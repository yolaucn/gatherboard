import SwiftUI
import AppKit
import BoardCore

// Every index write uses the same queue, including explicit saves and exit flushing.
// Keeping the last successful snapshot here also makes attachment archiving incremental.
private final class LibraryWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Gatherboard.library-writer", qos: .utility)
    private var lastSaved: BoardLibrary?
    private var root: URL?

    func remember(_ library: BoardLibrary, repository: LibraryRepository) {
        queue.sync { lastSaved = library; root = repository.root }
    }
    private func write(_ library: BoardLibrary, repository: LibraryRepository) throws {
        try repository.save(library, archivingChangesFrom: root == repository.root ? lastSaved : nil)
        lastSaved = library; root = repository.root
    }
    func save(_ library: BoardLibrary, repository: LibraryRepository) throws {
        try queue.sync { try write(library, repository: repository) }
    }
    func enqueue(_ library: BoardLibrary, repository: LibraryRepository,
                 completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        queue.async { completion(Result { try self.write(library, repository: repository) }) }
    }
}

@MainActor
final class BoardStore: ObservableObject {
    @Published var library = BoardLibrary()
    @Published var selectedProject: UUID?
    @Published var tab: BoardTab = .tasks
    @Published var folder = ""
    @Published var snapshot = DiskSnapshot()
    @Published var selectedFiles = Set<String>()
    @Published var selectedNote: UUID?
    @Published var busy = false
    @Published var ready = false
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var repository: LibraryRepository
    @Published private(set) var hasUnsavedNotes = false
    private let writer = LibraryWriter()
    private var noteSaveTask: Task<Void, Never>?
    private var noteRevision = 0
    private var refreshTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var lastScanError: String?
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let defaultRoot = support.appendingPathComponent("归拢", isDirectory: true)
        let root: URL
        let usesDefault: Bool
        if let index = arguments.firstIndex(of: "--library"), arguments.count > index + 1 {
            root = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            usesDefault = false
        } else if let path = UserDefaults.standard.string(forKey: "library.path") {
            root = URL(fileURLWithPath: path, isDirectory: true); usesDefault = root.standardized.path == defaultRoot.standardized.path
        } else {
            root = defaultRoot; usesDefault = true
        }
        repository = LibraryRepository(root: root)
        load()
        if ready, usesDefault { UserDefaults.standard.removeObject(forKey: "library.path") }
    }

    var project: BoardProject? { library.projects.first { $0.id == selectedProject } }
    var visibleFiles: [DiskFile] {
        folder.isEmpty ? snapshot.files : snapshot.files.filter { $0.folder == folder || $0.folder.hasPrefix(folder + "/") }
    }
    var chosenFiles: [DiskFile] { visibleFiles.filter { selectedFiles.contains($0.id) } }

    func load() {
        do {
            library = try repository.open(); writer.remember(library, repository: repository); ready = true
            let remembered = UserDefaults.standard.string(forKey: "selectedProject").flatMap(UUID.init(uuidString:))
            selectedProject = library.projects.first { $0.id == remembered }?.id ?? library.projects.first?.id
            refresh()
        } catch { ready = false; errorMessage = error.localizedDescription }
    }

    func select(_ id: UUID) {
        selectedProject = id; folder = ""; selectedFiles = []; selectedNote = nil; snapshot = DiskSnapshot()
        UserDefaults.standard.set(id.uuidString, forKey: "selectedProject")
        refresh()
    }

    func refresh() {
        guard ready, !busy, let project else { return }
        refreshTask?.cancel()
        let repository = repository
        refreshTask = Task {
            do {
                let result = try await Task.detached(priority: .utility) { try repository.snapshot(project) }.value
                guard !Task.isCancelled, selectedProject == project.id else { return }
                if result.files != snapshot.files || result.folders != snapshot.folders { snapshot = result }
                if !folder.isEmpty && !result.folders.contains(folder) { folder = "" }
                selectedFiles.formIntersection(Set(result.files.map(\.id)))
                lastScanError = nil
            } catch {
                guard !Task.isCancelled, selectedProject == project.id else { return }
                if lastScanError != error.localizedDescription { errorMessage = error.localizedDescription; lastScanError = error.localizedDescription }
            }
        }
    }

    func updateProject(_ change: (inout BoardProject) -> Void) {
        guard flushPendingNotes() else { return }
        guard ready, let index = library.projects.firstIndex(where: { $0.id == selectedProject }) else { return }
        var next = library; change(&next.projects[index])
        do { try writer.save(next, repository: repository); library = next }
        catch { errorMessage = error.localizedDescription }
    }

    func updateNote(_ id: UUID, change: (inout BoardNote) -> Void) {
        guard ready,
              let projectIndex = library.projects.firstIndex(where: { $0.notes.contains { $0.id == id } }),
              let noteIndex = library.projects[projectIndex].notes.firstIndex(where: { $0.id == id }) else { return }
        var note = library.projects[projectIndex].notes[noteIndex]
        change(&note)
        guard note != library.projects[projectIndex].notes[noteIndex] else { return }
        note.updated = Date()
        library.projects[projectIndex].notes[noteIndex] = note
        noteRevision += 1; hasUnsavedNotes = true
        noteSaveTask?.cancel()
        noteSaveTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            self?.saveNotesInBackground()
        }
    }

    private func saveNotesInBackground() {
        guard hasUnsavedNotes else { return }
        let revision = noteRevision, root = repository.root
        writer.enqueue(library, repository: repository) { [weak self] result in
            Task { @MainActor in
                guard let self, self.repository.root == root,
                      self.noteRevision == revision, self.hasUnsavedNotes else { return }
                switch result {
                case .success: self.hasUnsavedNotes = false
                case .failure(let error): self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    @discardableResult func flushPendingNotes() -> Bool {
        NotificationCenter.default.post(name: .flushNoteEditors, object: nil)
        noteSaveTask?.cancel(); noteSaveTask = nil
        guard hasUnsavedNotes else { return true }
        do {
            try writer.save(library, repository: repository)
            hasUnsavedNotes = false
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func createProject(_ name: String) {
        guard flushPendingNotes() else { return }
        do {
            let project = try repository.createProject(name: name, color: library.projects.count % 8)
            var next = library; next.projects.append(project)
            do { try writer.save(next, repository: repository) }
            catch { try? repository.trashProject(project); throw error }
            library = next; select(project.id)
        } catch { errorMessage = error.localizedDescription }
    }

    func renameProject(_ name: String) {
        guard flushPendingNotes() else { return }
        guard let project, let index = library.projects.firstIndex(where: { $0.id == project.id }) else { return }
        do {
            let renamed = try repository.renameProject(project, to: name)
            var next = library; next.projects[index] = renamed
            do { try writer.save(next, repository: repository) }
            catch {
                // Restore the original directory if metadata cannot be committed.
                try? FileManager.default.moveItem(at: repository.projectURL(renamed), to: repository.projectURL(project))
                throw error
            }
            library = next; refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteProject() {
        guard flushPendingNotes() else { return }
        guard let project else { return }
        let alert = NSAlert()
        alert.messageText = "删除项目「\(project.name)」？"
        alert.informativeText = "任务、备忘和链接将从看板移除，整个项目文件夹会移到系统废纸篓。建议先导出完整备份。"
        alert.alertStyle = .warning; alert.addButton(withTitle: "移到废纸篓"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            var next = library; next.projects.removeAll { $0.id == project.id }
            // Persist first, and roll metadata back if the filesystem operation fails.
            try writer.save(next, repository: repository)
            do { try repository.trashProject(project) }
            catch { try writer.save(library, repository: repository); throw error }
            library = next; selectedProject = next.projects.first?.id; snapshot = DiskSnapshot(); folder = ""; selectedFiles = []; refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func message(_ value: String) {
        noticeTask?.cancel(); notice = value
        noticeTask = Task { try? await Task.sleep(nanoseconds: 4_000_000_000); if !Task.isCancelled { notice = nil } }
    }

    func fileJob<T: Sendable>(_ operation: @escaping @Sendable (LibraryRepository) throws -> T, completed: @escaping (T) -> Void) {
        guard !busy, ready, flushPendingNotes() else { return }
        refreshTask?.cancel(); busy = true
        let repository = repository
        Task {
            do {
                let value = try await Task.detached(priority: .userInitiated) { try operation(repository) }.value
                busy = false; completed(value); refresh()
            } catch { busy = false; errorMessage = error.localizedDescription; refresh() }
        }
    }

    func importFiles(_ urls: [URL]) {
        guard let project, !urls.isEmpty else { return }
        let folder = folder
        fileJob({ try $0.importFiles(urls, into: folder, project: project) }) { self.report($0, verb: "导入") }
    }

    func report(_ result: ImportResult, verb: String) {
        message("已\(verb) \(result.imported) 项")
        if !result.failures.isEmpty { errorMessage = "已\(verb) \(result.imported) 项，以下项目失败：\n" + result.failures.joined(separator: "\n") }
    }

    func chooseImport() {
        let panel = NSOpenPanel(); panel.title = "导入文件或文件夹（复制到资料库）"
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { importFiles(panel.urls) }
    }

    func pasteFiles() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            importFiles(urls); return
        }
        guard let project, let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff), let png = representation.representation(using: .png, properties: [:]) else {
            message("剪贴板中没有图片或本地文件"); return
        }
        let folder = folder
        fileJob({ try $0.writeImage(png, into: folder, project: project) }) { self.message("图片已保存到磁盘") }
    }

    func copyFiles(_ files: [DiskFile]) {
        guard !files.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(files.map { $0.url as NSURL })
        message("已复制 \(files.count) 个文件，可在 Finder 中粘贴")
    }

    func duplicate(_ files: [DiskFile]) {
        guard let project else { return }
        let folder = folder
        fileJob({ try $0.importFiles(files.map(\.url), into: folder, project: project) }) { self.report($0, verb: "复制") }
    }

    func exportFiles(_ files: [DiskFile]) {
        guard let project, !files.isEmpty else { return }
        let panel = NSOpenPanel(); panel.title = "复制文件到…"; panel.canChooseFiles = false
        panel.canChooseDirectories = true; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        fileJob({ try $0.exportFiles(files.map(\.url), to: destination, project: project) }) { self.report($0, verb: "导出") }
    }

    func moveFiles(_ files: [DiskFile], to folder: String) {
        guard let project else { return }
        fileJob({ try $0.move(files.map(\.url), into: folder, project: project) }) { self.selectedFiles = []; self.message("文件已移动") }
    }

    func deleteFiles(_ urls: [URL], permanently: Bool) {
        guard let project, !urls.isEmpty else { return }
        let alert = NSAlert(); alert.alertStyle = .warning
        alert.messageText = permanently ? "永久删除这 \(urls.count) 项？" : "将这 \(urls.count) 项移到废纸篓？"
        alert.informativeText = (permanently ? "将直接删除磁盘上的真实文件，无法从废纸篓恢复。\n" : "会移动磁盘上的真实文件，可从系统废纸篓恢复。\n") + urls.prefix(6).map(\.lastPathComponent).joined(separator: "\n")
        alert.addButton(withTitle: permanently ? "永久删除" : "移到废纸篓"); alert.addButton(withTitle: "取消")
        if permanently { alert.buttons.first?.hasDestructiveAction = true }
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        fileJob({ try $0.delete(urls, project: project, permanently: permanently) }) {
            self.selectedFiles = []; self.message(permanently ? "已从磁盘永久删除" : "已移到废纸篓")
        }
    }

    func createFolder(_ name: String) {
        guard let project else { return }
        do { try repository.createFolder(name, parent: folder, in: project); folder = folder.isEmpty ? name : folder + "/" + name; refresh() }
        catch { errorMessage = error.localizedDescription }
    }

    func renameFile(_ url: URL, to name: String) {
        guard let project else { return }
        do { try repository.rename(url, to: name, project: project); selectedFiles = []; refresh() }
        catch { errorMessage = error.localizedDescription }
    }

    func backup() {
        let panel = NSOpenPanel(); panel.title = "选择完整备份的保存位置"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        fileJob({ try $0.backup(to: url) }) { output in
            self.message("完整备份已保存（含原始文件）"); NSWorkspace.shared.activateFileViewerSelecting([output])
        }
    }

    func restore() {
        let panel = NSOpenPanel(); panel.title = "选择 .boardbackup 备份（合并导入，不覆盖当前项目）"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.treatsFilePackagesAsDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard flushPendingNotes() else { return }
        let library = library
        fileJob({ try $0.restore(from: url, into: library) }) { self.library = $0; self.selectedProject = $0.projects.last?.id; self.folder = ""; self.selectedFiles = []; self.message("备份已合并导入") }
    }

    func chooseLibrary() {
        let panel = NSOpenPanel(); panel.title = "选择资料目录（可新建目录）"
        panel.prompt = "打开资料库"; panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard flushPendingNotes() else { return }
        do {
            let candidate = LibraryRepository(root: url)
            let library = try candidate.open()
            writer.remember(library, repository: candidate)
            refreshTask?.cancel(); repository = candidate; self.library = library; ready = true
            selectedProject = library.projects.first?.id; folder = ""; selectedFiles = []; selectedNote = nil; snapshot = DiskSnapshot()
            UserDefaults.standard.set(candidate.root.path, forKey: "library.path"); refresh()
        } catch { errorMessage = error.localizedDescription }
    }
}

enum BoardTab: String, CaseIterable {
    case tasks = "任务", notes = "备忘", links = "链接", files = "文件"
}

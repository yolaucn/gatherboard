import Foundation
import Darwin

/// Only paths inside this explicit, user-visible library may be mutated.
/// The application does not use an App Sandbox container or a browser database.
public struct LibraryRepository: Sendable {
    public let root: URL
    private var fm: FileManager { .default }
    public var manifestURL: URL { root.appendingPathComponent("library.json") }
    public var projectsURL: URL { root.appendingPathComponent("Projects", isDirectory: true) }

    public init(root: URL) { self.root = Self.canonicalURL(root) }

    // Resolve an existing ancestor even when the final directory hasn't been created.
    // macOS may expose the same directory through /var and /private/var.
    private static func canonicalURL(_ input: URL) -> URL {
        var ancestor = input.standardized
        var remaining: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            remaining.append(ancestor.lastPathComponent); ancestor.deleteLastPathComponent()
        }
        let base: URL
        if let resolved = Darwin.realpath(ancestor.path, nil) {
            base = URL(fileURLWithPath: String(cString: resolved)); free(resolved)
        } else { base = ancestor.resolvingSymlinksInPath() }
        return remaining.reversed().reduce(base) { $0.appendingPathComponent($1) }
    }

    public func open() throws -> BoardLibrary {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try checkPath(projectsURL)
        try fm.createDirectory(at: projectsURL, withIntermediateDirectories: true)
        try checkPath(manifestURL)
        if !fm.fileExists(atPath: manifestURL.path) {
            // Never silently replace a missing manifest when existing project files remain.
            guard try fm.contentsOfDirectory(atPath: projectsURL.path).isEmpty else { throw BoardError.corruptLibrary }
            let library = BoardLibrary(); try save(library); return library
        }
        let library = try JSONDecoder().decode(BoardLibrary.self, from: Data(contentsOf: manifestURL))
        try validate(library)
        return library
    }

    public func validate(_ library: BoardLibrary) throws {
        guard library.version == 1 else { throw BoardError.unsupportedVersion }
        guard Set(library.projects.map(\.id)).count == library.projects.count,
              Set(library.projects.map(\.directory)).count == library.projects.count else { throw BoardError.corruptLibrary }
        for project in library.projects {
            try Self.validateName(project.name)
            try Self.validateName(project.directory)
            try checkPath(projectsURL.appendingPathComponent(project.directory))
        }
    }

    public func save(_ library: BoardLibrary) throws {
        try validate(library)
        try checkPath(manifestURL)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: manifestURL, options: .atomic)
    }

    public static func validateName(_ name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == name, !name.hasPrefix("."), name.utf8.count <= 180,
              name.rangeOfCharacter(from: CharacterSet(charactersIn: "/:\0").union(.newlines).union(.controlCharacters)) == nil
        else { throw BoardError.invalidName }
    }

    public func checkPath(_ url: URL) throws {
        let candidate = url.standardized
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else { throw BoardError.unsafePath }
        let resolved = Self.canonicalURL(candidate)
        guard resolved.path == candidate.path else { throw BoardError.unsafePath }
        var cursor = candidate
        while cursor.path != root.path {
            let attributes = try? fm.attributesOfItem(atPath: cursor.path)
            if attributes?[.type] as? FileAttributeType == .typeSymbolicLink { throw BoardError.unsafePath }
            cursor.deleteLastPathComponent()
        }
    }

    public func projectURL(_ project: BoardProject) throws -> URL {
        try Self.validateName(project.directory)
        let url = projectsURL.appendingPathComponent(project.directory, isDirectory: true)
        try checkPath(url)
        return url
    }

    public func folderURL(_ folder: String, in project: BoardProject) throws -> URL {
        let base = try projectURL(project)
        if folder.isEmpty { return base }
        for component in folder.components(separatedBy: "/") { try Self.validateName(component) }
        let url = base.appendingPathComponent(folder, isDirectory: true)
        try checkPath(url)
        return url
    }

    public func createProject(name: String, color: Int) throws -> BoardProject {
        try Self.validateName(name)
        let project = BoardProject(name: name, color: color)
        try fm.createDirectory(at: projectURL(project), withIntermediateDirectories: false)
        return project
    }

    public func renameProject(_ project: BoardProject, to name: String) throws -> BoardProject {
        try Self.validateName(name)
        var renamed = project
        renamed.name = name
        renamed.directory = name + "--" + UUID().uuidString.prefix(8).lowercased()
        try fm.moveItem(at: projectURL(project), to: projectURL(renamed))
        return renamed
    }

    public func createFolder(_ name: String, parent: String = "", in project: BoardProject) throws {
        try Self.validateName(name)
        let url = try folderURL(parent, in: project).appendingPathComponent(name, isDirectory: true)
        try checkPath(url)
        try fm.createDirectory(at: url, withIntermediateDirectories: false)
    }

    public func snapshot(_ project: BoardProject) throws -> DiskSnapshot {
        let base = try projectURL(project)
        guard fm.fileExists(atPath: base.path) else { throw BoardError.missingProject }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        var traversalError: Error?
        guard let enumerator = fm.enumerator(at: base, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles], errorHandler: { _, error in
            traversalError = error; return false
        }) else { throw BoardError.missingProject }
        var result = DiskSnapshot()
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            let relative = String(url.path.dropFirst(base.path.count + 1))
            if values.isDirectory == true { result.folders.append(relative) }
            if values.isRegularFile == true {
                result.files.append(DiskFile(url: url, relativePath: relative, size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate ?? .distantPast))
            }
        }
        if let traversalError { throw traversalError }
        result.folders.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        result.files.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return result
    }

    private func uniqueDestination(name: String, in folder: URL) -> URL {
        let original = folder.appendingPathComponent(name)
        let ext = original.pathExtension
        let stem = ext.isEmpty ? name : original.deletingPathExtension().lastPathComponent
        var url = original; var index = 2
        while fm.fileExists(atPath: url.path) || (try? fm.attributesOfItem(atPath: url.path)) != nil {
            url = folder.appendingPathComponent(stem + " (\(index))" + (ext.isEmpty ? "" : "." + ext)); index += 1
        }
        return url
    }

    private func validateTree(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
        guard values.isSymbolicLink != true else { throw BoardError.unsafePath }
        if values.isDirectory == true {
            for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) { try validateTree(child) }
        } else if values.isRegularFile != true { throw BoardError.unsafePath }
    }

    public func importFiles(_ urls: [URL], into folder: String, project: BoardProject) throws -> ImportResult {
        let target = try folderURL(folder, in: project)
        guard fm.fileExists(atPath: target.path) else { throw BoardError.missingProject }
        var result = ImportResult()
        for source in urls {
            do {
                try Self.validateName(source.lastPathComponent)
                try validateTree(source)
                let resolvedSource = Self.canonicalURL(source)
                // Copying a parent into its child would recurse indefinitely.
                guard target.path != resolvedSource.path, !target.path.hasPrefix(resolvedSource.path + "/") else { throw BoardError.unsafePath }
                let destination = uniqueDestination(name: source.lastPathComponent, in: target)
                try checkPath(destination)
                do { try fm.copyItem(at: source, to: destination) }
                catch { try? fm.removeItem(at: destination); throw error }
                result.imported += 1
            } catch { result.failures.append(source.lastPathComponent + "：" + error.localizedDescription) }
        }
        return result
    }

    public func writeImage(_ data: Data, into folder: String, project: BoardProject) throws {
        let target = try folderURL(folder, in: project)
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = uniqueDestination(name: "粘贴图片-\(formatter.string(from: Date())).png", in: target)
        try checkPath(url)
        try data.write(to: url, options: .atomic)
    }

    public func rename(_ source: URL, to name: String, project: BoardProject) throws {
        try Self.validateName(name)
        try verifyFile(source, project: project)
        let destination = source.deletingLastPathComponent().appendingPathComponent(name)
        try checkPath(destination)
        if source.path != destination.path { try fm.moveItem(at: source, to: destination) }
    }

    public func move(_ sources: [URL], into folder: String, project: BoardProject) throws {
        let destination = try folderURL(folder, in: project)
        for source in sources {
            try verifyFile(source, project: project)
            guard source.path != destination.path, !destination.path.hasPrefix(source.path + "/") else { throw BoardError.unsafePath }
        }
        for source in sources where source.deletingLastPathComponent().path != destination.path {
            try fm.moveItem(at: source, to: uniqueDestination(name: source.lastPathComponent, in: destination))
        }
    }

    public func verifyFile(_ url: URL, project: BoardProject) throws {
        let base = try projectURL(project)
        guard url.standardized.path.hasPrefix(base.path + "/") else { throw BoardError.unsafePath }
        try checkPath(url)
    }

    public func delete(_ urls: [URL], project: BoardProject, permanently: Bool) throws {
        for url in urls { try verifyFile(url, project: project) }
        for url in urls {
            if permanently { try fm.removeItem(at: url) }
            else { try fm.trashItem(at: url, resultingItemURL: nil) }
        }
    }

    public func trashProject(_ project: BoardProject) throws {
        let url = try projectURL(project)
        try fm.trashItem(at: url, resultingItemURL: nil)
    }

    public func exportFiles(_ files: [URL], to destination: URL, project: BoardProject) throws -> ImportResult {
        let target = Self.canonicalURL(destination)
        guard target.path != root.path, !target.path.hasPrefix(root.path + "/") else { throw BoardError.nestedBackup }
        var result = ImportResult()
        for source in files {
            do {
                try verifyFile(source, project: project)
                try validateTree(source)
                let output = uniqueDestination(name: source.lastPathComponent, in: target)
                do { try fm.copyItem(at: source, to: output) }
                catch { try? fm.removeItem(at: output); throw error }
                result.imported += 1
            } catch { result.failures.append(source.lastPathComponent + "：" + error.localizedDescription) }
        }
        return result
    }

    public func backup(to parent: URL) throws -> URL {
        let target = Self.canonicalURL(parent)
        guard target.path != root.path, !target.path.hasPrefix(root.path + "/") else { throw BoardError.nestedBackup }
        try validateTree(root)
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let output = uniqueDestination(name: "归拢-\(formatter.string(from: Date())).boardbackup", in: target)
        do { try fm.copyItem(at: root, to: output) }
        catch { try? fm.removeItem(at: output); throw error }
        return output
    }

    /// Merge a full backup, including original files, without overwriting existing projects.
    public func restore(from backup: URL, into library: BoardLibrary) throws -> BoardLibrary {
        let source = LibraryRepository(root: backup)
        guard source.root.path != root.path,
              !source.root.path.hasPrefix(root.path + "/"), !root.path.hasPrefix(source.root.path + "/") else { throw BoardError.nestedBackup }
        try source.validateTree(source.root)
        // Reading a backup must never create or alter files in that backup.
        let incoming = try JSONDecoder().decode(BoardLibrary.self, from: Data(contentsOf: source.manifestURL))
        try source.validate(incoming)
        var merged = library
        var copied: [URL] = []
        do {
            for item in incoming.projects {
                var project = item; project.id = UUID()
                if merged.projects.contains(where: { $0.name == project.name }) { project.name += "（导入）" }
                project.directory = project.name + "--" + UUID().uuidString.prefix(8).lowercased()
                let destination = try projectURL(project)
                copied.append(destination)
                try fm.copyItem(at: source.projectURL(item), to: destination)
                merged.projects.append(project)
            }
            try save(merged)
        } catch {
            for url in copied { try? fm.removeItem(at: url) }
            throw error
        }
        return merged
    }
}

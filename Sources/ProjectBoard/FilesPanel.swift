import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO
import BoardCore

struct FilesPanel: View {
    @EnvironmentObject private var store: BoardStore
    let project: BoardProject
    @State private var newFolder = false
    @State private var renameTarget: DiskFile?
    @State private var preview: DiskFile?
    @State private var dropping = false
    @State private var search = ""
    @FocusState private var fileAreaFocused: Bool
    private var files: [DiskFile] { store.visibleFiles.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }
    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 12, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            folderBar
            Button(action: store.chooseImport) {
                HStack(spacing: 9) { Image(systemName: "square.and.arrow.down"); Text(dropping ? "松开，复制到当前文件夹" : "把照片 / 文件拖到这里，或点击选择") }.foregroundColor(dropping ? Theme.accent : Theme.muted).frame(maxWidth: .infinity).frame(height: 62)
                    .background(dropping ? Theme.accent.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(dropping ? Theme.accent : Theme.border, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            }.buttonStyle(.plain)
            .onDrop(of: [UTType.fileURL], isTargeted: $dropping, perform: acceptDrop)
            HStack(spacing: 12) {
                if !store.selectedFiles.isEmpty {
                    Text("已选 \(store.chosenFiles.count) 项").font(.system(size: 11)).foregroundColor(Theme.muted)
                    Button("复制") { store.copyFiles(store.chosenFiles) }
                    Button("导出…") { store.exportFiles(store.chosenFiles) }
                    Button("删除…") { store.deleteFiles(store.chosenFiles.map(\.url), permanently: false) }
                    Button("取消选择") { store.selectedFiles = [] }
                } else {
                    Text("\(store.visibleFiles.count) 个文件").font(.system(size: 11)).foregroundColor(Theme.muted)
                    Button("粘贴图片 / 文件", action: store.pasteFiles)
                }
                Spacer(minLength: 4)
                Image(systemName: "magnifyingglass").foregroundColor(Theme.muted)
                TextField("搜索文件", text: $search).textFieldStyle(.plain).frame(width: 110)
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("刷新目录")
            }.buttonStyle(.plain).font(.system(size: 11)).foregroundColor(Theme.accent)
            ScrollView {
                if files.isEmpty {
                    VStack(spacing: 10) { Image(systemName: "photo.on.rectangle.angled").font(.system(size: 30, weight: .ultraLight)); Text(search.isEmpty ? "还没有文件，导入后原图会保存在这里" : "没有匹配的文件").font(.system(size: 13)) }.foregroundColor(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 42)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(files) { file in
                        fileCard(file)
                    }
                }.padding(2)
            }.frame(maxHeight: .infinity)
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "internaldrive").foregroundColor(Theme.accent)
                Text("文件已保存在本地真实目录。导入会复制原文件；复制后可粘贴到 Finder。右键可重命名、移动、导出或永久删除。").font(.system(size: 11)).lineSpacing(4).foregroundColor(Color(hex: 0x7A6449))
            }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: 0xFAF3EA), in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: 0xF0E2CD)))
        }
        .focusable().focused($fileAreaFocused).focusEffectDisabledIfAvailable()
        .onCopyCommand { store.chosenFiles.map { NSItemProvider(object: $0.url as NSURL) } }
        .onPasteCommand(of: [UTType.fileURL, UTType.png, UTType.tiff]) { _ in store.pasteFiles() }
        .onDeleteCommand { if !store.chosenFiles.isEmpty { store.deleteFiles(store.chosenFiles.map(\.url), permanently: false) } }
        .sheet(isPresented: $newFolder) { NameSheet(title: "新建文件夹", hint: "在当前分类下创建真实文件夹。", submit: store.createFolder) }
        .sheet(item: $renameTarget) { file in NameSheet(title: "重命名文件", name: file.name) { store.renameFile(file.url, to: $0) } }
        .sheet(item: $preview) { file in FilePreview(file: file) }
        .onChange(of: store.folder) { _ in search = ""; store.selectedFiles = [] }
        .onChange(of: search) { _ in store.selectedFiles = [] }
    }

    private var folderBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("全部", count: store.snapshot.files.count, selected: store.folder.isEmpty) { store.folder = "" }
                ForEach(store.snapshot.folders, id: \.self) { folder in
                    chip(folder, count: store.snapshot.files.filter { $0.folder == folder || $0.folder.hasPrefix(folder + "/") }.count, selected: store.folder == folder) { store.folder = folder }
                        .contextMenu {
                            Button("在 Finder 中打开") { if let url = try? store.repository.folderURL(folder, in: project) { NSWorkspace.shared.open(url) } }
                            Divider()
                            Button("将文件夹移到废纸篓…", role: .destructive) { if let url = try? store.repository.folderURL(folder, in: project) { store.deleteFiles([url], permanently: false) } }
                            Button("永久删除文件夹…", role: .destructive) { if let url = try? store.repository.folderURL(folder, in: project) { store.deleteFiles([url], permanently: true) } }
                        }
                }
                Button { newFolder = true } label: { Text("＋ 新建文件夹") }.buttonStyle(OutlinedButton(dashed: true))
            }.padding(1)
        }
    }

    private func chip(_ title: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) { Text(title); Text("\(count)").opacity(0.6) }.font(.system(size: 12)).padding(.horizontal, 12).frame(height: 31).foregroundColor(selected ? .white : Theme.ink).background(selected ? Theme.ink : Theme.selection, in: Capsule())
        }.buttonStyle(.plain)
    }

    private func fileCard(_ file: DiskFile) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Thumbnail(file: file)
                .aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity)
                .background(.white).clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(store.selectedFiles.contains(file.id) ? Theme.accent : Theme.border, lineWidth: store.selectedFiles.contains(file.id) ? 2 : 1))
                .overlay(alignment: .topTrailing) {
                    if store.selectedFiles.contains(file.id) { Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.accent).background(.white, in: Circle()).padding(7) }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { preview = file }
                .onTapGesture {
                    fileAreaFocused = true
                    if NSEvent.modifierFlags.contains(.command) { if store.selectedFiles.contains(file.id) { store.selectedFiles.remove(file.id) } else { store.selectedFiles.insert(file.id) } }
                    else { store.selectedFiles = [file.id] }
                }
                .onDrag { NSItemProvider(contentsOf: file.url) ?? NSItemProvider() }
            Text(file.name).font(.system(size: 11)).lineLimit(2).frame(height: 29, alignment: .topLeading).foregroundColor(Theme.ink)
        }.contextMenu {
            Button("预览") { preview = file }
            Button("用默认应用打开") { NSWorkspace.shared.open(file.url) }
            Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
            Divider()
            Button("复制文件 ⌘C") { store.copyFiles(contextFiles(file)) }
            Button("创建副本") { store.duplicate(contextFiles(file)) }
            Button("复制到…") { store.exportFiles(contextFiles(file)) }
            Button("重命名…") { renameTarget = file }
            Menu("移动到") {
                Button("项目根目录") { store.moveFiles(contextFiles(file), to: "") }
                ForEach(store.snapshot.folders, id: \.self) { folder in Button(folder) { store.moveFiles(contextFiles(file), to: folder) } }
            }
            Divider()
            Button("移到废纸篓…", role: .destructive) { store.deleteFiles(contextFiles(file).map(\.url), permanently: false) }
            Button("永久删除…", role: .destructive) { store.deleteFiles(contextFiles(file).map(\.url), permanently: true) }
        }
        .help(file.relativePath + " · " + ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file) + "\n双击预览 · ⌘点选可多选")
    }

    private func contextFiles(_ file: DiskFile) -> [DiskFile] { store.selectedFiles.contains(file.id) ? store.chosenFiles : [file] }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        // Resolve every dropped URL before starting a single import operation.
        let group = DispatchGroup(); let collector = DropCollector()
        for provider in providers {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                defer { group.leave() }
                if let data, let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL { collector.append(url) }
            }
        }
        let destinationProject = project.id; let destinationFolder = store.folder
        group.notify(queue: .main) {
            guard store.selectedProject == destinationProject, store.folder == destinationFolder else { store.message("目标已切换，请重新拖入文件"); return }
            store.importFiles(collector.urls)
        }
        return true
    }
}

private final class DropCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []
    func append(_ url: URL) { lock.lock(); defer { lock.unlock() }; storage.append(url) }
    var urls: [URL] { lock.lock(); defer { lock.unlock() }; return storage }
}

extension View {
    @ViewBuilder func focusEffectDisabledIfAvailable() -> some View {
        if #available(macOS 14, *) { self.focusEffectDisabled() } else { self }
    }
}

struct Thumbnail: View {
    let file: DiskFile
    @State private var thumbnail: NSImage?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white
                if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit().frame(width: geometry.size.width, height: geometry.size.height) }
                else { VStack(spacing: 9) { Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path)).resizable().frame(width: 42, height: 42); Text(file.url.pathExtension.uppercased()).font(.system(size: 10, weight: .medium)).foregroundColor(Theme.muted) } }
            }
        }.task(id: file.url.path + String(file.modified.timeIntervalSince1970)) {
            let url = file.url
            let decoded = await Task.detached(priority: .utility) { () -> CGImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 420, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
                return cg
            }.value
            guard !Task.isCancelled else { return }
            thumbnail = decoded.map { NSImage(cgImage: $0, size: .zero) }
        }
    }
}

struct FilePreview: View {
    let file: DiskFile
    @Environment(\.dismiss) private var dismiss
    @State private var image: NSImage?
    var body: some View {
        VStack(spacing: 16) {
            HStack { Text(file.name).font(.system(size: 14, weight: .semibold)).lineLimit(1); Spacer(); Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction) }
            if let image { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { VStack(spacing: 18) { Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path)).resizable().frame(width: 80, height: 80); Text("使用系统默认应用查看此文件").foregroundColor(Theme.muted); Button("打开文件") { NSWorkspace.shared.open(file.url) }.buttonStyle(DarkButton()) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
            HStack { Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)).foregroundColor(Theme.muted); Spacer(); Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } }.font(.system(size: 12))
        }.padding(20).frame(width: 720, height: 580).background(Theme.background)
        .task {
            let url = file.url
            let decoded = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1800, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
                return cg
            }.value
            guard !Task.isCancelled else { return }
            image = decoded.map { NSImage(cgImage: $0, size: .zero) }
        }
    }
}

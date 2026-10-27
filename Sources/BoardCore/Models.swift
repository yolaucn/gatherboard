import Foundation

public struct BoardTask: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var text: String
    public var done = false
    public var due: Date?
    public init(text: String, due: Date? = nil) { self.text = text; self.due = due }
}

public struct BoardNote: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var title = ""
    public var text = ""
    public var richText: Data?
    public var updated = Date()
    public init() {}
    public var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? (text.split(separator: "\n").first.map(String.init) ?? "新备忘") : title
    }
}

public struct BoardLink: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var title: String
    public var url: String
    public init(title: String, url: String) { self.title = title; self.url = url }
}

public struct BoardProject: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var color: Int
    public var directory: String
    public var tasks: [BoardTask] = []
    public var notes: [BoardNote] = []
    public var links: [BoardLink] = []
    public init(name: String, color: Int = 0) {
        self.name = name; self.color = color
        self.directory = name + "--" + UUID().uuidString.prefix(8).lowercased()
    }
    public var pendingCount: Int { tasks.filter { !$0.done }.count }
}

public struct BoardLibrary: Codable, Equatable, Sendable {
    public var version = 1
    public var projects: [BoardProject] = []
    public init() {}
}

public struct DiskFile: Identifiable, Equatable, Sendable {
    public let url: URL
    public let relativePath: String
    public let size: Int64
    public let modified: Date
    public var id: String { relativePath }
    public var name: String { url.lastPathComponent }
    public var folder: String { (relativePath as NSString).deletingLastPathComponent }
    public init(url: URL, relativePath: String, size: Int64, modified: Date) {
        self.url = url; self.relativePath = relativePath; self.size = size; self.modified = modified
    }
}

public struct DiskSnapshot: Sendable {
    public var files: [DiskFile] = []
    public var folders: [String] = []
    public init() {}
}

public struct ImportResult: Sendable {
    public var imported = 0
    public var failures: [String] = []
    public init() {}
}

public enum BoardError: LocalizedError {
    case invalidName, unsafePath, unsupportedVersion, corruptLibrary, nestedBackup, missingProject
    public var errorDescription: String? {
        switch self {
        case .invalidName: return "名称不能为空，不能以点开头，也不能包含 /、: 或换行。"
        case .unsafePath: return "操作已停止：路径越过资料目录，或包含符号链接。"
        case .unsupportedVersion: return "这个资料库版本不受支持，请使用更新版本的归拢。"
        case .corruptLibrary: return "资料库结构不正确，原文件已保留。请检查 library.json 或从备份恢复。"
        case .nestedBackup: return "备份位置不能在当前资料库或源备份目录里面。"
        case .missingProject: return "项目目录不存在，请在 Finder 检查或从备份恢复。"
        }
    }
}

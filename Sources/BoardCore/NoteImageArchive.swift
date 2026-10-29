import Foundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

extension LibraryRepository {
    /// RTFD contains the attachment bytes, not references to the original image URLs.
    /// Keep those embedded bytes for compatibility, and archive independent image files
    /// beside the project. Hidden directories are excluded from the Files snapshot,
    /// but included when projects are renamed, trashed, backed up, or restored.
    func archiveNoteImages(in library: BoardLibrary, comparedTo previous: BoardLibrary? = nil) throws {
        for project in library.projects {
            let oldProject = previous?.projects.first { $0.id == project.id && $0.directory == project.directory }
            let oldNotes = Dictionary((oldProject?.notes ?? []).map { ($0.id, $0.richText) }, uniquingKeysWith: { _, last in last })
            for note in project.notes {
                guard let data = note.richText else { continue }
                // A title edit must not unpack and hash every image in the library.
                if let oldData = oldNotes[note.id], oldData == data { continue }
                guard
                      let package = FileWrapper(serializedRepresentation: data), package.isDirectory else { continue }
                try archiveImages(in: package, project: project)
            }
        }
    }

    private func archiveImages(in wrapper: FileWrapper, project: BoardProject) throws {
        if wrapper.isDirectory {
            guard let children = wrapper.fileWrappers else { return }
            for child in children.values {
                try archiveImages(in: child, project: project)
            }
            return
        }
        guard wrapper.isRegularFile, let data = wrapper.regularFileContents,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source),
              let type = UTType(identifier as String),
              let ext = type.preferredFilenameExtension else { return }

        let fm = FileManager.default
        let base = try projectURL(project)
        guard fm.fileExists(atPath: base.path) else { throw BoardError.missingProject }
        let directory = base.appendingPathComponent(".note-attachments", isDirectory: true)
        try checkPath(directory)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        // Content-based names avoid duplicates on each autosave or across notes.
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let destination = directory.appendingPathComponent(digest + "." + ext)
        try checkPath(destination)
        if fm.fileExists(atPath: destination.path) {
            guard try fm.attributesOfItem(atPath: destination.path)[.type] as? FileAttributeType == .typeRegular else {
                throw BoardError.unsafePath
            }
        } else {
            try data.write(to: destination, options: .atomic)
        }
        // Retain archived images when a note is edited/deleted so undo can restore them.
    }
}

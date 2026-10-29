import Foundation
import AppKit
import BoardCore

final class LibraryRepositoryTests {
    private var fixture: URL!
    private var repository: LibraryRepository!
    func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory.appendingPathComponent("ProjectBoardTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        repository = LibraryRepository(root: fixture.appendingPathComponent("资料库"))
        _ = try repository.open()
    }
    func tearDownWithError() throws {
        // This unique directory was created by this test and never contains user data.
        try FileManager.default.removeItem(at: fixture)
    }
    private func project(_ name: String = "售后体验日") throws -> BoardProject { try repository.createProject(name: name, color: 4) }
    private func source(_ name: String = "原图.png", bytes: Data = Data([0, 1, 2, 3, 255])) throws -> URL {
        let url = fixture.appendingPathComponent(name); try bytes.write(to: url); return url
    }

    func testAtomicMetadataRoundTrip() throws {
        var library = BoardLibrary(); var p = try project()
        p.tasks.append(BoardTask(text: "配置环境", due: Date(timeIntervalSince1970: 123456)))
        var note = BoardNote(); note.title = "备忘"; note.text = "第一行\n第二行"; note.richText = Data([1, 8, 9]); note.imageWidths = ["0": 300]; p.notes.append(note)
        p.links.append(BoardLink(title: "设计", url: "https://example.com")); library.projects.append(p)
        try repository.save(library)
        XCTAssertEqual(try repository.open(), library)
    }

    private func imageNote() throws -> (note: BoardNote, original: URL, bytes: Data) {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.bitmapData?.initialize(repeating: 255, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        let bytes = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let original = try source(bytes: bytes)
        let wrapper = FileWrapper(regularFileWithContents: try Data(contentsOf: original))
        wrapper.preferredFilename = original.lastPathComponent
        let text = NSAttributedString(attachment: NSTextAttachment(fileWrapper: wrapper))
        var note = BoardNote(); note.text = text.string
        note.richText = try XCTUnwrap(text.rtfd(from: NSRange(location: 0, length: text.length), documentAttributes: [:]))
        return (note, original, bytes)
    }

    private func archivedImages(_ project: BoardProject, in repo: LibraryRepository) throws -> [URL] {
        let directory = try repo.projectURL(project).appendingPathComponent(".note-attachments")
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    }

    private func assertEmbeddedImage(_ note: BoardNote, bytes: Data) throws {
        let data = try XCTUnwrap(note.richText)
        let text = try XCTUnwrap(NSAttributedString(rtfd: data, documentAttributes: nil))
        let attachment = try XCTUnwrap(text.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
        let embedded = try XCTUnwrap(attachment.fileWrapper?.regularFileContents)
        XCTAssertEqual(embedded, bytes)
        XCTAssertTrue(NSImage(data: embedded) != nil)
    }

    func testNoteImagesAreIndependentHiddenAndDeduplicated() throws {
        let image = try imageNote()
        var p = try project(); p.notes = [image.note]
        var library = BoardLibrary(); library.projects = [p]
        try repository.save(library)
        _ = try repository.importFiles([image.original], into: "", project: p)
        let visible = try repository.snapshot(p)
        XCTAssertEqual(visible.files.count, 1)
        XCTAssertTrue(visible.folders.isEmpty)
        try FileManager.default.removeItem(at: image.original)
        try repository.delete(visible.files.map(\.url), project: p, permanently: true)
        let archive = try XCTUnwrap(archivedImages(p, in: repository).first)
        XCTAssertEqual(try Data(contentsOf: archive), image.bytes)
        XCTAssertTrue(try repository.snapshot(p).files.isEmpty)
        XCTAssertTrue(try repository.snapshot(p).folders.isEmpty)
        var duplicate = image.note; duplicate.id = UUID(); duplicate.title = "同图另一条备忘"
        library.projects[0].notes.append(duplicate)
        try repository.save(library)
        try repository.save(library)
        XCTAssertEqual(try archivedImages(p, in: repository).count, 1)
        let reopened = try repository.open()
        for note in reopened.projects[0].notes { try assertEmbeddedImage(note, bytes: image.bytes) }
    }

    func testLegacyNoteImagesAreArchivedWithoutChangingMetadata() throws {
        let image = try imageNote()
        var p = try project(); p.notes = [image.note]
        var library = BoardLibrary(); library.projects = [p]
        let legacy = try JSONEncoder().encode(library)
        try legacy.write(to: repository.manifestURL)
        try FileManager.default.removeItem(at: image.original)
        XCTAssertEqual(try repository.open(), library)
        XCTAssertEqual(try Data(contentsOf: repository.manifestURL), legacy)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(archivedImages(p, in: repository).first)), image.bytes)
    }

    func testIncrementalArchiveSkipsUnchangedRichTextAndProcessesChanges() throws {
        let image = try imageNote()
        var p = try project(); p.notes = [image.note]
        var library = BoardLibrary(); library.projects = [p]
        try repository.save(library)
        let archive = try XCTUnwrap(archivedImages(p, in: repository).first)
        // Removing this fixture copy lets us detect whether a title-only save revisits it.
        // Opening the library still performs a complete repair pass.
        try FileManager.default.removeItem(at: archive)
        var edited = library
        edited.projects[0].notes[0].title = "只改标题"
        try repository.save(edited, archivingChangesFrom: library)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
        XCTAssertEqual(try JSONDecoder().decode(BoardLibrary.self, from: Data(contentsOf: repository.manifestURL)), edited)
        let rich = try XCTUnwrap(NSAttributedString(rtfd: XCTUnwrap(image.note.richText), documentAttributes: nil))
        let changed = NSMutableAttributedString(attributedString: rich)
        changed.append(NSAttributedString(string: "新增正文"))
        var next = edited
        next.projects[0].notes[0].richText = changed.rtfd(from: NSRange(location: 0, length: changed.length), documentAttributes: [:])
        try repository.save(next, archivingChangesFrom: edited)
        XCTAssertEqual(try Data(contentsOf: archive), image.bytes)
        try FileManager.default.removeItem(at: archive)
        XCTAssertEqual(try repository.open(), next)
        XCTAssertEqual(try Data(contentsOf: archive), image.bytes)
    }

    func testNoteImagesSurviveProjectRenameAndBackupToAnotherLibrary() throws {
        let image = try imageNote()
        var p = try project(); p.notes = [image.note]
        var library = BoardLibrary(); library.projects = [p]
        try repository.save(library)
        p = try repository.renameProject(p, to: "迁移后的项目")
        library.projects = [p]; try repository.save(library)
        let backup = try repository.backup(to: fixture)
        let target = LibraryRepository(root: fixture.appendingPathComponent("另一资料库"))
        let empty = try target.open()
        // Remove both the external source and the old project; restore must be self-contained.
        try FileManager.default.removeItem(at: image.original)
        try FileManager.default.removeItem(at: repository.projectURL(p))
        let restored = try target.restore(from: backup, into: empty)
        let restoredProject = try XCTUnwrap(restored.projects.first)
        XCTAssertEqual(try archivedImages(restoredProject, in: target).count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(archivedImages(restoredProject, in: target).first)), image.bytes)
        XCTAssertTrue(try target.snapshot(restoredProject).files.isEmpty)
        XCTAssertTrue(try target.snapshot(restoredProject).folders.isEmpty)
        try assertEmbeddedImage(XCTUnwrap(target.open().projects.first?.notes.first), bytes: image.bytes)
    }

    func testNoteImageArchiveFailurePreservesIndexAndRejectsSymlinks() throws {
        var p = try project()
        var library = BoardLibrary(); library.projects = [p]
        try repository.save(library)
        let before = try Data(contentsOf: repository.manifestURL)
        let image = try imageNote(); p.notes = [image.note]; library.projects = [p]
        let directory = try repository.projectURL(p).appendingPathComponent(".note-attachments")
        let outside = fixture.appendingPathComponent("外部附件", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: outside)
        XCTAssertThrowsError(try repository.save(library))
        XCTAssertEqual(try Data(contentsOf: repository.manifestURL), before)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        try FileManager.default.removeItem(at: directory)
        try repository.save(library)
        let saved = try Data(contentsOf: repository.manifestURL)
        let archive = try XCTUnwrap(archivedImages(p, in: repository).first)
        try FileManager.default.removeItem(at: archive)
        try FileManager.default.createSymbolicLink(at: archive, withDestinationURL: image.original)
        library.projects[0].notes[0].title = "尚未保存"
        XCTAssertThrowsError(try repository.save(library))
        XCTAssertEqual(try Data(contentsOf: repository.manifestURL), saved)
        XCTAssertEqual(try Data(contentsOf: image.original), image.bytes)
    }

    func testImportCopiesOriginalBytesAndDoesNotOverwriteNames() throws {
        let p = try project(); let original = try source()
        XCTAssertEqual(try repository.importFiles([original], into: "", project: p).imported, 1)
        XCTAssertEqual(try repository.importFiles([original], into: "", project: p).imported, 1)
        let files = try repository.snapshot(p).files
        XCTAssertEqual(Set(files.map(\.name)), ["原图.png", "原图 (2).png"])
        for file in files { XCTAssertEqual(try Data(contentsOf: file.url), try Data(contentsOf: original)) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }

    func testNestedDirectoryImportAndFinderChangesAreDiscovered() throws {
        let p = try project()
        let external = fixture.appendingPathComponent("素材/子目录", isDirectory: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try Data("真实文件".utf8).write(to: external.appendingPathComponent("图片.webp"))
        let result = try repository.importFiles([external.deletingLastPathComponent()], into: "", project: p)
        XCTAssertEqual(result.imported, 1)
        var snapshot = try repository.snapshot(p)
        XCTAssertEqual(snapshot.folders, ["素材", "素材/子目录"])
        XCTAssertEqual(snapshot.files.first?.relativePath, "素材/子目录/图片.webp")
        let direct = try repository.projectURL(p).appendingPathComponent("Finder新增.txt")
        try Data("外部更改".utf8).write(to: direct)
        snapshot = try repository.snapshot(p)
        XCTAssertEqual(snapshot.files.count, 2)
        try FileManager.default.removeItem(at: direct)
        XCTAssertEqual(try repository.snapshot(p).files.count, 1)
    }

    func testPermanentDeleteRemovesRealManagedFileButPreservesSource() throws {
        let p = try project(); let original = try source()
        _ = try repository.importFiles([original], into: "", project: p)
        let file = try XCTUnwrap(repository.snapshot(p).files.first)
        try repository.delete([file.url], project: p, permanently: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(try repository.snapshot(p).files.isEmpty)
    }

    func testDeletionRejectsOutsidePathsAndProjectRoot() throws {
        let p = try project(); let original = try source()
        XCTAssertThrowsError(try repository.delete([original], project: p, permanently: true))
        XCTAssertThrowsError(try repository.delete([repository.projectURL(p)], project: p, permanently: true))
        let root = repository.root
        XCTAssertThrowsError(try repository.delete([root], project: p, permanently: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }

    func testSymlinkAndTraversalProtection() throws {
        let p = try project(); let base = try repository.projectURL(p)
        let outside = try source("outside.txt")
        let link = base.appendingPathComponent("shortcut.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertTrue(try repository.snapshot(p).files.isEmpty)
        XCTAssertThrowsError(try repository.delete([link], project: p, permanently: true))
        XCTAssertThrowsError(try repository.folderURL("../outside", in: p))
        XCTAssertEqual(try repository.importFiles([link], into: "", project: p).failures.count, 1)
        XCTAssertThrowsError(try repository.backup(to: fixture))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testBrokenSymlinksAreRejected() throws {
        let p = try project(); let link = try repository.projectURL(p).appendingPathComponent("broken")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.appendingPathComponent("missing"))
        XCTAssertThrowsError(try repository.checkPath(link))
    }

    func testBackupIncludesOriginalFilesAndRestoreMergesWithoutOverwrite() throws {
        var library = BoardLibrary(); var p = try project(); p.tasks.append(BoardTask(text: "原任务")); library.projects = [p]
        try repository.save(library)
        try repository.createFolder("staging太阳码", in: p)
        _ = try repository.importFiles([source()], into: "staging太阳码", project: p)
        let backup = try repository.backup(to: fixture)
        let before = try Data(contentsOf: backup.appendingPathComponent("library.json"))
        let merged = try repository.restore(from: backup, into: library)
        XCTAssertEqual(merged.projects.count, 2)
        XCTAssertEqual(merged.projects[0], p)
        XCTAssertEqual(merged.projects[1].name, "售后体验日（导入）")
        XCTAssertNotEqual(merged.projects[0].directory, merged.projects[1].directory)
        let restored = try XCTUnwrap(repository.snapshot(merged.projects[1]).files.first)
        XCTAssertEqual(try Data(contentsOf: restored.url), Data([0, 1, 2, 3, 255]))
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("library.json")), before)
        XCTAssertEqual(try repository.open(), merged)
    }

    func testBackupInsideLibraryIsRejected() throws {
        XCTAssertThrowsError(try repository.backup(to: repository.projectsURL))
        XCTAssertThrowsError(try repository.restore(from: repository.root, into: BoardLibrary()))
    }

    func testCorruptManifestIsNotReplaced() throws {
        let broken = Data("{ broken json".utf8)
        try broken.write(to: repository.manifestURL)
        XCTAssertThrowsError(try repository.open())
        XCTAssertEqual(try Data(contentsOf: repository.manifestURL), broken)
    }

    func testMissingManifestWithExistingFilesIsNotSilentlyReset() throws {
        _ = try project()
        try FileManager.default.removeItem(at: repository.manifestURL)
        XCTAssertThrowsError(try repository.open())
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.manifestURL.path))
    }

    func testInvalidNamesAndUnsafeManifestAreRejected() throws {
        for name in ["", "..", ".hidden", "a/b", "a:b", "a\nb", " leading"] {
            XCTAssertThrowsError(try repository.createProject(name: name, color: 0), name)
        }
        var library = BoardLibrary(); var p = BoardProject(name: "测试"); p.directory = "../../outside"; library.projects = [p]
        XCTAssertThrowsError(try repository.save(library))
        library = BoardLibrary(); library.version = 99
        XCTAssertThrowsError(try repository.save(library))
    }

    func testRealRenameMoveAndFileExport() throws {
        let p = try project(); let original = try source()
        _ = try repository.importFiles([original], into: "", project: p)
        let renamed = try repository.renameProject(p, to: "新项目名")
        XCTAssertFalse(FileManager.default.fileExists(atPath: try repository.projectURL(p).path))
        let file = try XCTUnwrap(repository.snapshot(renamed).files.first)
        try repository.rename(file.url, to: "更名.png", project: renamed)
        try repository.createFolder("图片", in: renamed)
        let renamedFile = try XCTUnwrap(repository.snapshot(renamed).files.first)
        try repository.move([renamedFile.url], into: "图片", project: renamed)
        let moved = try XCTUnwrap(repository.snapshot(renamed).files.first)
        XCTAssertEqual(moved.relativePath, "图片/更名.png")
        XCTAssertEqual(try repository.exportFiles([moved.url], to: fixture, project: renamed).imported, 1)
        XCTAssertEqual(try Data(contentsOf: fixture.appendingPathComponent("更名.png")), try Data(contentsOf: original))
    }

    func testPartialImportReportsFailureAndKeepsSuccessfulOriginal() throws {
        let p = try project(); let original = try source()
        let result = try repository.importFiles([original, fixture.appendingPathComponent("不存在.jpg")], into: "", project: p)
        XCTAssertEqual(result.imported, 1); XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(try repository.snapshot(p).files.count, 1)
    }

    func testRestoreFailureRollsBackCopiedProjectsAndManifest() throws {
        var library = BoardLibrary(); library.projects = [try project("保留")]; try repository.save(library)
        let backup = try repository.backup(to: fixture)
        let source = LibraryRepository(root: backup)
        var incoming = try source.open(); incoming.projects.append(BoardProject(name: "缺少目录")); try source.save(incoming)
        let beforeDirectories = try FileManager.default.contentsOfDirectory(atPath: repository.projectsURL.path)
        XCTAssertThrowsError(try repository.restore(from: backup, into: library))
        XCTAssertEqual(try repository.open(), library)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: repository.projectsURL.path), beforeDirectories)
    }

}

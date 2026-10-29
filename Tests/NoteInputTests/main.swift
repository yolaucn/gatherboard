import SwiftUI
import AppKit
import BoardCore

extension Notification.Name { static let newBoardProject = Notification.Name("newBoardProject") }

@MainActor func runChecks() throws {
    _ = NSApplication.shared
    let store = BoardStore()
    store.createProject("输入检查")
    var first = BoardNote(); first.title = "第一条"
    var second = BoardNote(); second.title = "第二条"
    store.updateProject { $0.notes = [first, second] }
    store.selectedNote = first.id; store.tab = .notes
    let host = NSHostingView(rootView: ContentView().environmentObject(store))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 780),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.contentView = host
    func check(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
        guard try condition() else { fatalError(message) }; print("PASS \(message)")
    }
    func spin(_ seconds: TimeInterval = 0.1) {
        let until = Date(timeIntervalSinceNow: seconds)
        repeat {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: min(until, Date(timeIntervalSinceNow: 0.01)))
        } while Date() < until
    }
    func allViews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(allViews) }
    func editor() -> NoteEditorView { allViews(host).compactMap { $0 as? NoteEditorView }.first! }
    func disk() throws -> BoardLibrary { try JSONDecoder().decode(BoardLibrary.self, from: Data(contentsOf: store.repository.manifestURL)) }
    // A window must be ordered to receive native events. Keep it outside the desktop.
    window.setFrameOrigin(NSPoint(x: -20000, y: -20000)); window.orderFront(nil)
    spin()
    func click(_ point: NSPoint) {
        let location = host.convert(point, to: nil)
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0,
                                     windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [], timestamp: 0.01,
                                   windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
        NSApp.postEvent(up, atStart: true)
        window.sendEvent(down)
        while NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) != nil { }
    }
    let titleView = allViews(host).compactMap { $0 as? NoteTitleView }.first!
    let titleRect = titleView.convert(titleView.bounds, to: host)
    let bodyRect = editor().convert(editor().bounds, to: host)
    for offset in [CGFloat(3), titleRect.height / 2, titleRect.height - 3] {
        click(NSPoint(x: titleRect.midX, y: titleRect.minY + offset))
        check(titleView.field.currentEditor() != nil && window.firstResponder === titleView.field.currentEditor(),
              "one click focuses the title, including its padding")
        click(NSPoint(x: bodyRect.midX, y: bodyRect.minY + 3))
        check(window.firstResponder === editor().textView, "one click focuses the body's blank top margin")
    }
    let before = try Data(contentsOf: store.repository.manifestURL)
    let start = Date()
    for i in 0..<100 { store.updateNote(first.id) { $0.title = "快速输入 \(i)" } }
    let inputDuration = Date().timeIntervalSince(start)
    check(store.project?.notes.first?.title == "快速输入 99", "typing updates memory immediately")
    try check(try Data(contentsOf: store.repository.manifestURL) == before, "typing does not synchronously rewrite the index")
    check(store.hasUnsavedNotes, "pending input is marked unsaved")
    spin(0.8)
    try check(try disk().projects[0].notes[0].title == "快速输入 99", "a pause saves the latest title")
    check(!store.hasUnsavedNotes, "save completion clears pending status")
    print("100 title updates: \(Int(inputDuration * 1000)) ms")

    // Real native rich-text input, then exit/backup flushing before the debounce fires.
    let text = editor().textView
    text.insertText("马上退出也要保存", replacementRange: NSRange(location: 0, length: 0))
    check(store.project?.notes[0].text == "马上退出也要保存", "body input updates the list immediately")
    check(store.flushPendingNotes(), "exit flush succeeds before the debounce")
    let savedNote = try disk().projects[0].notes[0]
    check(savedNote.text == text.string, "exit flush saves the latest plain text")
    let rich = savedNote.richText.flatMap { NSAttributedString(rtfd: $0, documentAttributes: nil) }
    check(rich?.string == text.string, "exit flush saves the latest rich text")

    // A real note switch must flush the outgoing editor into its original note.
    text.insertText("，切换前的内容", replacementRange: NSRange(location: text.string.utf16.count, length: 0))
    store.selectedNote = second.id
    spin(0.15)
    check(editor().textView.string.isEmpty, "switching notes loads the target body")
    check(store.flushPendingNotes(), "switch flush succeeds")
    let switched = try disk().projects[0].notes
    check(switched[0].text.contains("切换前的内容") && switched[1].text.isEmpty,
          "a note switch preserves the outgoing input without writing into the next note")

    // Queue a background save, then immediately make a newer edit and flush it.
    store.updateNote(second.id) { $0.title = "较旧版本" }
    spin(0.36)
    store.updateNote(second.id) { $0.title = "最终版本" }
    check(store.flushPendingNotes(), "flush waits for earlier queued saves")
    spin(0.5)
    try check(try disk().projects[0].notes[1].title == "最终版本", "older saves never overwrite the final version")

    // A disk failure must keep the edit in memory and allow a later retry.
    let manifest = store.repository.manifestURL
    let savedIndex = try Data(contentsOf: manifest)
    try FileManager.default.removeItem(at: manifest)
    try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false)
    store.updateNote(second.id) { $0.title = "失败后仍保留" }
    check(!store.flushPendingNotes() && store.hasUnsavedNotes, "save failure keeps pending edits")
    check(store.project?.notes[1].title == "失败后仍保留", "save failure preserves typed content")
    try FileManager.default.removeItem(at: manifest)
    try savedIndex.write(to: manifest)
    store.errorMessage = nil
    check(store.flushPendingNotes(), "pending edits can be retried after a disk failure")
    try check(try disk().projects[0].notes[1].title == "失败后仍保留", "retry persists the retained content")
    let focusHost = NSHostingView(rootView: NoteTitleEditor(title: .constant("新建备忘"), requestFocus: true))
    let focusWindow = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 500, height: 44),
                               styleMask: [.borderless], backing: .buffered, defer: false)
    focusWindow.contentView = focusHost; focusHost.layoutSubtreeIfNeeded(); spin()
    let newTitle = allViews(focusHost).compactMap { $0 as? NoteTitleView }.first!
    check(newTitle.field.currentEditor() != nil && focusWindow.firstResponder === newTitle.field.currentEditor(),
          "a new note's title receives focus without a click")
    window.orderOut(nil)
    check(!window.isVisible, "input checks use an off-screen window and an isolated library")
    print("All note input checks passed")
}

try MainActor.assumeIsolated { try runChecks() }

import SwiftUI
import AppKit
import BoardCore

extension Notification.Name { static let newBoardProject = Notification.Name("newBoardProject") }

private struct SwitchHarness: View {
    @EnvironmentObject var store: BoardStore
    var body: some View { NotesPanel(project: store.project!) }
}

@MainActor func runChecks() throws {
    _ = NSApplication.shared
    let store = BoardStore(); store.createProject("切换检查")
    let link = URL(string: "https://example.com/story?id=123")!
    let linkedText = NSAttributedString(string: link.absoluteString, attributes: [.link: link, .font: NSFont.systemFont(ofSize: 14)])
    var notes = (0..<6).map { index -> BoardNote in
        var note = BoardNote(); note.title = "备忘 \(index)"; note.text = "摘要"
        note.updated = Date(timeIntervalSince1970: Double(1000 - index))
        return note
    }
    notes[2].title = "故事"; notes[2].text = linkedText.string
    notes[2].richText = linkedText.rtfd(from: NSRange(location: 0, length: linkedText.length), documentAttributes: [:])
    store.updateProject { $0.notes = notes }; store.selectedNote = notes[3].id
    let host = NSHostingView(rootView: SwitchHarness().environmentObject(store))
    let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 800, height: 600),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host; window.orderFront(nil)
    func check(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
        guard try condition() else { fatalError(message) }; print("PASS \(message)")
    }
    func settle() {
        for _ in 0..<5 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005)) }
    }
    func allViews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(allViews) }
    func editor() -> NoteEditorView { allViews(host).compactMap { $0 as? NoteEditorView }.first! }
    func select(_ id: UUID) { store.selectedNote = id; settle() }
    func click(_ x: CGFloat, _ y: CGFloat) {
        let location = host.convert(NSPoint(x: x, y: y), to: nil)
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0,
                                     windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [], timestamp: 0.01,
                                   windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
        NSApp.postEvent(up, atStart: true); window.sendEvent(down)
        if let event = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) { window.sendEvent(event) }
        settle()
    }
    settle()
    let indexBeforeSwitching = try Data(contentsOf: store.repository.manifestURL)
    // Third row, at positions outside the short title and summary text.
    for x in [CGFloat(206), 100, 5] {
        select(notes[3].id); click(x, 185)
        check(store.selectedNote == notes[2].id, "one click on a row's empty space selects the linked story")
    }
    let storyEditor = editor()
    check(storyEditor.textView.textStorage?.attribute(.link, at: 0, effectiveRange: nil) as? URL == link,
          "loading a note preserves its clickable hyperlink")
    check(!storyEditor.textView.isAutomaticLinkDetectionEnabled, "loading saved content does not restart automatic link detection")
    let start = Date()
    for _ in 0..<8 {
        select(notes[3].id); select(notes[2].id)
        check(editor() === storyEditor, "returning to the story reuses its existing native editor")
    }
    print("16 cached note switches: \(Int(Date().timeIntervalSince(start) * 1000)) ms (including run-loop settling)")
    try check(try Data(contentsOf: store.repository.manifestURL) == indexBeforeSwitching,
          "switching clean notes does not rewrite the library")
    storyEditor.textView.insertText("\n新增内容", replacementRange: NSRange(location: linkedText.length, length: 0))
    check(storyEditor.textView.isAutomaticLinkDetectionEnabled, "editing enables automatic detection for newly typed links")
    select(notes[3].id); select(notes[2].id)
    check(editor() === storyEditor && editor().textView.string.hasSuffix("新增内容"),
          "switching immediately after typing preserves the cached editor and latest input")
    check(store.flushPendingNotes(), "pending edits can be flushed with inactive cached editors")
    let saved = try JSONDecoder().decode(BoardLibrary.self, from: Data(contentsOf: store.repository.manifestURL))
    let savedStory = saved.projects[0].notes.first { $0.id == notes[2].id }!
    let reopened = NSAttributedString(rtfd: savedStory.richText!, documentAttributes: nil)!
    check(reopened.string.hasSuffix("新增内容") && reopened.attribute(.link, at: 0, effectiveRange: nil) as? URL == link,
          "switching and saving preserve both new text and the original hyperlink")
    select(notes[3].id)
    let newLink = URL(string: "https://example.com/updated-story")!
    let revised = NSMutableAttributedString(attributedString: reopened)
    revised.addAttribute(.link, value: newLink, range: NSRange(location: 0, length: linkedText.length))
    store.updateNote(notes[2].id) {
        $0.richText = revised.rtfd(from: NSRange(location: 0, length: revised.length), documentAttributes: [:])
    }
    select(notes[2].id)
    let revisedEditor = editor()
    check(revisedEditor !== storyEditor
          && revisedEditor.textView.textStorage?.attribute(.link, at: 0, effectiveRange: nil) as? URL == newLink,
          "changed rich text invalidates a cached session even when its plain text is unchanged")
    // Visiting more than four notes evicts old sessions; returning must restore from the model.
    for index in [0, 1, 3, 4, 5] { select(notes[index].id) }
    select(notes[2].id)
    check(editor() !== revisedEditor && editor().textView.string.hasSuffix("新增内容"),
          "the bounded cache reloads evicted notes without losing edits")
    check(store.flushPendingNotes(), "all edited fixtures are saved before the test exits")
    window.orderOut(nil)
    print("All note switching checks passed")
}

try MainActor.assumeIsolated { try runChecks() }

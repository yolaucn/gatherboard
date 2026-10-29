import SwiftUI
import AppKit
import BoardCore

extension Notification.Name { static let newBoardProject = Notification.Name("newBoardProject") }

// Render the real SwiftUI page, including its native editor. Editor-only checks cannot
// catch drawing that escapes into the adjacent list and title owned by SwiftUI.
@MainActor func runChecks() throws {
    _ = NSApplication.shared
    let store = BoardStore()
    store.createProject("备忘布局检查")
    store.tab = .notes
    let host = NSHostingView(rootView: ContentView().environmentObject(store).preferredColorScheme(.light))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 780),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.contentView = host
    window.setContentSize(NSSize(width: 1080, height: 780))
    func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        print("PASS \(message)")
    }
    func allViews(_ parent: NSView) -> [NSView] { [parent] + parent.subviews.flatMap(allViews) }
    func settle() {
        for _ in 0..<8 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        }
    }
    func verifyPage(_ name: String) throws {
        settle()
        let editors = allViews(host).compactMap { $0 as? NoteEditorView }
        check(editors.count == 1, "\(name): one editor is mounted")
        let editor = editors[0]
        let rect = editor.convert(editor.bounds, to: host)
        let title = allViews(host).compactMap { $0 as? NoteTitleView }.first!
        let titleRect = title.convert(title.bounds, to: host)
        func hit(_ point: NSPoint) -> NSView? { host.hitTest(host.convert(point, to: host.superview)) }
        for x in [titleRect.minX + 3, titleRect.midX, titleRect.maxX - 3] {
            for y in [titleRect.minY + 3, titleRect.midY, titleRect.maxY - 3] {
                let target = hit(NSPoint(x: x, y: y))
                check(target === title || target === title.field,
                      "\(name): title row and padding receive clicks")
            }
        }
        for y in [rect.minY + 3, rect.minY + 40, rect.maxY - 4] {
            check(hit(NSPoint(x: rect.midX, y: y)) === editor.textView,
                  "\(name): body and blank margin receive clicks")
        }
        check(title.acceptsFirstMouse(for: nil) && title.field.acceptsFirstMouse(for: nil)
              && editor.textView.acceptsFirstMouse(for: nil), "\(name): inputs accept the first click")
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        func color(_ x: CGFloat, _ y: CGFloat) -> NSColor {
            bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))!
        }
        // A selected list row is beige. Before the fix, the editor painted this entire column white.
        let listX = rect.minX - 10
        let selectedPixels = stride(from: rect.minY - 36, to: rect.maxY - 10, by: 2).filter { y in
            let pixel = color(listX, y)
            return abs(pixel.redComponent - 243.0 / 255) < 0.02
                && abs(pixel.greenComponent - 233.0 / 255) < 0.02
                && abs(pixel.blueComponent - 217.0 / 255) < 0.02
        }.count
        check(selectedPixels > 15, "\(name): the selected note row remains visible")
        var titlePixels = 0
        for y in stride(from: rect.minY - 34, to: rect.minY - 10, by: 2) {
            for x in stride(from: rect.minX + 16, to: rect.maxX - 16, by: 2) {
                let pixel = color(x, y)
                if max(pixel.redComponent, pixel.greenComponent, pixel.blueComponent) < 0.85 { titlePixels += 1 }
            }
        }
        check(titlePixels > 15, "\(name): the note title remains visible above the editor")
        check(rect.minX >= 463 && rect.maxX <= host.bounds.width, "\(name): the editor stays in its own column")
        try bitmap.representation(using: .png, properties: [:])!.write(
            to: URL(fileURLWithPath: ".build/NoteLayoutChecks/\(name).png"))
    }
    func createNote(_ title: String) -> UUID {
        var note = BoardNote(); note.title = title
        store.updateProject { $0.notes.insert(note, at: 0) }; store.selectedNote = note.id
        return note.id
    }
    settle()
    check(store.project?.notes.isEmpty == true, "fixture starts with no notes")
    let first = createNote("第一条备忘")
    try verifyPage("first-created")
    _ = createNote("第二条备忘")
    try verifyPage("second-created")
    store.selectedNote = first
    try verifyPage("switch-existing")
    for size in [NSSize(width: 880, height: 600), NSSize(width: 1400, height: 900)] {
        window.setContentSize(size)
        try verifyPage("resize-\(Int(size.width))")
    }
    store.tab = .tasks; settle(); store.tab = .notes
    try verifyPage("return-to-notes")
    check(store.project?.notes.count == 2, "all notes survive layout changes and tab switches")
    check(!window.isVisible, "layout checks keep their window off screen")
    print("All note page layout checks passed")
}

try MainActor.assumeIsolated { try runChecks() }

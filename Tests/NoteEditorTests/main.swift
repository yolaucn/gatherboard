import AppKit

// Exercise the production native views with generated fixtures, without opening a user library.

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
    print("PASS \(message)")
}
final class TestTextView: NoteImageTextView {
    let testUndo = UndoManager()
    override var undoManager: UndoManager? { testUndo }
}
final class Delegate: NSObject, NSTextViewDelegate {
    var saves = 0
    func textDidChange(_ notification: Notification) {
        (notification.object as? NoteImageTextView)?.prepareImages()
        saves += 1
    }
}
func image(width: Int, height: Int) -> (NSAttributedString, Data) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.bitmapData?.initialize(repeating: 255, count: rep.bytesPerRow * rep.pixelsHigh)
    let data = rep.representation(using: .png, properties: [:])!
    let wrapper = FileWrapper(regularFileWithContents: data); wrapper.preferredFilename = "original.png"
    return (NSAttributedString(attachment: NSTextAttachment(fileWrapper: wrapper)), data)
}
func configure(_ view: NoteImageTextView, width: CGFloat = 450) {
    view.isRichText = true; view.importsGraphics = true; view.allowsUndo = true
    view.layoutManager!.defaultAttachmentScaling = .scaleProportionallyDown
    view.textContainerInset = NSSize(width: 14, height: 14)
    view.isVerticallyResizable = true; view.isHorizontallyResizable = false
    view.textContainer!.widthTracksTextView = true
    view.textContainer!.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    view.setFrameSize(NSSize(width: width, height: 1500))
}
let delegate = Delegate()
let view = TestTextView()
configure(view)
let source = image(width: 1200, height: 600)
let content = NSMutableAttributedString(string: "Before\n")
let index = content.length
content.append(source.0); content.append(NSAttributedString(string: "\nAfter"))
view.textStorage!.setAttributedString(content)
view.prepareImages(); view.delegate = delegate
view.setSelectedRange(NSRange(location: index, length: 1))
check(abs(view.imageRect(at: index)!.width - 412) < 0.01, "automatic fit uses available body width")
view.testUndo.beginUndoGrouping()
view.resizeSelectedImage(by: 0.5)
view.testUndo.endUndoGrouping()
check(abs(view.imageRect(at: index)!.width - 206) < 0.01, "manual shrink halves image width")
check(abs(view.imageRect(at: index)!.height - 103) < 0.01, "manual resize preserves aspect ratio")
check(delegate.saves > 0, "manual resize triggers native text change for autosave")
check(view.imageWidths[String(index)] == 206, "manual width is included in saved note metadata")
check(view.testUndo.canUndo, "image resizing can be undone")
view.testUndo.undo()
check(abs(view.imageRect(at: index)!.width - 412) < 0.01 && view.imageWidths.isEmpty, "undo restores automatic sizing")
view.testUndo.redo()
check(abs(view.imageRect(at: index)!.width - 206) < 0.01, "redo restores manual sizing")
let saved = view.textStorage!.rtfd(from: NSRange(location: 0, length: view.textStorage!.length), documentAttributes: [:])!
let widths = view.imageWidths
let reopened = NoteImageTextView(); configure(reopened)
reopened.textStorage!.setAttributedString(NSAttributedString(rtfd: saved, documentAttributes: nil)!)
reopened.prepareImages(savedWidths: widths)
check(abs(reopened.imageRect(at: index)!.width - 206) < 0.01, "manual size survives save and reload")
check(reopened.imageAttachment(at: index)!.fileWrapper!.regularFileContents == source.1, "original image bytes are unchanged")
configure(reopened, width: 200)
check(abs(reopened.imageRect(at: index)!.width - 162) < 0.01, "manual size fits a narrower window")
configure(reopened, width: 900)
check(abs(reopened.imageRect(at: index)!.width - 206) < 0.01, "manual size returns when window widens")
reopened.setSelectedRange(NSRange(location: index, length: 1))
reopened.resizeSelectedImage(by: 1.25)
check(abs(reopened.imageRect(at: index)!.width - 257.5) < 0.01, "manual enlarge increases width")
reopened.resetSelectedImageSize()
check(reopened.imageWidths.isEmpty && abs(reopened.imageRect(at: index)!.width - 862) < 0.01, "reset restores automatic fit")
var previewCount = 0
reopened.previewRequested = { original, name in
    check(original.size == NSSize(width: 1200, height: 600), "preview receives full original size")
    previewCount += 1
}
reopened.previewSelectedImage()
check(previewCount == 1, "preview button requests original image")
let rect = reopened.imageRect(at: index)!
let event = NSEvent.mouseEvent(with: .leftMouseDown, location: reopened.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 2, pressure: 1)!
reopened.mouseDown(with: event)
check(previewCount == 2, "double-click requests full image preview")
// Drag the lower-right handle left, then release to commit one undoable resize.
let handle = reopened.imageRect(at: index)!
func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: reopened.convert(NSPoint(x: x, y: y), to: nil), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
}
reopened.mouseDown(with: mouse(.leftMouseDown, handle.maxX, handle.maxY))
reopened.mouseDragged(with: mouse(.leftMouseDragged, handle.maxX - 100, handle.maxY))
reopened.mouseUp(with: mouse(.leftMouseUp, handle.maxX - 100, handle.maxY))
check(abs(reopened.imageRect(at: index)!.width - 762) < 0.01, "dragging resize handle changes and commits width")
let previousWidth = reopened.imageWidths[String(index)]!
reopened.insertText("Prefix", replacementRange: NSRange(location: 0, length: 0))
check(reopened.imageWidths[String(index + 6)] == previousWidth, "typing before image preserves its manual size at the new position")
check(reopened.string.hasPrefix("PrefixBefore\n") && reopened.string.hasSuffix("\nAfter"), "image controls preserve surrounding note text")
let small = NoteImageTextView(); configure(small)
small.textStorage!.setAttributedString(image(width: 120, height: 80).0); small.prepareImages()
small.setSelectedRange(NSRange(location: 0, length: 1))
check(abs(small.imageRect(at: 0)!.width - 120) < 0.01, "small images keep natural size by default")
small.resizeSelectedImage(by: 1.25)
check(abs(small.imageRect(at: 0)!.width - 150) < 0.01, "small images can be manually enlarged")

_ = NSApplication.shared
let editor = NoteEditorView(frame: NSRect(x: 0, y: 0, width: 650, height: 500))
let toolbar = editor.subviews.compactMap { $0 as? NSStackView }.first!
editor.layoutSubtreeIfNeeded()
check(toolbar.isHidden && editor.scrollView.frame.maxY == editor.bounds.maxY, "empty notes hide image tools and leave no toolbar gap")
configure(editor.textView)
editor.textView.textStorage!.setAttributedString(content)
editor.textView.prepareImages()
editor.layoutSubtreeIfNeeded()
editor.textView.setSelectedRange(NSRange(location: index, length: 1))
editor.textView.refreshImageSelection()
let buttons = toolbar.arrangedSubviews.compactMap { $0 as? NSButton }
check(!toolbar.isHidden && buttons.count == 4 && buttons.allSatisfy(\.isEnabled), "selecting an image shows and enables its toolbar")
let toolbarWidth = editor.textView.imageRect(at: index)!.width
buttons[0].performClick(nil)
check(abs(editor.textView.imageRect(at: index)!.width - toolbarWidth * 0.8) < 0.01, "toolbar shrink button resizes the selected image")
buttons[1].performClick(nil)
check(abs(editor.textView.imageRect(at: index)!.width - toolbarWidth) < 0.01, "toolbar enlarge button resizes the selected image")
buttons[2].performClick(nil)
check(editor.textView.imageWidths.isEmpty, "toolbar reset button restores automatic fit")
editor.textView.previewRequested = { _, _ in previewCount += 1 }
buttons[3].performClick(nil)
check(previewCount == 3, "toolbar preview button opens the selected original")
editor.textView.setSelectedRange(NSRange(location: 0, length: 0)); editor.textView.refreshImageSelection()
editor.layoutSubtreeIfNeeded()
check(toolbar.isHidden && buttons.allSatisfy { !$0.isEnabled }, "image controls hide when editing ordinary text")
check(editor.scrollView.frame.maxY == editor.bounds.maxY, "hiding the toolbar returns its space to the text area")

let preview = NoteImagePreviewController(image: NoteImageTextView.originalImage(view.imageAttachment(at: index)!)!, title: "Test original")
let root = preview.window!.contentView!
root.layoutSubtreeIfNeeded()
let previewScroll = root.subviews.compactMap { $0 as? NSScrollView }.first!
let previewToolbar = root.subviews.compactMap { $0 as? NSStackView }.first!
let previewButtons = previewToolbar.arrangedSubviews.compactMap { $0 as? NSButton }
func click(_ title: String) { previewButtons.first { $0.title == title }!.performClick(nil) }
check(!preview.window!.isVisible, "preview test keeps its window off screen")
click("适应窗口")
check(previewScroll.magnification < 1 && previewScroll.magnification > 0, "preview fits the original into its viewport")
let fittedZoom = previewScroll.magnification
click("＋")
check(abs(previewScroll.magnification - fittedZoom * 1.25) < 0.001, "preview can zoom in")
click("－")
check(abs(previewScroll.magnification - fittedZoom) < 0.001, "preview can zoom out")
click("100%")
check(previewScroll.magnification == 1, "preview supports original 100 percent size")
check(previewScroll.allowsMagnification && previewScroll.hasHorizontalScroller && previewScroll.hasVerticalScroller, "preview supports pinch zoom and scrolling")
check(previewButtons.first { $0.title == "关闭" }!.keyEquivalent == "\u{1b}", "Escape closes the preview")
preview.close()
print("All image editor checks passed")

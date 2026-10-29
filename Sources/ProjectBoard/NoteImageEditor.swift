import AppKit

/// Display-only sizing: the attachment's file wrapper always retains the original bytes.
final class NoteImageCell: NSTextAttachmentCell {
    var preferredWidth: CGFloat?
    init(image: NSImage, preferredWidth: CGFloat? = nil) {
        self.preferredWidth = preferredWidth
        super.init(imageCell: image)
    }
    required init(coder: NSCoder) { super.init(coder: coder) }
    override var cellSize: NSSize {
        guard let image, image.size.width > 0, image.size.height > 0 else { return super.cellSize }
        let width = preferredWidth ?? image.size.width
        return NSSize(width: width, height: width * image.size.height / image.size.width)
    }
    override func cellFrame(for textContainer: NSTextContainer, proposedLineFragment lineFrag: NSRect,
                            glyphPosition position: NSPoint, characterIndex charIndex: Int) -> NSRect {
        let natural = cellSize
        let available = max(1, min(textContainer.containerSize.width, lineFrag.width) - textContainer.lineFragmentPadding * 2)
        let width = min(natural.width, available)
        return NSRect(x: 0, y: 0, width: width, height: natural.height * width / max(1, natural.width))
    }
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        image?.draw(in: cellFrame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

class NoteImageTextView: NSTextView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var imageSelectionChanged: (() -> Void)?
    var previewRequested: ((NSImage, String) -> Void)?
    private var resizing: (index: Int, start: NSPoint, width: CGFloat, previous: CGFloat?)?

    func prepareImages(savedWidths: [String: Double]? = nil) {
        guard let storage = textStorage else { return }
        var changed = false
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment, !(attachment.attachmentCell is NoteImageCell),
                  let image = Self.originalImage(attachment), image.size.width > 0, image.size.height > 0 else { return }
            let width = savedWidths?[String(range.location)].flatMap { $0.isFinite && $0 > 0 ? CGFloat($0) : nil }
            attachment.attachmentCell = NoteImageCell(image: image, preferredWidth: width)
            changed = true
        }
        if changed { invalidateImages() }
    }
    static func originalImage(_ attachment: NSTextAttachment) -> NSImage? {
        if let data = attachment.fileWrapper?.regularFileContents, let image = NSImage(data: data) { return image }
        return (attachment.attachmentCell as? NSCell)?.image
    }
    var imageWidths: [String: Double] {
        guard let storage = textStorage else { return [:] }
        var result: [String: Double] = [:]
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let cell = (value as? NSTextAttachment)?.attachmentCell as? NoteImageCell, let width = cell.preferredWidth {
                result[String(range.location)] = Double(width)
            }
        }
        return result
    }
    var selectedImageIndex: Int? {
        let range = selectedRange()
        guard range.length == 1, imageAttachment(at: range.location) != nil else { return nil }
        return range.location
    }
    func imageAttachment(at index: Int) -> NSTextAttachment? {
        guard let storage = textStorage, index >= 0, index < storage.length,
              let attachment = storage.attribute(.attachment, at: index, effectiveRange: nil) as? NSTextAttachment,
              attachment.attachmentCell is NoteImageCell else { return nil }
        return attachment
    }
    func imageRect(at index: Int) -> NSRect? {
        guard imageAttachment(at: index) != nil, let manager = layoutManager, let container = textContainer else { return nil }
        manager.ensureLayout(for: container)
        let range = manager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        return manager.boundingRect(forGlyphRange: range, in: container).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }
    private var handleRect: NSRect? {
        guard let index = selectedImageIndex, let rect = imageRect(at: index) else { return nil }
        return NSRect(x: rect.maxX - 5, y: rect.maxY - 5, width: 10, height: 10)
    }
    private func imageIndex(at point: NSPoint) -> Int? {
        guard let manager = layoutManager, let container = textContainer, manager.numberOfGlyphs > 0 else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = manager.glyphIndex(for: local, in: container)
        guard glyph < manager.numberOfGlyphs else { return nil }
        let index = manager.characterIndexForGlyph(at: glyph)
        guard let rect = imageRect(at: index), rect.contains(point) else { return nil }
        return index
    }
    func refreshImageSelection() {
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        imageSelectionChanged?()
    }
    private func invalidateImages() {
        if let storage = textStorage {
            layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: storage.length), actualCharacterRange: nil)
        }
        needsDisplay = true
        refreshImageSelection()
    }
    func resizeSelectedImage(by factor: CGFloat) {
        guard let index = selectedImageIndex, let rect = imageRect(at: index) else { return }
        setImageWidth(rect.width * factor, at: index)
    }
    func resetSelectedImageSize() {
        guard let index = selectedImageIndex else { return }
        setImageWidth(nil, at: index)
    }
    /// Replacing the attachment gives native text undo its own old/new objects.
    func setImageWidth(_ width: CGFloat?, at index: Int) {
        guard let attachment = imageAttachment(at: index), let image = Self.originalImage(attachment),
              let storage = textStorage else { return }
        let available = max(1, (textContainer?.containerSize.width ?? bounds.width) - (textContainer?.lineFragmentPadding ?? 5) * 2)
        let preferred = width.map { min(available, max(min(24, available), $0)) }
        let replacement = NSTextAttachment(fileWrapper: attachment.fileWrapper)
        replacement.attachmentCell = NoteImageCell(image: image, preferredWidth: preferred)
        let content = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: NSRange(location: index, length: 1)))
        content.addAttribute(.attachment, value: replacement, range: NSRange(location: 0, length: 1))
        breakUndoCoalescing()
        insertText(content, replacementRange: NSRange(location: index, length: 1))
        breakUndoCoalescing()
        undoManager?.setActionName("调整图片大小")
        setSelectedRange(NSRange(location: index, length: 1))
        invalidateImages()
    }
    func previewSelectedImage() {
        guard let index = selectedImageIndex, let attachment = imageAttachment(at: index),
              let image = Self.originalImage(attachment) else { return }
        previewRequested?(image, attachment.fileWrapper?.preferredFilename ?? "备忘图片")
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 1, let handle = handleRect, handle.insetBy(dx: -4, dy: -4).contains(point),
           let index = selectedImageIndex, let rect = imageRect(at: index),
           let cell = imageAttachment(at: index)?.attachmentCell as? NoteImageCell {
            resizing = (index, point, rect.width, cell.preferredWidth)
            return
        }
        if let index = imageIndex(at: point) {
            window?.makeFirstResponder(self)
            setSelectedRange(NSRange(location: index, length: 1))
            refreshImageSelection()
            if event.clickCount == 2 { previewSelectedImage() }
            return
        }
        super.mouseDown(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let state = resizing, let cell = imageAttachment(at: state.index)?.attachmentCell as? NoteImageCell else {
            super.mouseDragged(with: event); return
        }
        let point = convert(event.locationInWindow, from: nil)
        let available = max(1, (textContainer?.containerSize.width ?? bounds.width) - (textContainer?.lineFragmentPadding ?? 5) * 2)
        cell.preferredWidth = min(available, max(min(24, available), state.width + point.x - state.start.x))
        invalidateImages()
    }
    override func mouseUp(with event: NSEvent) {
        guard let state = resizing, let cell = imageAttachment(at: state.index)?.attachmentCell as? NoteImageCell else {
            super.mouseUp(with: event); return
        }
        let width = cell.preferredWidth
        cell.preferredWidth = state.previous
        resizing = nil
        setImageWidth(width, at: state.index)
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let index = selectedImageIndex, let rect = imageRect(at: index), let handle = handleRect else { return }
        NSColor.controlAccentColor.setStroke()
        NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5)).stroke()
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: handle, xRadius: 2, yRadius: 2).fill()
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        if let handle = handleRect { addCursorRect(handle.insetBy(dx: -4, dy: -4), cursor: .crosshair) }
    }
    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged { DispatchQueue.main.async { [weak self] in self?.refreshImageSelection() } }
    }
}

final class NoteEditorView: NSView {
    let textView = NoteImageTextView()
    let scrollView = NSScrollView()
    private let hint = NSTextField(labelWithString: "")
    private let imageToolbar = NSStackView()
    private var scrollTopWithToolbar: NSLayoutConstraint?
    private var scrollTopWithoutToolbar: NSLayoutConstraint?
    private var imageButtons: [NSButton] = []
    private var previewController: NoteImagePreviewController?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // SwiftUI may request drawing beyond this view's bounds; keep the editor inside its column.
        clipsToBounds = true
        let smaller = NSButton(image: NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: "缩小图片")!, target: self, action: #selector(shrinkImage))
        let larger = NSButton(image: NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "放大图片")!, target: self, action: #selector(enlargeImage))
        let reset = NSButton(title: "自动适应", target: self, action: #selector(resetImage))
        let preview = NSButton(title: "查看大图", target: self, action: #selector(previewImage))
        imageButtons = [smaller, larger, reset, preview]
        for button in imageButtons { button.bezelStyle = .rounded; button.controlSize = .small; button.font = .systemFont(ofSize: 11) }
        smaller.toolTip = "缩小选中的图片，也可拖动图片右下角"
        larger.toolTip = "放大选中的图片，最大适应正文宽度"
        reset.toolTip = "恢复自动适应正文宽度"
        preview.toolTip = "查看原图，可继续放大、缩小"
        hint.font = .systemFont(ofSize: 10); hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let toolbar = imageToolbar
        toolbar.addArrangedSubview(hint)
        for button in imageButtons { toolbar.addArrangedSubview(button) }
        toolbar.spacing = 6; toolbar.alignment = .centerY
        scrollView.hasVerticalScroller = true; scrollView.autohidesScrollers = true; scrollView.drawsBackground = false
        scrollView.documentView = textView
        addSubview(toolbar); addSubview(scrollView)
        toolbar.translatesAutoresizingMaskIntoConstraints = false; scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollTopWithToolbar = scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor)
        scrollTopWithoutToolbar = scrollView.topAnchor.constraint(equalTo: topAnchor)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            toolbar.topAnchor.constraint(equalTo: topAnchor), toolbar.heightAnchor.constraint(equalToConstant: 36),
            scrollTopWithoutToolbar!, scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor), scrollView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        textView.imageSelectionChanged = { [weak self] in self?.updateToolbar() }
        textView.previewRequested = { [weak self] image, title in
            self?.previewController?.close()
            self?.previewController = NoteImagePreviewController(image: image, title: title)
            self?.previewController?.showPreview()
        }
        updateToolbar()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        // The clip view owns the blank margin above the text; forward it to the editor.
        if hit === scrollView.contentView || hit === scrollView { return textView }
        return hit
    }
    deinit { previewController?.close() }
    func closePreview() { previewController?.close(); previewController = nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.intersection(bounds).fill()
    }
    private func updateToolbar() {
        let index = textView.selectedImageIndex
        let showToolbar = index != nil
        imageToolbar.isHidden = !showToolbar
        if showToolbar {
            scrollTopWithoutToolbar?.isActive = false
            scrollTopWithToolbar?.isActive = true
        } else {
            scrollTopWithToolbar?.isActive = false
            scrollTopWithoutToolbar?.isActive = true
        }
        for button in imageButtons { button.isEnabled = index != nil }
        if let index, let rect = textView.imageRect(at: index) { hint.stringValue = "\(Int(rect.width)) × \(Int(rect.height)) · 拖右下角调大小" }
        else { hint.stringValue = "" }
    }
    @objc private func shrinkImage() { textView.resizeSelectedImage(by: 0.8) }
    @objc private func enlargeImage() { textView.resizeSelectedImage(by: 1.25) }
    @objc private func resetImage() { textView.resetSelectedImageSize() }
    @objc private func previewImage() { textView.previewSelectedImage() }
}

final class NoteImagePreviewController: NSWindowController {
    private let scrollView = NSScrollView()
    private let image: NSImage
    private let zoomLabel = NSTextField(labelWithString: "100%")
    init(image: NSImage, title: String) {
        self.image = image
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = title; panel.isReleasedWhenClosed = false; panel.minSize = NSSize(width: 400, height: 300)
        super.init(window: panel)
        let smaller = NSButton(title: "－", target: self, action: #selector(zoomOut))
        let larger = NSButton(title: "＋", target: self, action: #selector(zoomIn))
        let actual = NSButton(title: "100%", target: self, action: #selector(actualSize))
        let fit = NSButton(title: "适应窗口", target: self, action: #selector(fitImage))
        let close = NSButton(title: "关闭", target: self, action: #selector(closePreview)); close.keyEquivalent = "\u{1b}"
        let toolbar = NSStackView(views: [smaller, zoomLabel, larger, actual, fit, close])
        toolbar.spacing = 10
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        imageView.image = image; imageView.imageScaling = .scaleAxesIndependently
        scrollView.documentView = imageView
        scrollView.hasVerticalScroller = true; scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true; scrollView.minMagnification = 0.05; scrollView.maxMagnification = 8
        guard let content = panel.contentView else { return }
        content.addSubview(toolbar); content.addSubview(scrollView)
        toolbar.translatesAutoresizingMaskIntoConstraints = false; scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            toolbar.centerXAnchor.constraint(equalTo: content.centerXAnchor), toolbar.heightAnchor.constraint(equalToConstant: 30),
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8), scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor), scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(updateZoomLabel), name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func showPreview() {
        window?.center(); showWindow(nil)
        window?.contentView?.layoutSubtreeIfNeeded()
        fitImage()
    }
    private func setZoom(_ value: CGFloat) {
        scrollView.magnification = min(scrollView.maxMagnification, max(scrollView.minMagnification, value))
        updateZoomLabel()
    }
    @objc private func updateZoomLabel() { zoomLabel.stringValue = "\(Int((scrollView.magnification * 100).rounded()))%" }
    @objc private func zoomIn() { setZoom(scrollView.magnification * 1.25) }
    @objc private func zoomOut() { setZoom(scrollView.magnification / 1.25) }
    @objc private func actualSize() { setZoom(1) }
    @objc private func fitImage() {
        let size = scrollView.contentSize
        setZoom(min(1, min(size.width / max(1, image.size.width), size.height / max(1, image.size.height))))
    }
    @objc private func closePreview() { close() }
}

import SwiftUI
import AppKit
import BoardCore

extension Notification.Name { static let flushNoteEditors = Notification.Name("flushNoteEditors") }

struct NotesPanel: View {
    @EnvironmentObject private var store: BoardStore
    @State private var titleFocusRequest: UUID?
    @StateObject private var editorCache = NoteEditorCache()
    let project: BoardProject
    private var selected: BoardNote? { project.notes.first { $0.id == store.selectedNote } ?? project.notes.sorted { $0.updated > $1.updated }.first }
    var body: some View {
        let boardStore = store
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Button {
                    let note = BoardNote(); store.updateProject { $0.notes.insert(note, at: 0) }; store.selectedNote = note.id
                    titleFocusRequest = note.id
                } label: { Text("＋ 新建备忘").foregroundColor(Theme.accent).frame(maxWidth: .infinity, alignment: .leading).padding(12).contentShape(Rectangle()) }.buttonStyle(.plain)
                Divider().overlay(Theme.border)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(project.notes.sorted { $0.updated > $1.updated }) { note in
                            Button { store.selectedNote = note.id } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(note.displayTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    HStack(spacing: 4) { Text(note.updated, format: .dateTime.year().month().day()); Text("· " + (note.text.isEmpty ? "没有更多文字" : String(note.text.prefix(160)).replacingOccurrences(of: "\n", with: " "))) }.font(.system(size: 11)).foregroundColor(Theme.muted).lineLimit(1)
                                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(selected?.id == note.id ? Color(hex: 0xF3E9D9) : .clear).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider().overlay(Theme.border.opacity(0.6))
                        }
                    }
                }
            }.frame(width: 214).background(Color(hex: 0xFAF9F6))
            Rectangle().fill(Theme.border).frame(width: 1)
            if let note = selected {
                VStack(spacing: 0) {
                    HStack {
                        Text(note.updated, format: .dateTime.year().month().day().hour().minute()).font(.system(size: 11)).foregroundColor(Theme.muted)
                        Spacer()
                        Text(store.hasUnsavedNotes ? "正在保存…" : "自动保存").font(.system(size: 10)).foregroundColor(Theme.muted)
                        Button("删除") { deleteNote(note) }.buttonStyle(.plain).font(.system(size: 11)).foregroundColor(Theme.muted)
                    }.padding(.horizontal, 14).frame(height: 34)
                    Divider().overlay(Theme.border)
                    NoteTitleEditor(title: Binding(get: { note.title }, set: { value in store.updateNote(note.id) { $0.title = value } }),
                                    requestFocus: titleFocusRequest == note.id).id(note.id).frame(height: 44)
                    Divider().overlay(Theme.border)
                    RichNoteEditor(note: note, cache: editorCache, typing: { text in boardStore.updateNote(note.id) { $0.text = text } }) { text, data, widths in
                        boardStore.updateNote(note.id) { $0.text = text; $0.richText = data; $0.imageWidths = widths.isEmpty ? nil : widths }
                    }.id(note.id)
                }.background(.white)
            } else { Text("还没有备忘，点左上角新建").foregroundColor(Theme.muted).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white) }
        }.frame(minHeight: 380, maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border).allowsHitTesting(false))
    }
    private func deleteNote(_ note: BoardNote) {
        let alert = NSAlert(); alert.messageText = "删除这条备忘？"; alert.informativeText = note.displayTitle
        alert.addButton(withTitle: "删除"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.updateProject { $0.notes.removeAll { $0.id == note.id } }; store.selectedNote = nil
    }
}

// Keep a small per-project working set. Returning to a note preserves its native
// text layout instead of importing RTFD and setting up link checking on every click.
final class NoteEditorCache: ObservableObject {
    struct Session {
        let editor: NoteEditorView
        let coordinator: RichNoteEditor.Coordinator
    }
    private var sessions: [UUID: Session] = [:]
    private var recent: [UUID] = []

    func session(for note: BoardNote) -> Session? {
        guard let session = sessions[note.id],
              session.coordinator.savedRichText == note.richText,
              session.editor.textView.string == note.text,
              session.editor.textView.imageWidths == (note.imageWidths ?? [:]) else { return nil }
        return session
    }
    func remember(_ session: Session, for id: UUID) {
        sessions[id] = session
        recent.removeAll { $0 == id }; recent.append(id)
        while recent.count > 4 {
            let removed = recent.removeFirst(); sessions.removeValue(forKey: removed)
        }
    }
}

// Give the entire title row a native click target, including its vertical padding.
final class NoteTitleView: NSView {
    final class Field: NSTextField {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
    let field = Field()
    override init(frame: NSRect) {
        super.init(frame: frame)
        field.isBordered = false; field.drawsBackground = false
        field.font = .systemFont(ofSize: 16, weight: .semibold)
        field.textColor = NSColor(Theme.ink)
        field.placeholderString = "标题（留空则取正文第一行）"
        field.usesSingleLineMode = true; field.cell?.isScrollable = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(field); field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            field.centerYAnchor.constraint(equalTo: centerYAnchor), field.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.utf16.count, length: 0)
    }
}

struct NoteTitleEditor: NSViewRepresentable {
    @Binding var title: String
    var requestFocus: Bool
    func makeCoordinator() -> Coordinator { Coordinator(title: $title) }
    func makeNSView(context: Context) -> NoteTitleView {
        let view = NoteTitleView()
        view.field.delegate = context.coordinator
        return view
    }
    func updateNSView(_ view: NoteTitleView, context: Context) {
        context.coordinator.title = $title
        if view.field.stringValue != title, view.field.currentEditor() == nil { view.field.stringValue = title }
        if requestFocus, !context.coordinator.didRequestFocus {
            context.coordinator.didRequestFocus = true
            DispatchQueue.main.async { [weak view] in
                guard let view, view.window != nil else { return }
                view.window?.makeFirstResponder(view.field)
            }
        }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var title: Binding<String>
        var didRequestFocus = false
        init(title: Binding<String>) { self.title = title }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            title.wrappedValue = field.stringValue
        }
    }
}

struct RichNoteEditor: NSViewRepresentable {
    var note: BoardNote
    var cache: NoteEditorCache
    var typing: (String) -> Void
    var changed: (String, Data?, [String: Double]) -> Void
    func makeCoordinator() -> Coordinator {
        cache.session(for: note)?.coordinator ?? Coordinator(typing: typing, changed: changed)
    }
    func makeNSView(context: Context) -> NoteEditorView {
        context.coordinator.typing = typing; context.coordinator.changed = changed
        if let session = cache.session(for: note), session.coordinator === context.coordinator {
            session.editor.textView.delegate = context.coordinator
            cache.remember(session, for: note.id)
            return session.editor
        }
        let editor = NoteEditorView()
        let text = editor.textView
        text.isRichText = true; text.importsGraphics = true; text.allowsUndo = true
        // Fit image attachments during layout so resizing never changes the original image bytes.
        text.layoutManager?.defaultAttachmentScaling = .scaleProportionallyDown
        // Saved .link attributes remain clickable. Automatic detection is needed only
        // when the user edits, not when displaying an already saved document.
        text.isAutomaticLinkDetectionEnabled = false; text.isAutomaticSpellingCorrectionEnabled = false
        text.font = .systemFont(ofSize: 14); text.textColor = NSColor(Theme.ink)
        text.backgroundColor = .white; text.textContainerInset = NSSize(width: 14, height: 14)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        if let data = note.richText, let attributed = NSAttributedString(rtfd: data, documentAttributes: nil) { text.textStorage?.setAttributedString(attributed) }
        else { text.string = note.text }
        text.prepareImages(savedWidths: note.imageWidths)
        context.coordinator.textView = text
        context.coordinator.savedRichText = note.richText
        text.delegate = context.coordinator
        cache.remember(NoteEditorCache.Session(editor: editor, coordinator: context.coordinator), for: note.id)
        return editor
    }
    func updateNSView(_ view: NoteEditorView, context: Context) {
        context.coordinator.typing = typing; context.coordinator.changed = changed
    }
    static func dismantleNSView(_ view: NoteEditorView, coordinator: Coordinator) {
        coordinator.flush(); view.textView.delegate = nil
        view.textView.isAutomaticLinkDetectionEnabled = false
        view.closePreview()
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var typing: (String) -> Void
        var changed: (String, Data?, [String: Double]) -> Void
        weak var textView: NoteImageTextView?
        var savedRichText: Data?
        private var pendingSerialization: DispatchWorkItem?
        init(typing: @escaping (String) -> Void, changed: @escaping (String, Data?, [String: Double]) -> Void) {
            self.typing = typing; self.changed = changed
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(flush), name: .flushNoteEditors, object: nil)
        }
        deinit { pendingSerialization?.cancel(); NotificationCenter.default.removeObserver(self) }
        func textDidChange(_ notification: Notification) {
            guard let text = notification.object as? NoteImageTextView else { return }
            text.isAutomaticLinkDetectionEnabled = true
            text.prepareImages()
            typing(text.string)
            pendingSerialization?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.flush() }
            pendingSerialization = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
        @objc func flush() {
            guard pendingSerialization != nil, let text = textView else { return }
            pendingSerialization?.cancel(); pendingSerialization = nil
            let data = text.textStorage?.rtfd(from: NSRange(location: 0, length: text.textStorage?.length ?? 0), documentAttributes: [:])
            savedRichText = data
            changed(text.string, data, text.imageWidths)
        }
        func textDidEndEditing(_ notification: Notification) { flush() }
        func textViewDidChangeSelection(_ notification: Notification) {
            (notification.object as? NoteImageTextView)?.refreshImageSelection()
        }
    }
}

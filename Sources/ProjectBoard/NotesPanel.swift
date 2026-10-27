import SwiftUI
import AppKit
import BoardCore

struct NotesPanel: View {
    @EnvironmentObject private var store: BoardStore
    let project: BoardProject
    private var selected: BoardNote? { project.notes.first { $0.id == store.selectedNote } ?? project.notes.sorted { $0.updated > $1.updated }.first }
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Button {
                    let note = BoardNote(); store.updateProject { $0.notes.insert(note, at: 0) }; store.selectedNote = note.id
                } label: { Text("＋ 新建备忘").foregroundColor(Theme.accent).frame(maxWidth: .infinity, alignment: .leading).padding(12) }.buttonStyle(.plain)
                Divider().overlay(Theme.border)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(project.notes.sorted { $0.updated > $1.updated }) { note in
                            Button { store.selectedNote = note.id } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(note.displayTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    HStack(spacing: 4) { Text(note.updated, format: .dateTime.year().month().day()); Text("· " + (note.text.isEmpty ? "没有更多文字" : note.text.replacingOccurrences(of: "\n", with: " "))) }.font(.system(size: 11)).foregroundColor(Theme.muted).lineLimit(1)
                                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(selected?.id == note.id ? Color(hex: 0xF3E9D9) : .clear)
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
                        Text("自动保存").font(.system(size: 10)).foregroundColor(Theme.muted)
                        Button("删除") { deleteNote(note) }.buttonStyle(.plain).font(.system(size: 11)).foregroundColor(Theme.muted)
                    }.padding(.horizontal, 14).frame(height: 34)
                    Divider().overlay(Theme.border)
                    TextField("标题（留空则取正文第一行）", text: Binding(get: { note.title }, set: { value in store.updateNote(note.id) { $0.title = value } })).textFieldStyle(.plain).font(.system(size: 16, weight: .semibold)).padding(.horizontal, 16).frame(height: 44)
                    Divider().overlay(Theme.border)
                    RichNoteEditor(note: note) { text, data in store.updateNote(note.id) { $0.text = text; $0.richText = data } }.id(note.id)
                }.background(.white)
            } else { Text("还没有备忘，点左上角新建").foregroundColor(Theme.muted).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white) }
        }.frame(minHeight: 380, maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
    }
    private func deleteNote(_ note: BoardNote) {
        let alert = NSAlert(); alert.messageText = "删除这条备忘？"; alert.informativeText = note.displayTitle
        alert.addButton(withTitle: "删除"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.updateProject { $0.notes.removeAll { $0.id == note.id } }; store.selectedNote = nil
    }
}

struct RichNoteEditor: NSViewRepresentable {
    var note: BoardNote
    var changed: (String, Data?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(changed: changed) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let text = NSTextView()
        text.isRichText = true; text.importsGraphics = true; text.allowsUndo = true
        text.isAutomaticLinkDetectionEnabled = true; text.isAutomaticSpellingCorrectionEnabled = false
        text.font = .systemFont(ofSize: 14); text.textColor = NSColor(Theme.ink)
        text.backgroundColor = .white; text.textContainerInset = NSSize(width: 14, height: 14)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        if let data = note.richText, let attributed = NSAttributedString(rtfd: data, documentAttributes: nil) { text.textStorage?.setAttributedString(attributed) }
        else { text.string = note.text }
        text.delegate = context.coordinator; scroll.documentView = text
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) { context.coordinator.changed = changed }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var changed: (String, Data?) -> Void
        init(changed: @escaping (String, Data?) -> Void) { self.changed = changed }
        func textDidChange(_ notification: Notification) {
            guard let text = notification.object as? NSTextView else { return }
            let data = text.textStorage?.rtfd(from: NSRange(location: 0, length: text.textStorage?.length ?? 0), documentAttributes: [:])
            changed(text.string, data)
        }
    }
}

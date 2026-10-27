import SwiftUI

enum Theme {
    static let background = Color(hex: 0xF7F7F5)
    static let ink = Color(hex: 0x1F1F1D)
    static let muted = Color(hex: 0x8A8779)
    static let border = Color(hex: 0xE6E4DF)
    static let selection = Color(hex: 0xECEAE3)
    static let accent = Color(hex: 0xB06F3A)
    static let colors = [0xB06F3A, 0x5B8A72, 0x5A7DA8, 0xA85A8A, 0x8A7A3A, 0x7A5AA8, 0xA85A5A, 0x3A8A8A]
    static func projectColor(_ index: Int) -> Color { Color(hex: colors[abs(index % colors.count)]) }
}

extension Color {
    init(hex: Int) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
}

struct DarkButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .medium)).foregroundColor(.white)
            .padding(.horizontal, 15).frame(height: 36)
            .background(Theme.ink.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct OutlinedButton: ButtonStyle {
    var dashed = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13)).foregroundColor(Theme.muted)
            .padding(.horizontal, 12).frame(height: 34)
            .background(configuration.isPressed ? Theme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: dashed ? [4, 3] : [])))
    }
}

struct BoardField: ViewModifier {
    func body(content: Content) -> some View {
        content.textFieldStyle(.plain).font(.system(size: 14)).padding(.horizontal, 10).frame(height: 37)
            .background(.white, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border))
    }
}

struct NameSheet: View {
    var title: String
    var hint = ""
    @State var name: String = ""
    var submit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 19, weight: .semibold))
            if !hint.isEmpty { Text(hint).font(.system(size: 12)).foregroundColor(Theme.muted) }
            TextField("名称", text: $name).modifier(BoardField()).focused($focused).onSubmit(commit)
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("确定", action: commit).buttonStyle(DarkButton()).keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(24).frame(width: 400).onAppear { focused = true }
    }
    private func commit() {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }; submit(value); dismiss()
    }
}

import SwiftUI
import AppKit
import BoardCore

struct LinksPanel: View {
    @EnvironmentObject private var store: BoardStore
    let project: BoardProject
    @State private var title = ""
    @State private var url = ""
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if project.links.isEmpty { Text("还没有链接").foregroundColor(Theme.muted).padding(.vertical, 32) }
                    ForEach(project.links) { link in
                        HStack(spacing: 10) {
                            Image(systemName: "link").foregroundColor(Theme.muted)
                            Button { if let url = URL(string: link.url), ["https", "http"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) } } label: {
                                VStack(alignment: .leading, spacing: 3) { Text(link.title.isEmpty ? link.url : link.title).foregroundColor(Theme.accent); if !link.title.isEmpty { Text(link.url).font(.system(size: 11)).foregroundColor(Theme.muted).lineLimit(1) } }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(link.url, forType: .string); store.message("链接已复制") } label: { Image(systemName: "doc.on.doc").font(.system(size: 12)) }.buttonStyle(.plain).foregroundColor(Theme.muted)
                            Button { store.updateProject { $0.links.removeAll { $0.id == link.id } } } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain).foregroundColor(Theme.muted)
                        }.padding(.vertical, 12).overlay(alignment: .bottom) { Rectangle().fill(Theme.border.opacity(0.5)).frame(height: 1) }
                    }
                }.frame(maxWidth: .infinity)
            }.frame(maxHeight: project.links.isEmpty ? 95 : .infinity)
            HStack(spacing: 8) {
                TextField("标题（可选）", text: $title).modifier(BoardField())
                TextField("https://…", text: $url).modifier(BoardField()).onSubmit(add)
                Button("添加", action: add).buttonStyle(DarkButton()).disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(.top, 14)
        }
    }
    private func add() {
        var input = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !input.contains("://") { input = "https://" + input }
        guard let parsed = URL(string: input), ["https", "http"].contains(parsed.scheme?.lowercased() ?? ""), let host = parsed.host, !host.isEmpty else { store.errorMessage = "请输入有效的 http 或 https 链接。"; return }
        store.updateProject { $0.links.append(BoardLink(title: title.trimmingCharacters(in: .whitespacesAndNewlines), url: input)) }; title = ""; url = ""
    }
}

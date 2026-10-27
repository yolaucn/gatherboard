import SwiftUI
import AppKit
import BoardCore

struct ContentView: View {
    @EnvironmentObject private var store: BoardStore
    @State private var newProject = false
    @State private var renameProject = false
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 220)
            Rectangle().fill(Theme.border).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                if let project = store.project {
                    header(project)
                    tabs(project).padding(.top, 18)
                    Group {
                        switch store.tab {
                        case .tasks: TasksPanel(project: project)
                        case .notes: NotesPanel(project: project)
                        case .links: LinksPanel(project: project)
                        case .files: FilesPanel(project: project)
                        }
                    }.padding(.top, 16).id(project.id)
                } else {
                    welcome
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 28).padding(.top, 30).padding(.bottom, 20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Theme.background).foregroundColor(Theme.ink).font(.system(size: 14)).tint(Theme.accent)
        .disabled(store.busy)
        .overlay { if store.busy { ZStack { Color.black.opacity(0.08); HStack(spacing: 12) { ProgressView().controlSize(.small); Text("正在处理真实文件…").font(.system(size: 14)) }.padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } } }
        .overlay(alignment: .bottom) {
            if let notice = store.notice { Text(notice).font(.system(size: 12)).foregroundColor(.white).padding(.horizontal, 18).padding(.vertical, 10).background(Theme.ink, in: Capsule()).padding(.bottom, 16).allowsHitTesting(false) }
        }
        .sheet(isPresented: $newProject) { NameSheet(title: "新建项目", hint: "会同时在资料库里创建真实项目文件夹。", submit: store.createProject) }
        .sheet(isPresented: $renameProject) { NameSheet(title: "重命名项目", name: store.project?.name ?? "", submit: store.renameProject) }
        .alert("操作未完成", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) { Button("知道了") { store.errorMessage = nil } } message: { Text(store.errorMessage ?? "") }
        .onReceive(timer) { _ in store.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .newBoardProject)) { _ in newProject = true }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.refresh() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("📋")
                VStack(alignment: .leading, spacing: 1) {
                    Text("归拢").fontWeight(.semibold)
                    Text("本地项目看板").font(.system(size: 9)).foregroundColor(Theme.muted)
                }
            }.padding(.horizontal, 16).padding(.top, 38).padding(.bottom, 18)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(store.library.projects) { project in
                        Button { store.select(project.id) } label: {
                            HStack(spacing: 9) {
                                Circle().fill(Theme.projectColor(project.color)).frame(width: 9, height: 9)
                                Text(project.name).lineLimit(1).fontWeight(store.selectedProject == project.id ? .semibold : .regular)
                                Spacer(minLength: 4)
                                if project.pendingCount > 0 { Text("\(project.pendingCount)").font(.system(size: 11)).foregroundColor(Theme.muted) }
                            }.padding(.horizontal, 11).frame(height: 37)
                                .background(store.selectedProject == project.id ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .contextMenu {
                            Button("重命名…") { store.select(project.id); renameProject = true }
                            Button("在 Finder 中打开") { if let url = try? store.repository.projectURL(project) { NSWorkspace.shared.open(url) } }
                            Divider()
                            Button("删除项目…", role: .destructive) { store.select(project.id); store.deleteProject() }
                        }
                    }
                }.padding(.horizontal, 9)
            }
            VStack(spacing: 13) {
                Button { newProject = true } label: { Text("＋ 新建项目").frame(maxWidth: .infinity) }.buttonStyle(OutlinedButton(dashed: true)).disabled(!store.ready)
                Rectangle().fill(Theme.border).frame(height: 1)
                HStack(spacing: 14) {
                    Button("↓ 导出备份", action: store.backup)
                    Button("↑ 导入", action: store.restore)
                }.buttonStyle(.plain).font(.system(size: 12)).foregroundColor(Theme.muted).disabled(!store.ready)
                Button { store.chooseLibrary() } label: { Label("资料库位置", systemImage: "folder").font(.system(size: 11)).foregroundColor(Theme.muted) }.buttonStyle(.plain)
            }.padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 18)
        }.background(.white)
    }

    private func header(_ project: BoardProject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle().fill(Theme.projectColor(project.color)).frame(width: 12, height: 12)
                Text(project.name).font(.system(size: 22, weight: .bold)).onTapGesture(count: 2) { renameProject = true }
                Button { renameProject = true } label: { Image(systemName: "pencil").font(.system(size: 12)) }.buttonStyle(.plain).foregroundColor(Theme.muted).help("重命名项目")
                Button(action: store.deleteProject) { Image(systemName: "trash").font(.system(size: 14)) }.buttonStyle(.plain).foregroundColor(Theme.muted).help("删除项目并将文件夹移到废纸篓")
                Spacer()
            }
            if let url = try? store.repository.projectURL(project) {
                HStack(spacing: 7) {
                    Text("归档文件夹：").foregroundColor(Theme.muted)
                    Text(url.path).font(.system(size: 10, design: .monospaced)).foregroundColor(Theme.muted).lineLimit(1).truncationMode(.middle).padding(.horizontal, 5).padding(.vertical, 3).background(Theme.selection, in: RoundedRectangle(cornerRadius: 3)).textSelection(.enabled)
                    Button("复制路径") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.path, forType: .string); store.message("路径已复制") }.buttonStyle(.plain).foregroundColor(Theme.accent)
                    Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.forward.square") }.buttonStyle(.plain).foregroundColor(Theme.accent).help("在 Finder 中打开")
                }.font(.system(size: 11))
            }
        }
    }

    private func tabs(_ project: BoardProject) -> some View {
        HStack(spacing: 0) {
            ForEach(BoardTab.allCases, id: \.self) { tab in
                Button { store.tab = tab } label: {
                    HStack(spacing: 5) {
                        Text(tab.rawValue).fontWeight(store.tab == tab ? .semibold : .regular)
                        if tab != .files { Text("\(tab == .tasks ? project.pendingCount : tab == .notes ? project.notes.count : project.links.count)").font(.system(size: 10)).foregroundColor(Theme.muted) }
                    }.padding(.horizontal, 14).frame(height: 38)
                        .foregroundColor(store.tab == tab ? Theme.ink : Theme.muted)
                        .overlay(alignment: .bottom) { if store.tab == tab { Rectangle().fill(Theme.accent).frame(height: 2) } }
                }.buttonStyle(.plain)
            }
            Spacer()
        }.overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1).offset(y: 1) }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 40, weight: .ultraLight)).foregroundColor(Theme.accent)
            Text(store.ready ? "把工作，放在一起。" : "打开你的本地资料库").font(.system(size: 23, weight: .semibold))
            Text("任务、备忘、链接和原始文件，都留在你的 Mac 上。").font(.system(size: 13)).foregroundColor(Theme.muted)
            if store.ready { Button("＋ 创建第一个项目") { newProject = true }.buttonStyle(DarkButton()) }
            Button("选择资料目录…", action: store.chooseLibrary).buttonStyle(.plain).foregroundColor(Theme.accent)
            Text(store.repository.root.path).font(.system(size: 10, design: .monospaced)).foregroundColor(Theme.muted).textSelection(.enabled)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

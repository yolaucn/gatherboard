import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct ProjectBoardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = BoardStore()

    var body: some Scene {
        Window("归拢", id: "main") {
            ContentView().environmentObject(store)
                .frame(minWidth: 880, minHeight: 600)
                .preferredColorScheme(.light)
        }
        .defaultSize(width: 1080, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建项目…") { NotificationCenter.default.post(name: .newBoardProject, object: nil) }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(!store.ready || store.busy)
                Button("导入文件…") { store.tab = .files; store.chooseImport() }.keyboardShortcut("i").disabled(store.project == nil || store.busy)
            }
            CommandMenu("资料库") {
                Button("在 Finder 中打开资料目录") { NSWorkspace.shared.open(store.repository.root) }
                Button("选择其他资料库…") { store.chooseLibrary() }.disabled(store.busy)
                Divider()
                Button("导出完整备份…") { store.backup() }.disabled(!store.ready || store.busy)
                Button("合并导入备份…") { store.restore() }.disabled(!store.ready || store.busy)
            }
        }
    }
}

extension Notification.Name { static let newBoardProject = Notification.Name("newBoardProject") }

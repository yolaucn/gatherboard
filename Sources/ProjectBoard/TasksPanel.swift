import SwiftUI
import BoardCore

struct TasksPanel: View {
    @EnvironmentObject private var store: BoardStore
    let project: BoardProject
    @State private var text = ""
    @State private var hasDue = false
    @State private var due = Date()
    @State private var editing: BoardTask?

    private var sortedTasks: [BoardTask] {
        project.tasks.sorted {
            if $0.done != $1.done { return !$0.done }
            return ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if project.tasks.isEmpty { Text("还没有任务").foregroundColor(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 32) }
                    ForEach(sortedTasks) { task in
                        HStack(spacing: 12) {
                            Toggle("完成任务", isOn: Binding(get: { task.done }, set: { value in store.updateProject { p in if let i = p.tasks.firstIndex(where: { $0.id == task.id }) { p.tasks[i].done = value } } })).labelsHidden().toggleStyle(.checkbox).tint(.blue)
                            Text(task.text).strikethrough(task.done).foregroundColor(task.done ? Theme.muted.opacity(0.7) : Theme.ink).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture { editing = task }.help("点击编辑任务")
                            if let due = task.due { Text(due, format: .dateTime.year().month(.twoDigits).day(.twoDigits)).font(.system(size: 11)).foregroundColor(!task.done && Calendar.current.startOfDay(for: due) < Calendar.current.startOfDay(for: Date()) ? .red : Theme.accent) }
                            Button { store.updateProject { $0.tasks.removeAll { $0.id == task.id } } } label: { Image(systemName: "xmark").font(.system(size: 10)).foregroundColor(Theme.muted.opacity(0.6)) }.buttonStyle(.plain).help("删除任务")
                        }.padding(.horizontal, 7).padding(.vertical, 12)
                            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border.opacity(0.5)).frame(height: 1) }
                    }
                }
            }.frame(maxHeight: project.tasks.isEmpty ? 95 : .infinity)
            HStack(spacing: 8) {
                TextField("新任务…", text: $text).modifier(BoardField()).onSubmit(add)
                Toggle("日期", isOn: $hasDue).font(.system(size: 12)).toggleStyle(.checkbox)
                if hasDue { DatePicker("截止日期", selection: $due, displayedComponents: .date).labelsHidden().frame(width: 112) }
                Button("添加", action: add).buttonStyle(DarkButton()).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(.top, 14)
        }
        .sheet(item: $editing) { task in
            EditTaskSheet(task: task) { updated in store.updateProject { p in if let i = p.tasks.firstIndex(where: { $0.id == updated.id }) { p.tasks[i] = updated } } }
        }
    }
    private func add() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !value.isEmpty else { return }
        store.updateProject { $0.tasks.append(BoardTask(text: value, due: hasDue ? due : nil)) }; text = ""
    }
}

struct EditTaskSheet: View {
    @State var task: BoardTask
    var submit: (BoardTask) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("编辑任务").font(.system(size: 19, weight: .semibold))
            TextField("任务内容", text: $task.text).modifier(BoardField())
            Toggle("设置截止日期", isOn: Binding(get: { task.due != nil }, set: { task.due = $0 ? Date() : nil }))
            if task.due != nil { DatePicker("截止日期", selection: Binding(get: { task.due ?? Date() }, set: { task.due = $0 }), displayedComponents: .date) }
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("保存") { submit(task); dismiss() }.buttonStyle(DarkButton()).disabled(task.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(24).frame(width: 420)
    }
}

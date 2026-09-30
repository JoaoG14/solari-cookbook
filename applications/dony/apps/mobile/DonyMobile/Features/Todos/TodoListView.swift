import SwiftUI

struct TodoListView: View {
    @Environment(TodoStore.self) private var store
    @Environment(CompanionStore.self) private var companion
    @State private var editor: Editor?
    @State private var showingVoice = false

    private struct Editor: Identifiable {
        let id = UUID()
        let item: TodoItem?
        let parent: TodoItem?
    }

    var body: some View {
        VStack(spacing: 0) {
            TodoModePicker()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            todoList
                .clipped()
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [Color("TodoSurface"), Color("TodoSurface").opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 16)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
        }
        .background(Color("TodoSurface").ignoresSafeArea())
        .tint(Color("TodoInk"))
        .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
            Button { openEditor() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(.blue, in: Circle())
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add task")
            .accessibilityIdentifier("add-todo")
            .contextMenu {
                Button("Add task", systemImage: "plus") { openEditor() }
                Button("Speak tasks", systemImage: "mic") { openVoice() }
            }
            .padding(.trailing, 20)
            .padding(.vertical, 12)
            .opacity(editor == nil ? 1 : 0)
        }
        .tabTitle("To-do List")
        .sheet(item: $editor) { editor in
            if let item = editor.item {
                TodoDetailView(item: item)
            } else {
                TodoEditorView(item: nil, parent: editor.parent) { title, dueDate, subtasks in
                    guard let task = store.add(title, dueDate: dueDate, parent: editor.parent) else { return }
                    for subtask in subtasks {
                        store.add(subtask, dueDate: nil, parent: task)
                    }
                }
            }
        }
        .sheet(isPresented: $showingVoice) {
            TodoVoiceView { titles in
                for title in titles { store.add(title, dueDate: nil, parent: nil) }
            }
        }
    }

    private var todoList: some View {
        List {
            if !store.items.isEmpty {
                section("Active", items: store.active, completed: false)
                if !store.completed.isEmpty {
                    section("Completed", items: store.completed, completed: true)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color("TodoSurface"))
        .overlay {
            if store.items.isEmpty {
                ContentUnavailableView {
                    Label("A little room to focus", systemImage: "checklist")
                } description: {
                    Text("Add your first to-do.")
                } actions: {
                    Button("Add a to-do") { openEditor() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
        }
    }

    private func section(_ title: String, items: [TodoItem], completed: Bool) -> some View {
        Section {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    TodoRow(item: item, toggle: { store.toggle(item) }, edit: { openEditor(item) })
                    ForEach(store.children(of: item)) { child in
                        TodoRow(item: child, toggle: { store.toggle(child) }, edit: { openEditor(child, parent: item) })
                            .padding(.leading, 28)
                            .contextMenu {
                                Button("Delete subtask", systemImage: "trash", role: .destructive) { store.delete(child) }
                            }
                            .accessibilityAction(named: "Delete subtask") { store.delete(child) }
                    }
                }
                    .listRowInsets(EdgeInsets(top: 2, leading: 13, bottom: 2, trailing: 24))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { store.delete(item) }
                            .tint(.red)
                    }
                    .accessibilityAction(named: "Delete to-do") { store.delete(item) }
            }
            .onMove { offsets, destination in
                store.move(from: offsets, to: destination, completed: completed)
            }

            if items.isEmpty {
                Text(completed ? "Completed to-dos will appear here." : "All caught up. Add a to-do whenever you’re ready.")
                    .font(.subheadline).foregroundStyle(Color("TodoMuted"))
                    .padding(.vertical, 8)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        } header: {
            if completed {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color("TodoMuted"))
                    .textCase(nil)
                    .padding(.top, 16)
            }
        }
    }

    private func openEditor(_ item: TodoItem? = nil, parent: TodoItem? = nil) {
        editor = Editor(item: item, parent: parent)
    }

    private func openVoice() {
        if companion.requestVoiceTasks() { showingVoice = true }
    }
}

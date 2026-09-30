import SwiftUI

struct TodoDetailView: View {
    @Environment(TodoStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showingDatePicker = false
    @State private var editor: Editor?
    let item: TodoItem

    private struct Editor: Identifiable {
        let id = UUID()
        let item: TodoItem?
        let parent: TodoItem?
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        TodoRow(item: item, toggle: { store.toggle(item) }, edit: {
                            editor = Editor(item: item, parent: nil)
                        }, showsDueDate: false)
                        Divider().padding(.leading, 44)
                        Button { showingDatePicker = true } label: {
                            Label(item.dueDate.map { TodoDueDate.label($0) } ?? "Date", systemImage: "calendar")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .padding(.leading, 12)
                        }
                        .accessibilityIdentifier("edit-due-date")
                    }
                    .padding(12)
                    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))

                    TaskAgentWorkView(item: item)

                    if item.parentID == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Subtasks")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color("TodoMuted"))
                            ForEach(store.children(of: item)) { child in
                                TodoRow(item: child, toggle: { store.toggle(child) }, edit: {
                                    editor = Editor(item: child, parent: item)
                                })
                                .contextMenu {
                                    Button("Delete subtask", systemImage: "trash", role: .destructive) { store.delete(child) }
                                }
                                .accessibilityAction(named: "Delete subtask") { store.delete(child) }
                            }
                            Button {
                                editor = Editor(item: nil, parent: item)
                            } label: {
                                Label("Add subtask", systemImage: "plus")
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .background(.primary.opacity(0.04), in: Capsule())
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color("TodoSurface"))
            .accessibilityIdentifier("task-detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu("Task actions", systemImage: "ellipsis") {
                        Button("Delete task", systemImage: "trash", role: .destructive) {
                            store.delete(item)
                            dismiss()
                        }
                    }
                }
            }
            .sheet(isPresented: $showingDatePicker) {
                TodoDatePickerView(dueDate: item.dueDate) {
                    store.update(item, title: item.title, dueDate: $0)
                }
            }
            .sheet(item: $editor) { editor in
                TodoEditorView(item: editor.item, parent: editor.parent) { title, dueDate, _ in
                    if let editedItem = editor.item {
                        store.update(editedItem, title: title, dueDate: dueDate)
                    } else {
                        store.add(title, dueDate: dueDate, parent: editor.parent)
                    }
                }
            }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.fraction(0.65), .large])
        .presentationDragIndicator(.visible)
    }
}

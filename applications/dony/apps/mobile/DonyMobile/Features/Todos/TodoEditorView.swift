import Observation
import SwiftUI

struct TodoEditorView: View {
    @Environment(DemoChatStore.self) private var chats
    @Environment(TodoStore.self) private var store
    @Environment(CompanionStore.self) private var companion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var focusedField: Field?
    @State private var title: String
    @State private var titleSelection: TextSelection?
    @State private var dueDate: String?
    @State private var showingDatePicker = false
    @State private var showingVoice = false
    @State private var composerContentHeight: CGFloat = 76
    @State private var mentionContentHeight: CGFloat = 190
    @State private var subtasks: [SubtaskDraft] = []
    let parent: TodoItem?
    let item: TodoItem?
    let save: (String, String?, [String]) -> Void

    private enum Field: Hashable {
        case title
        case subtask(UUID)
    }

    @Observable
    fileprivate final class SubtaskDraft: Identifiable {
        let id = UUID()
        var title = ""
        var selection: TextSelection?
    }

    init(item: TodoItem?, parent: TodoItem? = nil, save: @escaping (String, String?, [String]) -> Void) {
        self.item = item
        self.parent = parent
        self.save = save
        self._title = State(initialValue: item?.title ?? "")
        self._dueDate = State(initialValue: item?.dueDate)
    }

    var body: some View {
        Group {
            if item == nil {
                compactComposer
            } else {
                editForm
            }
        }
        .onAppear { focusedField = .title }
        .onChange(of: title) { titleSelection = nil }
        .sheet(isPresented: $showingDatePicker, onDismiss: { focusedField = .title }) {
            TodoDatePickerView(dueDate: dueDate) { dueDate = $0 }
        }
        .sheet(isPresented: $showingVoice, onDismiss: { focusedField = .title }) {
            TodoVoiceView { titles in
                for title in titles { store.add(title, dueDate: nil, parent: nil) }
            }
        }
    }

    private var compactComposer: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 8) {
                        TextField(parent == nil ? "Task name" : "Subtask name", text: $title, selection: $titleSelection, axis: .vertical)
                            .font(.title3.weight(.medium))
                            .lineLimit(1...4)
                            .frame(minHeight: 44)
                            .focused($focusedField, equals: .title)
                            .accessibilityLabel("To-do title")
                            .accessibilityHint("Type @ to tag an agent")
                            .accessibilityIdentifier("todo-title")
                            .background { mentionOverlay(for: .title) }
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color("TodoMuted"))
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Cancel")
                    }
                    if let parent {
                        Label(parent.title, systemImage: "arrow.turn.down.right")
                            .font(.subheadline)
                            .foregroundStyle(Color("TodoMuted"))
                            .lineLimit(2)
                    }
                    ForEach(subtasks) { subtask in
                        @Bindable var subtask = subtask
                        HStack(spacing: 12) {
                            Image(systemName: "circle")
                                .foregroundStyle(Color("TodoQuiet"))
                                .accessibilityHidden(true)
                            TextField("Subtask name", text: $subtask.title, selection: $subtask.selection, axis: .vertical)
                                .focused($focusedField, equals: .subtask(subtask.id))
                                .onChange(of: subtask.title) { subtask.selection = nil }
                                .accessibilityLabel("Subtask title")
                                .accessibilityHint("Type @ to tag an agent")
                                .background { mentionOverlay(for: .subtask(subtask.id)) }
                            Button {
                                if focusedField == .subtask(subtask.id) { focusedField = .title }
                                subtasks.removeAll { $0.id == subtask.id }
                            } label: {
                                Image(systemName: "xmark")
                                    .foregroundStyle(Color("TodoMuted"))
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Remove subtask")
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 8)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    composerContentHeight = $0
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            HStack(spacing: 10) {
                if parent == nil {
                    Button {
                        let subtask = SubtaskDraft()
                        subtasks.append(subtask)
                        focusedField = .subtask(subtask.id)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .regular))
                            .frame(width: 44, height: 44)
                            .background(Color("TodoInk").opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel("Add subtask")
                    Button {
                        focusedField = nil
                        if companion.requestVoiceTasks() { showingVoice = true }
                    } label: {
                        Image(systemName: "mic")
                            .font(.system(size: 18))
                            .frame(width: 44, height: 44)
                            .background(Color("TodoInk").opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel("Speak tasks")
                    .accessibilityIdentifier("composer-voice-tasks")
                }
                Button {
                    focusedField = nil
                    showingDatePicker = true
                } label: {
                    Label(dueDate.map { TodoDueDate.label($0) } ?? "Date", systemImage: "calendar")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .foregroundStyle(dueDate == nil ? Color("TodoMuted") : .blue)
                        .background(dueDate == nil ? Color.clear : Color.blue.opacity(0.08), in: Capsule())
                        .overlay { Capsule().strokeBorder(Color("TodoInk").opacity(0.12), lineWidth: 1) }
                }
                .accessibilityIdentifier("edit-due-date")
                Spacer(minLength: 0)
                Button(action: saveTask) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.blue, in: Circle())
                        .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Save")
                .accessibilityHint(parent == nil ? "Add task" : "Add subtask")
            }
            .padding(16)
            .background(composerSurface)
        }
        .foregroundStyle(Color("TodoInk"))
        .tint(.blue)
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-composer")
        .background(composerSurface)
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .padding(.bottom, 8)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(min(composerContentHeight + 84, 380))])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(32)
        .presentationBackground(.clear)
    }

    private var composerSurface: some View {
        Color("TodoSurface").overlay(Color("TodoInk").opacity(0.04))
    }

    private func mentionOverlay(for field: Field) -> some View {
        TodoMentionOverlay(isPresented: focusedField == field && mentionQuery != nil) {
            agentSuggestions
        }
    }

    private var mentionQuery: TodoAgentMention.Query? {
        let text: String
        let selection: TextSelection?
        switch focusedField {
        case .title:
            text = title
            selection = titleSelection
        case .subtask(let id):
            guard let subtask = subtasks.first(where: { $0.id == id }) else { return nil }
            text = subtask.title
            selection = subtask.selection
        case nil:
            return nil
        }
        if let selection {
            guard case .selection(let range) = selection.indices, range.isEmpty else { return nil }
            return TodoAgentMention.query(in: text, selection: range)
        }
        return TodoAgentMention.query(in: text, caret: text.utf16.count)
    }

    @ViewBuilder
    private var agentSuggestions: some View {
        if let query = mentionQuery {
            let search = TodoAgentMention.normalize(query.text)
            let agents = chats.agents.filter {
                TodoAgentMention.tag(for: $0.name) != "@" &&
                    (search.isEmpty || TodoAgentMention.normalize($0.name).contains(search))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if agents.isEmpty {
                        Text(chats.agents.isEmpty ? "Your agents will appear here when available." : "No matching agents")
                            .font(.subheadline)
                            .foregroundStyle(Color("TodoMuted"))
                            .padding(12)
                    } else {
                        ForEach(agents) { agent in
                            Button { insertMention(agent, query: query) } label: {
                                HStack(spacing: 12) {
                                    AgentAvatar(agent: agent, size: 24)
                                    Text(agent.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(TodoMentionButtonStyle())
                            .accessibilityLabel("Tag \(agent.name)")
                            .accessibilityIdentifier("todo-mention-\(agent.id)")
                        }
                    }
                }
                .padding(.vertical, 6)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { mentionContentHeight = $0 }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("todo-agent-suggestions")
            }
            .frame(height: min(mentionContentHeight, 280))
            .scrollBounceBehavior(.basedOnSize)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.14), radius: 16, y: 6)
        }
    }

    private func insertMention(_ agent: DemoAgent, query: TodoAgentMention.Query) {
        let tag = TodoAgentMention.tag(for: agent.name)
        switch focusedField {
        case .title:
            let result = TodoAgentMention.inserting(tag, into: title, query: query)
            title = result.text
            titleSelection = TextSelection(insertionPoint: String.Index(utf16Offset: result.caret, in: result.text))
        case .subtask(let id):
            guard let subtask = subtasks.first(where: { $0.id == id }) else { return }
            let result = TodoAgentMention.inserting(tag, into: subtask.title, query: query)
            subtask.title = result.text
            subtask.selection = TextSelection(insertionPoint: String.Index(utf16Offset: result.caret, in: result.text))
        case nil:
            break
        }
    }

    private func saveTask() {
        let subtaskTitles = subtasks.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        save(title, dueDate, subtaskTitles)
        dismiss()
    }

    private var editForm: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(Color("TodoQuiet"))
                            .accessibilityHidden(true)
                        TextField("Task name", text: $title, selection: $titleSelection, axis: .vertical)
                            .font(.body.weight(.medium))
                            .lineLimit(1...8)
                            .focused($focusedField, equals: .title)
                            .accessibilityLabel("To-do title")
                            .accessibilityHint("Type @ to tag an agent")
                            .accessibilityIdentifier("todo-title")
                            .background { mentionOverlay(for: .title) }
                    }
                    if let parent {
                        Label(parent.title, systemImage: "arrow.turn.down.right")
                            .font(.subheadline)
                            .foregroundStyle(Color("TodoMuted"))
                    }
                    Button {
                        focusedField = nil
                        showingDatePicker = true
                    } label: {
                        Label(dueDate.map { TodoDueDate.label($0) } ?? "Date", systemImage: "calendar")
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(.primary.opacity(0.05), in: Capsule())
                    }
                    .accessibilityIdentifier("edit-due-date")
                }
                .padding(24)
            }
            .background(Color("TodoSurface"))
            .accessibilityIdentifier("task-composer")
            .navigationTitle("Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", action: saveTask)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

import SwiftUI

struct ChatListView: View {
    @Environment(DemoChatStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(CompanionStore.self) private var companion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var path: [String] = []
    @State private var showingNewChat = false
    @State private var editingAgent: SyncedAgent?
    @State private var showingSearch = false
    @State private var searchText = ""
    @State private var selectedChatID: String?
    @State private var archiveConfirmation: (chatID: String, taskTitle: String)?

    private var chats: [DemoConversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return store.recent.filter { chat in
            chat.agent.name.localizedStandardContains(query)
                || chat.title.localizedStandardContains(query)
                || chat.messages.contains { $0.preview.localizedStandardContains(query) }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(store.recent) { chat in
                    Button { path.append(chat.id) } label: {
                        row(chat)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chat-\(chat.id)")
                    .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .contextMenu {
                        if let agent = companion.editableAgent(chat.agent.id) {
                            Button("Edit agent", systemImage: "pencil") { editingAgent = agent }
                        }
                    }
                    .swipeActions {
                        if store.isDemo || chat.instanceNumber != nil {
                            Button("Archive", systemImage: "archivebox", role: companion.linkedTask(for: chat.id) == nil ? .destructive : nil) {
                                requestArchive(chat)
                            }
                                .tint(.orange)
                        }
                    }
                    .accessibilityActions {
                        if store.isDemo || chat.instanceNumber != nil {
                            Button("Archive conversation") { requestArchive(chat) }
                        }
                    }
                }
                ForEach(store.idleAgents) { agent in
                    Button {
                        let id = store.createChat(agent: agent)
                        if !id.isEmpty { path.append(id) }
                    } label: {
                        HStack(spacing: 12) {
                            AgentStatusAvatar(agent: agent)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(agent.name).font(.body.weight(.semibold))
                                Text("Start a conversation").font(.subheadline).foregroundStyle(Color("TodoMuted"))
                            }
                        }.foregroundStyle(Color("TodoInk"))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .contextMenu {
                        if let agent = companion.editableAgent(agent.id) {
                            Button("Edit agent", systemImage: "pencil") { editingAgent = agent }
                        }
                    }
                }
                if store.isDemo && !store.recent.isEmpty {
                    Text("Demo chats")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: store.recent.map(\.id))
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color("TodoSurface"))
            .overlay {
                if store.recent.isEmpty && store.idleAgents.isEmpty {
                    ContentUnavailableView {
                        Label("No recent chats", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text(store.isDemo ? "Start a new demo chat with the plus button." : companion.isConnected ? "Start a chat with one of your agents." : "Sign in to start a conversation with your agents.")
                    } actions: {
                        if !store.isDemo && !companion.isConnected {
                            Button("Sign in to Dony") { companion.showingCloudSignIn = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .tabTitle("Employees")
            .alert("Archive chat and delete to-do?", isPresented: Binding(
                get: { archiveConfirmation != nil },
                set: { if !$0 { archiveConfirmation = nil } }
            ), presenting: archiveConfirmation) { confirmation in
                Button("Archive and delete", role: .destructive) {
                    store.archive(confirmation.chatID)
                }
                Button("Cancel", role: .cancel) {}
            } message: { confirmation in
                Text("Archiving this chat will delete “\(confirmation.taskTitle)” and its subtasks from your To-do List.")
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    searchButton
                }
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    newChatButton
                }
            }
            .navigationDestination(for: String.self) { id in
                ChatDetailView(conversationID: id)
            }
            .sheet(isPresented: $showingSearch, onDismiss: {
                searchText = ""
                guard let selectedChatID else { return }
                path.append(selectedChatID)
                self.selectedChatID = nil
            }) {
                searchSheet
            }
            .sheet(isPresented: $showingNewChat) {
                NewChatView { agent in
                    let id = store.createChat(agent: agent)
                    if !id.isEmpty { path.append(id) }
                }
            }
            .sheet(item: $editingAgent) { agent in
                AgentEditorView(agent: agent)
            }
            .onChange(of: companion.notificationThreadID) { _, id in
                if let id { path = [id]; companion.notificationThreadID = nil }
            }
            .onAppear {
                if let id = companion.notificationThreadID { path = [id]; companion.notificationThreadID = nil }
            }
            .onChange(of: store.resetCount) { path.removeAll() }
        }
    }

    private func requestArchive(_ chat: DemoConversation) {
        guard let task = companion.linkedTask(for: chat.id) else {
            store.archive(chat.id)
            return
        }
        archiveConfirmation = (chat.id, task.title)
    }

    private var searchButton: some View {
        Button("Search chats", systemImage: "magnifyingglass") { showingSearch = true }
            .accessibilityIdentifier("search-chats")
    }

    private var newChatButton: some View {
        Button("New chat", systemImage: "plus") {
            guard companion.requireAIAccess() else { return }
            showingNewChat = true
        }
            .accessibilityIdentifier("new-chat")
    }

    private var searchSheet: some View {
        NavigationStack {
            List(chats) { chat in
                Button {
                    selectedChatID = chat.id
                    showingSearch = false
                } label: {
                    row(chat)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("search-result-\(chat.id)")
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color("TodoSurface"))
            .tint(Color("TodoInk"))
            .overlay {
                if chats.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "Find a chat" : "No matching chats",
                        systemImage: "magnifyingglass",
                        description: Text("Search agent names, conversation titles, and messages.")
                    )
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search chats")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle("Search chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingSearch = false }
                }
            }
        }
    }

    private func row(_ chat: DemoConversation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AgentStatusAvatar(agent: chat.agent, working: chat.status == .running, instanceNumber: chat.instanceNumber, needsAttention: chat.status == .blocked || chat.status == .failed)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(chat.agent.name)
                        .font(.body.weight(.semibold))
                        .layoutPriority(1)
                    if !typeSize.isAccessibilitySize && chat.instanceNumber != nil {
                        Text(chat.title)
                            .font(.subheadline)
                            .foregroundStyle(Color("TodoMuted"))
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.primary.opacity(0.06), in: Capsule())
                    }
                    Spacer(minLength: 0)
                    if !typeSize.isAccessibilitySize {
                        Text(chat.updatedAt, format: .dateTime.hour().minute())
                            .font(.caption)
                            .foregroundStyle(Color("TodoMuted"))
                            .fixedSize()
                    }
                }
                if typeSize.isAccessibilitySize {
                    if chat.instanceNumber != nil {
                        Text(chat.title).font(.subheadline).foregroundStyle(Color("TodoMuted"))
                    }
                    Text(chat.updatedAt, format: .dateTime.hour().minute())
                        .font(.caption).foregroundStyle(Color("TodoMuted"))
                }
                Text(.init(preview(for: chat)))
                    .font(.subheadline)
                    .foregroundStyle(Color("TodoMuted"))
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Color("TodoInk"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(chat.agent.name)\(chat.instanceNumber.map { ", task agent \($0), \(chat.title)" } ?? ""), \(preview(for: chat))")
        .accessibilityValue(chat.updatedAt.formatted(date: .abbreviated, time: .shortened))
    }

    private func preview(for chat: DemoConversation) -> String {
        if chat.status == .waiting && companion.connectionError != nil { return "Couldn’t send" }
        return chat.preview
    }
}

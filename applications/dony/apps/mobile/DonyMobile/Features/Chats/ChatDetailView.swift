import SwiftUI

struct ChatDetailView: View {
    @Environment(DemoChatStore.self) private var store
    @Environment(CompanionStore.self) private var companion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage private var thinkingValue: String
    let conversationID: String
    var initialMessageID: String? = nil
    @State private var showingSearch = false
    @State private var selectedMessageID: String?
    @State private var didScrollToInitialMessage = false
    @State private var showingThinking = false

    init(conversationID: String, initialMessageID: String? = nil) {
        self.conversationID = conversationID
        self.initialMessageID = initialMessageID
        _thinkingValue = AppStorage(wrappedValue: ChatThinking.balanced.rawValue, "chat.thinking.\(conversationID)")
    }

    private var thinking: Binding<ChatThinking> {
        Binding(get: { ChatThinking(rawValue: thinkingValue) ?? .balanced }, set: { thinkingValue = $0.rawValue })
    }

    var body: some View {
        Group {
            if let chat = store.conversation(id: conversationID) {
                let question = companion.thread(chat.id)?.question
                let thread = companion.thread(chat.id)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            Text(chat.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(Color("TodoMuted"))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.bottom, 8)

                            if chat.instanceNumber != nil {
                                Text(chat.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color("TodoMuted"))
                            }

                            if chat.messages.isEmpty && question == nil {
                                ContentUnavailableView("A fresh start", systemImage: "bubble.left", description: Text(store.isDemo ? "Say hello to \(chat.agent.name). You’ll get a local example reply." : "Send a message to \(chat.agent.name)."))
                            }

                            ForEach(chat.messages) { message in
                                VStack(alignment: .leading, spacing: 12) {
                                    if let summary = message.questionAnswer {
                                        AnsweredQuestionView(summary: summary)
                                    } else {
                                        MessageContent(message: message, agent: chat.agent)
                                    }
                                    if let result = latestOutput(for: message, in: chat) {
                                        TaskOutputReviewView(
                                            result: result,
                                            outputs: (companion.snapshot?.results ?? []).filter {
                                                $0.threadId == result.threadId && !$0.artifacts.isEmpty
                                            },
                                            isChat: true,
                                            allowsReview: companion.snapshot?.tasks.first { $0.id == result.taskId }?.status == "todo"
                                                && companion.thread(result.threadId)?.status != "running"
                                                && companion.snapshot?.results.first { $0.taskId == result.taskId }?.id == result.id
                                        )
                                    }
                                }
                                .id(message.id)
                            }

                            if let question {
                                AgentQuestionView(question: question)
                                    .id(question.id)
                            } else {
                                statusView(chat.status, activity: chat.activity)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(20)
                    }
                    .scrollClipDisabled()
                    .foregroundStyle(Color("TodoInk"))
                    .scrollDismissesKeyboard(.interactively)
                    .blur(radius: showingThinking && !reduceTransparency ? 8 : 0)
                    .allowsHitTesting(!showingThinking)
                    .accessibilityHidden(showingThinking)
                    .overlay {
                        if showingThinking {
                            Button {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.9)) {
                                    showingThinking = false
                                }
                            } label: {
                                Rectangle()
                                    .fill(reduceTransparency ? Color("TodoSurface") : Color("TodoSurface").opacity(0.25))
                                    .ignoresSafeArea()
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close thinking picker")
                            .accessibilityIdentifier("close-thinking-picker")
                        }
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if question == nil {
                            ChatComposer(
                                thinking: thinking,
                                showingThinking: $showingThinking,
                                agentColor: chat.agent.color,
                                isRunning: thread?.status == "running" && thread?.runId != nil,
                                isStopping: thread.map { companion.isStopping($0) } ?? false,
                                stop: { if let thread { companion.stop(thread) } },
                                onKeyboardShown: {
                                    guard !showingSearch else { return }
                                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                                        proxy.scrollTo("bottom", anchor: .bottom)
                                    }
                                }
                            ) { text, attachments in
                                store.send(text, attachments: attachments, to: chat.id, thinking: thinking.wrappedValue)
                            }
                        }
                    }
                    .onAppear {
                        if scrollToInitialMessage(in: chat, using: proxy) { return }
                        if let question { proxy.scrollTo(question.id, anchor: .top) }
                    }
                    .onChange(of: question?.id) {
                        if let question { proxy.scrollTo(question.id, anchor: .top) }
                    }
                    .sheet(isPresented: $showingSearch, onDismiss: {
                        guard let selectedMessageID else { return }
                        proxy.scrollTo(selectedMessageID, anchor: .top)
                        self.selectedMessageID = nil
                    }) {
                        ChatSearchView(chat: chat) { id in
                            selectedMessageID = id
                            showingSearch = false
                        }
                    }
                    .onChange(of: chat.messages.count) {
                        if scrollToInitialMessage(in: chat, using: proxy) { return }
                        guard question == nil else { return }
                        if reduceMotion {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                }
                .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.9), value: showingThinking)
                .navigationTitle(chat.agent.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Search chat", systemImage: "magnifyingglass") { showingSearch = true }
                            .disabled(showingThinking)
                            .blur(radius: showingThinking && !reduceTransparency ? 6 : 0)
                            .accessibilityIdentifier("search-chat-messages")
                    }
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 8) {
                            AgentStatusAvatar(agent: chat.agent, size: 28, working: chat.status == .running, instanceNumber: chat.instanceNumber, needsAttention: chat.status == .blocked)
                            Text(chat.agent.name).font(.headline)
                        }
                        .blur(radius: showingThinking && !reduceTransparency ? 6 : 0)
                    }
                }
                .toolbarBackground(Color("TodoSurface"), for: .navigationBar)
            } else {
                ContentUnavailableView("Conversation unavailable", systemImage: "bubble.left", description: Text("Go back to choose another conversation."))
            }
        }
        .background {
            Color("TodoSurface").ignoresSafeArea()
        }
        .toolbar(.hidden, for: .tabBar)
        .onAppear { store.view(conversationID) }
        .onDisappear {
            if store.openConversationID == conversationID { store.openConversationID = nil }
            store.refreshVisibility()
        }
    }

    private func scrollToInitialMessage(in chat: DemoConversation, using proxy: ScrollViewProxy) -> Bool {
        guard !didScrollToInitialMessage, let initialMessageID,
              chat.messages.contains(where: { $0.id == initialMessageID }) else { return false }
        proxy.scrollTo(initialMessageID, anchor: .top)
        didScrollToInitialMessage = true
        return true
    }

    private func latestOutput(for message: DemoMessage, in chat: DemoConversation) -> SyncResult? {
        guard message.role == .assistant, let results = companion.snapshot?.results else { return nil }
        return results.first { result in
            guard results.first(where: { $0.threadId == result.threadId })?.id == result.id else { return false }
            if let messageID = result.assistantMessageId { return messageID == message.id }
            return result.threadId == chat.id && chat.messages.last(where: { $0.role == .assistant })?.id == message.id
        }
    }

    @ViewBuilder
    private func statusView(_ status: DemoConversation.Status, activity: String?) -> some View {
        switch status {
        case .ready:
            EmptyView()
        case .running:
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if reduceMotion {
                        Image(systemName: "ellipsis.circle").accessibilityHidden(true)
                    } else {
                        ProgressView().accessibilityHidden(true)
                    }
                    Text(activity ?? "Working…").font(.headline)
                }
                Text(store.isDemo ? "Simulated progress. No agent is running. Send a message to see an example reply." : "Your agent is working.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("demo-running")
        case .waiting:
            if companion.connectionError == nil {
                ProgressView("Sending…").font(.subheadline).foregroundStyle(.secondary)
            }
        case .blocked:
            EmptyView()
        case .failed:
            VStack(alignment: .leading, spacing: 10) {
                Label(store.isDemo ? "An example error" : "Couldn’t finish", systemImage: "exclamationmark.circle")
                    .font(.headline)
                Text(store.isDemo ? "This response was interrupted in the demo. Nothing was lost or sent. Try the composer below to continue with a canned reply." : "You can send another message to continue this conversation.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if !store.isDemo {
                    Button("Try again") { store.send("Please try again.", to: conversationID, thinking: thinking.wrappedValue) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("retry-response")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("demo-error")
        }
    }
}

import Foundation
import Observation

@MainActor
@Observable
final class DemoChatStore {
    private(set) var conversations: [DemoConversation]
    private(set) var agents: [DemoAgent]
    var isDemo: Bool
    var onCreate: ((String, String) -> Bool)?
    var onSend: ((String, [DemoAttachment], String, ChatThinking?) -> Bool)?
    var onArchive: ((String) -> Bool)?
    var onView: ((String, Date) -> Bool)?
    var openConversationID: String?
    private var visibilityDate = Date.now
    private var expirationTask: Task<Void, Never>?


    init(isDemo: Bool = true) {
        self.isDemo = isDemo
        conversations = isDemo ? DemoFixtures.conversations : []
        agents = isDemo ? DemoAgent.allCases : []
    }
    private(set) var resetCount = 0

    private var visibleTaskChats: [DemoConversation] {
        let visible = conversations.filter {
            !$0.isArchived && $0.instanceNumber != nil &&
                ($0.id == openConversationID || $0.sidebarExpiresAt.map { $0 > visibilityDate } ?? true)
        }
        return agents.flatMap { agent in
            visible.filter { $0.agent.id == agent.id }
                .sorted { ($0.instanceNumber ?? 0) < ($1.instanceNumber ?? 0) }
                .enumerated().map { index, chat in
                    var chat = chat
                    chat.instanceNumber = index + 1
                    return chat
                }
        }
    }

    private func mainConversation(for agentID: String) -> DemoConversation? {
        let sessions = conversations.filter { !$0.isArchived && $0.agent.id == agentID && $0.instanceNumber == nil }
            .sorted { $0.updatedAt > $1.updatedAt }
        guard var chat = sessions.first(where: { $0.status == .running || $0.status == .blocked || $0.status == .waiting }) ?? sessions.first else { return nil }
        chat.title = "Chat"
        chat.createdAt = sessions.map(\.createdAt).min() ?? chat.createdAt
        chat.messages = sessions.flatMap(\.messages).sorted { $0.createdAt < $1.createdAt }
        chat.updatedAt = chat.messages.last?.createdAt ?? chat.updatedAt
        return chat
    }

    var recent: [DemoConversation] {
        if isDemo { return conversations.filter { !$0.isArchived } }
        let mainChats = agents.compactMap { mainConversation(for: $0.id) }
        return (mainChats + visibleTaskChats).sorted { $0.updatedAt > $1.updatedAt }
    }

    func refreshVisibility(now: Date = .now) {
        visibilityDate = now
        expirationTask?.cancel()
        guard let next = conversations.compactMap(\.sidebarExpiresAt).filter({ $0 > now }).min() else { return }
        expirationTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(next.timeIntervalSince(now))) }
            catch { return }
            self?.refreshVisibility()
        }
    }

    func view(_ id: String) {
        openConversationID = id
        guard !isDemo, let chat = conversation(id: id), chat.instanceNumber != nil, chat.viewedAt == nil else { return }
        _ = onView?(id, .now)
    }

    var idleAgents: [DemoAgent] {
        isDemo ? [] : agents.filter { agent in !recent.contains { $0.agent.id == agent.id && $0.instanceNumber == nil } }
    }

    func conversation(id: String) -> DemoConversation? {
        guard let chat = conversations.first(where: { $0.id == id && !$0.isArchived }) else { return nil }
        if isDemo { return chat }
        if chat.instanceNumber == nil { return mainConversation(for: chat.agent.id) }
        return visibleTaskChats.first { $0.id == id } ?? chat
    }

    @discardableResult
    func createChat(agent: DemoAgent) -> String {
        if !isDemo, let chat = mainConversation(for: agent.id) { return chat.id }
        let id = UUID().uuidString.lowercased()
        if !isDemo, onCreate?(agent.id, id) != true { return "" }
        let chat = DemoConversation(
            id: id,
            agent: agent,
            title: "New conversation",
            messages: []
        )
        conversations.insert(chat, at: 0)
        return chat.id
    }

    @discardableResult
    func send(_ text: String, attachments: [DemoAttachment] = [], to id: String, thinking: ChatThinking? = nil) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return false }
        let targetID = conversation(id: id)?.id ?? id
        guard let index = conversations.firstIndex(where: { $0.id == targetID && !$0.isArchived }) else { return false }

        if !isDemo, onSend?(text, attachments, targetID, thinking) != true { return false }
        var chat = conversations.remove(at: index)
        if chat.messages.isEmpty { chat.title = String((text.isEmpty ? attachments[0].name : text).prefix(48)) }
        var blocks: [DemoMessage.Block] = text.isEmpty ? [] : [.text(text)]
        blocks += attachments.map { .file($0) }
        chat.messages.append(DemoMessage(role: .user, blocks: blocks))
        if isDemo { chat.messages.append(DemoMessage(role: .assistant, blocks: [
            .text("This is a demo reply from \(chat.agent.name). Your message was added locally. No AI is connected and no work was performed."),
            .text("You can explore these example chats, or use the To-do List to keep track of your own work.")
        ])) }
        chat.status = isDemo ? .ready : .waiting
        chat.updatedAt = .now
        conversations.insert(chat, at: 0)
        return true
    }

    func archive(_ id: String) {
        if !isDemo, onArchive?(id) != true { return }
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].isArchived = true
    }

    func receive(_ snapshot: SyncSnapshot, pending: [PendingChange]) {
        agents = snapshot.agents.map { DemoAgent(id: $0.id, name: $0.name, colorHex: $0.color, description: $0.instructions) }
        conversations = snapshot.threads.compactMap { thread in
            guard let agent = agents.first(where: { $0.id == thread.agentId }) else { return nil }
            return DemoConversation(id: thread.id, agent: agent, title: thread.title,
                messages: thread.messages.filter { $0.role != "system" }.map { DemoMessage(id: $0.id, role: $0.role == "user" ? .user : .assistant, blocks: [.text($0.content)], createdAt: syncDate($0.createdAt), questionAnswer: $0.questionAnswer) },
                status: thread.status == "running" ? .running : thread.status == "failed" ? .failed : thread.status == "blocked" ? .blocked : .ready,
                isArchived: thread.archivedAt != nil,
                createdAt: syncDate(thread.createdAt ?? thread.messages.map(\.createdAt).min() ?? thread.updatedAt),
                updatedAt: syncDate(thread.updatedAt), instanceNumber: thread.instanceNumber, activity: thread.activity,
                viewedAt: thread.viewedAt.map(syncDate), sidebarExpiresAt: thread.sidebarExpiresAt.map(syncDate))
        }
        for change in pending where change.error == nil {
            let action = change.command.action
            guard let id = action["threadId"]?.string else { continue }
            if action["type"] == "chat.create", !conversations.contains(where: { $0.id == id }), let agent = agents.first(where: { $0.id == action["agentId"]?.string }) {
                conversations.append(DemoConversation(id: id, agent: agent, title: "New conversation", messages: []))
            }
            if action["type"] == "chat.send", let index = conversations.firstIndex(where: { $0.id == id }) {
                conversations[index].messages.append(DemoMessage(id: change.id, role: .user, blocks: [.text(action["message"]?.string ?? "Attached files")]))
                conversations[index].status = .waiting
            }
            if action["type"] == "chat.viewed", let index = conversations.firstIndex(where: { $0.id == id }),
               let viewedAt = action["viewedAt"]?.string {
                let viewed = syncDate(viewedAt)
                let firstViewed = min(conversations[index].viewedAt ?? viewed, viewed)
                conversations[index].viewedAt = firstViewed
                if let thread = snapshot.threads.first(where: { $0.id == id }),
                   snapshot.tasks.contains(where: { $0.id == thread.taskId && $0.status == "done" }) {
                    conversations[index].sidebarExpiresAt = firstViewed.addingTimeInterval(24 * 60 * 60)
                }
            }
            if action["type"] == "chat.archive", let index = conversations.firstIndex(where: { $0.id == id }) { conversations[index].isArchived = true }
        }
        conversations.sort { $0.updatedAt > $1.updatedAt }
        refreshVisibility()
    }

    func disconnect() {
        conversations = []; agents = []; resetCount += 1
        onCreate = nil; onSend = nil; onArchive = nil; onView = nil
        openConversationID = nil; expirationTask?.cancel()
    }

    func reset() {
        for block in conversations.flatMap(\.messages).flatMap(\.blocks) {
            if case .file(let file) = block { file.removeLocalCopy() }
        }
        conversations = DemoFixtures.conversations
        resetCount += 1
    }
}

import SwiftData
import XCTest

@testable import DonyMobile

private final class CompanionURLProtocol: URLProtocol {
    static var handle: ((URLRequest) throws -> (Int, Data))?
    static var hold: ((CompanionURLProtocol) -> Bool)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if Self.hold?(self) == true { return }
        do {
            let (status, data) = try Self.handle!(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class CompanionStoreTests: XCTestCase {
    private var directory: URL!
    private var session: URLSession!
    private var snapshot: [String: Any]!
    private var receipts: [[String: Any]] = []
    private var sent: [SyncCommand] = []
    private var connection: CompanionConnection!
    private var revision = 1

    override func setUp() async throws {
        directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "companion-snapshot", withExtension: "json"))
        snapshot = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        receipts = []
        sent = []
        revision = 1
        connection = CompanionConnection(
            server: URL(string: "https://companion.test")!, token: "test-phone-token",
            deviceId: UUID().uuidString, desktopId: UUID().uuidString, desktopName: "Work Mac",
            accountId: "owner")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CompanionURLProtocol.self]
        session = URLSession(configuration: config)
        CompanionURLProtocol.handle = { [unowned self] request in
            if request.url?.lastPathComponent == "commands" {
                let data: Data
                if let body = request.httpBody {
                    data = body
                } else {
                    let stream = request.httpBodyStream!
                    stream.open()
                    defer { stream.close() }
                    var bytes = Data()
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        if count <= 0 { break }
                        bytes.append(contentsOf: buffer.prefix(count))
                    }
                    data = bytes
                }
                self.sent.append(try JSONDecoder().decode(SyncCommand.self, from: data))
                return (200, Data("{\"ok\":true}".utf8))
            }
            let response: [String: Any] = [
                "revision": self.revision, "desktopOnline": true, "snapshot": self.snapshot!,
                "receipts": self.receipts,
            ]
            return (200, try JSONSerialization.data(withJSONObject: response))
        }
    }
    override func tearDown() async throws {
        session.invalidateAndCancel()
        CompanionURLProtocol.handle = nil
        CompanionURLProtocol.hold = nil
        try FileManager.default.removeItem(at: directory)
    }
    private func makeStore() -> CompanionStore {
        let connection = connection
        return CompanionStore(
            session: session, cacheURL: directory.appending(path: "companion.json"),
            credentials: CompanionCredentials(read: { connection }, save: { _ in }, remove: {}))
    }
    func testIdlePollingAndFailureBackoff() async throws {
        snapshot["threads"] = []
        let store = makeStore()
        await store.sync()
        XCTAssertEqual(store.nextSyncDelay, .seconds(30))
        let success = CompanionURLProtocol.handle
        CompanionURLProtocol.handle = { _ in throw URLError(.cannotConnectToHost) }
        for seconds in [5, 10, 20, 40, 80, 160, 300, 300] {
            await store.sync()
            XCTAssertEqual(store.nextSyncDelay, .seconds(seconds))
        }
        CompanionURLProtocol.handle = success
        await store.sync()
        XCTAssertEqual(store.nextSyncDelay, .seconds(30))
        XCTAssertTrue(store.enqueue("task.create", ["taskId": .string(UUID().uuidString), "input": .object(["title": .string("Wake sync")])]))
        XCTAssertEqual(store.nextSyncDelay, .seconds(2))
    }

    private func makeTodos() throws -> TodoStore {
        let defaults = UserDefaults(suiteName: "CompanionUnitTests-\(UUID().uuidString)")!
        defaults.set(true, forKey: "hasSeededTodos")
        let container = try ModelContainer(
            for: TodoItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return try TodoStore(container: container, defaults: defaults)
    }
    private func attach(_ store: CompanionStore) throws -> TodoStore {
        let todos = try makeTodos()
        store.attach(todos: todos, chats: DemoChatStore(isDemo: false))
        return todos
    }

    private func prepareSuggestionsAndReview() throws {
        var tasks = try XCTUnwrap(snapshot["tasks"] as? [[String: Any]])
        tasks[0]["proactiveSuggestionPending"] = true
        tasks[0]["proactiveExecutionStatus"] = NSNull()
        tasks[1]["proactiveExecutionStatus"] = NSNull()
        snapshot["tasks"] = tasks
        snapshot["results"] = [[
            "id": "review-1", "taskId": tasks[1]["id"]!,
            "threadId": "00000000-0000-4000-8000-000000000022",
            "preview": "Proposal ready", "outcome": "review", "artifacts": [],
        ]]
    }

    func testChatThinkingTravelsWithTheQueuedMessageAndSurvivesRestart() async throws {
        let store = makeStore()
        let todos = try makeTodos()
        let chats = DemoChatStore(isDemo: false)
        store.attach(todos: todos, chats: chats)
        await store.sync()
        store.setActive(false)
        let chat = try XCTUnwrap(chats.recent.first)
        XCTAssertTrue(chats.send("Think this through", to: chat.id, thinking: .deep))
        let change = try XCTUnwrap(store.changes.first { $0.command.action["type"] == "chat.send" })
        XCTAssertEqual(change.command.action["thinking"], "deep")
        XCTAssertEqual(change.command.action["message"], "Think this through")
        let restored = makeStore()
        XCTAssertEqual(restored.changes.first { $0.id == change.id }?.command.action["thinking"], "deep")
    }

    func testArchivingTaskChatDeletesTodoAndSubtasksImmediatelyAndSurvivesRestart() async throws {
        var tasks = try XCTUnwrap(snapshot["tasks"] as? [[String: Any]])
        let taskID = try XCTUnwrap(tasks[0]["id"] as? String)
        var child = tasks[0]
        child["id"] = UUID().uuidString.lowercased()
        child["parentTaskId"] = taskID
        tasks.append(child)
        snapshot["tasks"] = tasks
        let store = makeStore()
        let todos = try makeTodos()
        let chats = DemoChatStore(isDemo: false)
        store.attach(todos: todos, chats: chats)
        await store.sync()
        let threadID = try XCTUnwrap(store.snapshot?.threads.first { $0.taskId == taskID }?.id)

        chats.archive(threadID)

        XCTAssertNil(chats.conversation(id: threadID))
        XCTAssertEqual(todos.items.count, 1)
        XCTAssertEqual(todos.items.first?.title, "Review the proposal")
        XCTAssertEqual(store.changes.count, 1)
        XCTAssertEqual(store.changes.first?.command.action["type"], "chat.archive")
        XCTAssertEqual(store.changes.first?.relatedTaskID, taskID)
        let restored = makeStore()
        let restoredTodos = try makeTodos()
        let restoredChats = DemoChatStore(isDemo: false)
        restored.attach(todos: restoredTodos, chats: restoredChats)
        XCTAssertEqual(restoredTodos.items.count, 1)
        XCTAssertNil(restoredChats.conversation(id: threadID))
    }

    func testRejectedArchiveRestoresCompletedTodoAndChat() async throws {
        var tasks = try XCTUnwrap(snapshot["tasks"] as? [[String: Any]])
        tasks[0]["status"] = "done"
        snapshot["tasks"] = tasks
        let store = makeStore()
        let todos = try makeTodos()
        let chats = DemoChatStore(isDemo: false)
        store.attach(todos: todos, chats: chats)
        await store.sync()
        let taskID = try XCTUnwrap(tasks[0]["id"] as? String)
        let threadID = try XCTUnwrap(store.snapshot?.threads.first { $0.taskId == taskID }?.id)
        chats.archive(threadID)
        XCTAssertTrue(todos.completed.isEmpty)
        let archive = try XCTUnwrap(store.changes.first)
        receipts = [["id": archive.id, "status": "conflict", "error": "Changed on desktop"]]
        await store.sync()
        XCTAssertEqual(todos.completed.count, 1)
        XCTAssertNotNil(chats.conversation(id: threadID))
        store.retry(archive.id)
        XCTAssertTrue(todos.completed.isEmpty)
        XCTAssertNil(chats.conversation(id: threadID))
    }

    func testArchivingDirectChatLeavesTodosAlone() async throws {
        let store = makeStore()
        let todos = try makeTodos()
        let chats = DemoChatStore(isDemo: false)
        store.attach(todos: todos, chats: chats)
        await store.sync()
        let threadID = try XCTUnwrap(chats.recent.first { $0.instanceNumber == nil }?.id)
        chats.archive(threadID)
        XCTAssertEqual(todos.items.count, 2)
        XCTAssertNil(store.changes.first?.relatedTaskID)
        XCTAssertNil(chats.conversation(id: threadID))
    }

    func testDismissedReviewCannotCompleteTheTask() async throws {
        try prepareSuggestionsAndReview()
        var results = try XCTUnwrap(snapshot["results"] as? [[String: Any]])
        results[0]["dismissedAt"] = "2026-09-09T17:00:00.000Z"
        snapshot["results"] = results
        let store = makeStore()
        let todos = try attach(store)
        await store.sync()
        let result = try XCTUnwrap(store.snapshot?.results.first)
        XCTAssertFalse(store.isAwaitingReview(result))
        XCTAssertFalse(store.review(result))
        XCTAssertTrue(store.changes.isEmpty)
        XCTAssertFalse(try XCTUnwrap(todos.items.first { $0.id.uuidString.lowercased() == result.taskId }).isCompleted)
    }

    func testRetryMovesFailedChatToWaitingAndQueuesTheMessage() async throws {
        var threads = try XCTUnwrap(snapshot["threads"] as? [[String: Any]])
        threads[0]["status"] = "failed"
        threads[0]["question"] = NSNull()
        snapshot["threads"] = threads
        let store = makeStore()
        let chats = DemoChatStore(isDemo: false)
        store.attach(todos: try makeTodos(), chats: chats)
        await store.sync()
        let threadID = try XCTUnwrap(threads[0]["id"] as? String)
        XCTAssertEqual(chats.conversation(id: threadID)?.status, .failed)
        XCTAssertTrue(chats.send("Please try again.", to: threadID))
        XCTAssertEqual(chats.conversation(id: threadID)?.status, .waiting)
        XCTAssertEqual(store.changes.filter { $0.command.action["type"] == "chat.send" }.count, 1)
        XCTAssertEqual(store.changes.first?.command.action["message"]?.string, "Please try again.")
    }

    func testConnectorRequestsUsePairedCredentialsAndNeverEnterOfflineQueue() async throws {
        let store = makeStore()
        CompanionURLProtocol.handle = { request in
            XCTAssertEqual(request.url?.path, "/v1/companion/connectors")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-phone-token")
            return (200, Data("{\"enabled\":true,\"disabledReason\":null,\"toolkits\":[]}".utf8))
        }
        let result: MobileConnectorsStatus = try await store.connectorRequest(["action": "list"])
        XCTAssertTrue(result.enabled)
        XCTAssertTrue(store.changes.isEmpty)
        CompanionURLProtocol.handle = { _ in throw URLError(.notConnectedToInternet) }
        do {
            let _: ConnectorAuthorization = try await store.connectorRequest(["action": "connect", "toolkit": "gmail"])
            XCTFail("Offline authorization must fail instead of queueing")
        } catch { XCTAssertTrue(store.changes.isEmpty) }
    }

    func testConnectorRequestsExplainAnOlderDesktopAndRejectUnpairedAccess() async throws {
        let store = makeStore()
        CompanionURLProtocol.handle = { _ in (404, Data("{}".utf8)) }
        do {
            let _: MobileConnectorsStatus = try await store.connectorRequest(["action": "list"])
            XCTFail("An older desktop should request an update")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Update Dony")) }
        let unpaired = CompanionStore(demo: true)
        do {
            let _: MobileConnectorsStatus = try await unpaired.connectorRequest(["action": "list"])
            XCTFail("Unpaired access should fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Sign in to Dony")) }
    }

    func testActionsStayImmediateDuringASuspendedDesktopRequestAndSurviveRestart() async throws {
        try prepareSuggestionsAndReview()
        let store = makeStore()
        let todos = try makeTodos()
        let chats = DemoChatStore(isDemo: false)
        store.attach(todos: todos, chats: chats)
        await store.sync()
        let suggested = try XCTUnwrap(store.snapshot?.tasks.first)
        let result = try XCTUnwrap(store.snapshot?.results.first)
        let reviewed = try XCTUnwrap(todos.items.first { $0.id.uuidString.lowercased() == result.taskId })
        let chat = try XCTUnwrap(chats.recent.first { $0.instanceNumber == nil })
        let requested = expectation(description: "Desktop request is in flight")
        var heldRequest: CompanionURLProtocol?
        CompanionURLProtocol.hold = { request in
            heldRequest = request
            requested.fulfill()
            return true
        }
        let sync = Task { await store.sync() }
        await fulfillment(of: [requested], timeout: 2)

        let started = Date.now
        store.suggestion(suggested, action: "accept")
        store.suggestion(suggested, action: "accept")
        XCTAssertNotNil(store.pendingSuggestion(suggested.id))
        XCTAssertTrue(store.review(result))
        XCTAssertFalse(store.review(result))
        XCTAssertTrue(reviewed.isCompleted)
        XCTAssertFalse(store.isAwaitingReview(result))
        todos.rename(reviewed, to: "Approved proposal")
        XCTAssertTrue(chats.send("Send after reconnecting", to: chat.id))
        XCTAssertEqual(chats.conversation(id: chat.id)?.status, .waiting)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertLessThan(Date.now.timeIntervalSince(started), 0.5)

        let restored = makeStore()
        let restoredTodos = try makeTodos()
        let restoredChats = DemoChatStore(isDemo: false)
        restored.attach(todos: restoredTodos, chats: restoredChats)
        XCTAssertNotNil(restored.pendingSuggestion(suggested.id))
        XCTAssertTrue(restoredTodos.completed.contains { $0.title == "Approved proposal" })
        XCTAssertFalse(restored.isAwaitingReview(result))
        XCTAssertEqual(restoredChats.conversation(id: chat.id)?.messages.last?.preview, "Send after reconnecting")
        XCTAssertEqual(restoredChats.conversation(id: chat.id)?.status, .waiting)
        XCTAssertEqual(restored.changes.count, 4)

        CompanionURLProtocol.hold = nil
        heldRequest?.startLoading()
        await sync.value
        // The old desktop snapshot must not undo these optimistic actions.
        XCTAssertTrue(reviewed.isCompleted)
        XCTAssertEqual(reviewed.title, "Approved proposal")
        XCTAssertFalse(store.isAwaitingReview(result))
        XCTAssertNotNil(store.pendingSuggestion(suggested.id))
    }

    func testRejectedSuggestionAndReviewRestoreDesktopStateAndCanBeRetried() async throws {
        try prepareSuggestionsAndReview()
        let store = makeStore()
        let todos = try attach(store)
        await store.sync()
        let task = try XCTUnwrap(store.snapshot?.tasks.first)
        let result = try XCTUnwrap(store.snapshot?.results.first)
        store.suggestion(task, action: "accept")
        XCTAssertTrue(store.review(result))
        receipts = store.changes.map { ["id": $0.id, "status": "conflict", "error": "Changed on desktop"] }
        await store.sync()
        XCTAssertNil(store.pendingSuggestion(task.id))
        XCTAssertTrue(store.isAwaitingReview(result))
        XCTAssertFalse(todos.items.first { $0.id.uuidString.lowercased() == result.taskId }!.isCompleted)
        XCTAssertEqual(store.failedChanges.count, 2)
        let restored = makeStore()
        let restoredTodos = try attach(restored)
        XCTAssertEqual(restored.failedChanges.count, 2)
        for change in restored.failedChanges { restored.retry(change.id) }
        XCTAssertNotNil(restored.pendingSuggestion(task.id))
        XCTAssertFalse(restored.isAwaitingReview(result))
        XCTAssertTrue(restoredTodos.completed.contains { $0.id.uuidString.lowercased() == result.taskId })
    }

    func testApprovalThenReopenKeepsOrderAndUsesAcknowledgedTaskVersion() async throws {
        try prepareSuggestionsAndReview()
        let store = makeStore()
        let todos = try attach(store)
        await store.sync()
        let result = try XCTUnwrap(store.snapshot?.results.first)
        let item = try XCTUnwrap(todos.items.first { $0.id.uuidString.lowercased() == result.taskId })
        XCTAssertTrue(store.review(result))
        let approval = try XCTUnwrap(store.changes.first)
        todos.toggle(item)
        XCTAssertFalse(item.isCompleted)
        XCTAssertEqual(store.changes.last?.dependsOn, approval.id)
        await store.sync()
        await store.sync()
        XCTAssertEqual(sent.count, 1)
        var tasks = try XCTUnwrap(snapshot["tasks"] as? [[String: Any]])
        let index = try XCTUnwrap(tasks.firstIndex { $0["id"] as? String == result.taskId })
        let before = try XCTUnwrap(tasks[index]["updatedAt"] as? String)
        let after = "2026-09-08T12:00:00.000Z"
        tasks[index]["status"] = "done"
        tasks[index]["updatedAt"] = after
        snapshot["tasks"] = tasks
        receipts = [["id": approval.id, "status": "completed", "taskVersions": [result.taskId: ["before": before, "after": after]]]]
        await store.sync()
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent.last?.action["expectedUpdatedAt"], .string(after))
        XCTAssertFalse(item.isCompleted)
    }

    func testLocalEditsDoNotRewriteTheSnapshotAndUnchangedPollsDoNotRebuildChats() async throws {
        let store = makeStore()
        let todos = try makeTodos()
        let chats = DemoChatStore(isDemo: false)
        store.attach(todos: todos, chats: chats)
        await store.sync()
        let url = directory.appending(path: "companion.json")
        let original = try Data(contentsOf: url)
        let task = try XCTUnwrap(todos.items.first)
        todos.rename(task, to: "Saved immediately")
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(try attach(makeStore()).items.first { $0.id == task.id }?.title, "Saved immediately")

        let chat = try XCTUnwrap(chats.recent.first)
        XCTAssertTrue(chats.send("Keep this message identity", to: chat.id))
        let messageID = chats.conversation(id: chat.id)?.messages.last?.id
        let unchanged = try JSONSerialization.data(withJSONObject: ["revision": revision, "desktopOnline": true, "receipts": []])
        CompanionURLProtocol.handle = { request in
            (200, request.url?.lastPathComponent == "state" ? unchanged : Data("{\"ok\":true}".utf8))
        }
        await store.sync()
        XCTAssertEqual(chats.conversation(id: chat.id)?.messages.last?.id, messageID)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testConfirmedChangesDoNotReturnFromAnOlderOutboxOnRestart() async throws {
        let store = makeStore()
        _ = try attach(store)
        await store.sync()
        store.setMode("proactive")
        await store.sync()
        let command = try XCTUnwrap(sent.first)
        snapshot["mode"] = "proactive"
        receipts = [["id": command.id, "status": "completed"]]
        await store.sync()
        let restored = makeStore()
        _ = try attach(restored)
        XCTAssertTrue(restored.changes.isEmpty)
        XCTAssertEqual(restored.mode, "proactive")
    }

    func testInboxMatchesDesktopQuestionsAndCountsUnansweredItems() async throws {
        var tasks = try XCTUnwrap(snapshot["tasks"] as? [[String: Any]])
        let threads = try XCTUnwrap(snapshot["threads"] as? [[String: Any]])
        var plannerQuestion = try XCTUnwrap(threads[2]["question"] as? [String: Any])
        plannerQuestion["id"] = UUID().uuidString.lowercased()
        tasks[0]["proactiveQuestion"] = plannerQuestion
        snapshot["tasks"] = tasks
        let store = makeStore()
        await store.sync()
        XCTAssertEqual(store.inboxQuestions.count, 1, "Suggestions mode keeps planner questions with the task")
        store.setMode("proactive")
        XCTAssertEqual(store.inboxQuestions.count, 2)
        XCTAssertEqual(store.inboxQuestions.last?.taskId, tasks[0]["id"] as? String)
        XCTAssertEqual(store.inboxQuestions.last?.agent.name, "Dony Planner")
        let question = try XCTUnwrap(store.inboxQuestions.first)
        XCTAssertNil(question.taskId, "Agent answers use question ID, not the planner task command")
        XCTAssertTrue(store.answer(question.question, taskId: question.taskId, response: .object(["action": "decline"])))
        XCTAssertEqual(store.inboxQuestions.count, 2, "Keep queued answers reachable until acknowledged")
        XCTAssertEqual(store.inboxPendingCount, 1)
        let answer = try XCTUnwrap(store.answerChange(question.id))
        receipts = [["id": answer.id, "status": "failed", "error": "Try again"]]
        await store.sync()
        XCTAssertEqual(store.inboxPendingCount, 2)
    }

    func testInboxDismissalsSurviveRestartAndFailedDismissalsReturn() async throws {
        let resultID = UUID().uuidString.lowercased()
        snapshot["results"] = [[
            "id": resultID, "taskId": "task", "threadId": "thread", "preview": "The brief is ready.",
            "outcome": "completed", "artifacts": [], "taskTitle": "Launch brief",
            "agentName": "Writer", "agentColor": "#2080FB", "completedAt": "2026-09-08T12:00:00.000Z",
        ], [
            "id": "review-result", "taskId": "review-task", "threadId": "review-thread",
            "preview": "Review this", "outcome": "review", "artifacts": [],
        ]]
        let store = makeStore()
        await store.sync()
        XCTAssertEqual(store.inboxResults.count, 1)
        let result = try XCTUnwrap(store.inboxResults.first)
        XCTAssertEqual(result.taskTitle, "Launch brief")
        XCTAssertEqual(result.agentName, "Writer")
        store.dismissInboxResult(result)
        store.dismissInboxResult(result)
        XCTAssertTrue(store.inboxResults.isEmpty)
        XCTAssertEqual(store.changes.count, 1)
        let restored = makeStore()
        XCTAssertTrue(restored.inboxResults.isEmpty)
        let change = try XCTUnwrap(restored.changes.first)
        XCTAssertEqual(change.command.action["type"], "result.dismiss")
        XCTAssertEqual(change.command.action["resultId"], .string(resultID))
        receipts = [["id": change.id, "status": "failed", "error": "Desktop could not dismiss this result"]]
        await restored.sync()
        XCTAssertEqual(restored.inboxResults.map(\.id), [resultID])
        restored.dismissInboxResult(result)
        XCTAssertTrue(restored.inboxResults.isEmpty)
        XCTAssertEqual(restored.changes.count, 1)
        XCTAssertNotEqual(restored.changes.first?.id, change.id)
        XCTAssertNil(restored.changes.first?.dependsOn)
    }

    func testClearInboxPreservesReviewAndPreviouslyDismissedResults() async throws {
        snapshot["results"] = ["completed", "review", "failed"].map { outcome in
            ["id": outcome, "taskId": "task", "threadId": "thread", "preview": outcome,
             "outcome": outcome, "artifacts": []] as [String: Any]
        } + [["id": "old", "taskId": "task", "threadId": "thread", "preview": "old", "artifacts": [],
              "dismissedAt": "2026-09-07T12:00:00.000Z"]]
        let store = makeStore()
        await store.sync()
        store.clearInboxResults()
        XCTAssertTrue(store.inboxResults.isEmpty)
        XCTAssertEqual(store.changes.compactMap { $0.command.action["resultId"]?.string }, ["completed", "failed"])
        XCTAssertEqual(store.snapshot?.results.count, 4, "Dismissing does not delete tasks or results locally")
    }

    func testArtifactOpenFetchesPromptlyAndIgnoresDuplicateTaps() async throws {
        let store = makeStore()
        defer { store.setActive(false) }
        let result = SyncResult(
            id: UUID().uuidString, taskId: UUID().uuidString, threadId: UUID().uuidString,
            preview: "A test output", outcome: "review",
            artifacts: [.init(name: "brief.txt", type: "file", url: nil)])
        let started = Date.now
        store.openArtifact(result, index: 0)
        store.openArtifact(result, index: 0)
        XCTAssertTrue(store.isOpeningArtifact(result, index: 0))
        XCTAssertEqual(store.changes.count, 1)

        let deadline = Date.now.addingTimeInterval(2)
        while sent.isEmpty && Date.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let command = try XCTUnwrap(sent.first)
        XCTAssertEqual(command.action["type"], "artifact.read")
        XCTAssertEqual(command.action["resultId"], .string(result.id))
        XCTAssertEqual(command.action["index"], .number(0))
        receipts = [[
            "id": command.id, "status": "completed",
            "file": ["name": "brief.txt", "mimeType": "text/plain", "base64": Data("Test brief".utf8).base64EncodedString()],
        ]]
        while store.previewURL == nil && Date.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let preview = try XCTUnwrap(store.previewURL)
        defer { try? FileManager.default.removeItem(at: preview.deletingLastPathComponent()) }
        XCTAssertEqual(try String(contentsOf: preview, encoding: .utf8), "Test brief")
        XCTAssertFalse(store.isOpeningArtifact(result, index: 0))
        XCTAssertEqual(sent.count, 1)
        print("Artifact open including receipt and local preview: \(Date.now.timeIntervalSince(started))s")
    }

    func testArtifactOpenKeepsEarlierCommandsInOrder() async throws {
        let store = makeStore()
        defer { store.setActive(false) }
        XCTAssertTrue(store.enqueue("mode.set", ["mode": "suggest", "expectedMode": "off"]))
        let result = SyncResult(
            id: UUID().uuidString, taskId: UUID().uuidString, threadId: UUID().uuidString,
            preview: "A test output", outcome: "review", artifacts: [])
        store.openArtifact(result, index: 0)
        let deadline = Date.now.addingTimeInterval(2)
        while sent.isEmpty && Date.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let first = try XCTUnwrap(sent.first)
        XCTAssertEqual(first.action["type"], "mode.set")
        receipts = [["id": first.id, "status": "completed"]]
        while !sent.contains(where: { $0.action["type"] == "artifact.read" }) && Date.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(sent.last?.action["type"], "artifact.read")
    }

    func testEmployeesCombineDirectSessionsWithoutLosingHistoryOrAddingAnotherSession() throws {
        var threads = try XCTUnwrap(snapshot["threads"] as? [[String: Any]])
        let currentID = try XCTUnwrap(threads[0]["id"] as? String)
        var older = threads[0]
        older["id"] = "00000000-0000-4000-8000-000000000023"
        older["updatedAt"] = "2026-09-06T12:00:00.000Z"
        var oldMessage = try XCTUnwrap((older["messages"] as? [[String: Any]])?.first)
        oldMessage["id"] = "00000000-0000-4000-8000-000000000033"
        oldMessage["createdAt"] = "2026-09-06T12:00:00.000Z"
        oldMessage["content"] = "Earlier project context"
        older["messages"] = [oldMessage]
        threads.append(older)
        snapshot["threads"] = threads
        let decoded = try JSONDecoder().decode(SyncSnapshot.self, from: JSONSerialization.data(withJSONObject: snapshot!))
        let chats = DemoChatStore(isDemo: false)
        chats.receive(decoded, pending: [])
        XCTAssertEqual(chats.conversations.count, 4)
        XCTAssertEqual(chats.recent.count, 3)
        let main = try XCTUnwrap(chats.recent.first { $0.instanceNumber == nil })
        XCTAssertEqual(main.id, currentID)
        XCTAssertEqual(main.title, "Chat")
        XCTAssertEqual(main.messages.count, 3)
        XCTAssertEqual(main.messages.first?.preview, "Earlier project context")
        XCTAssertEqual(chats.recent.compactMap(\.instanceNumber).sorted(), [1, 2])
        XCTAssertEqual(chats.conversation(id: older["id"] as! String)?.id, currentID)
        chats.onCreate = { _, _ in XCTFail("Should reuse the employee's main conversation"); return false }
        XCTAssertEqual(chats.createChat(agent: main.agent), currentID)
        var sentTo: String?
        chats.onSend = { _, _, id, _ in sentTo = id; return true }
        XCTAssertTrue(chats.send("Continue the discussion", attachments: [], to: older["id"] as! String))
        XCTAssertEqual(sentTo, currentID)
        XCTAssertEqual(chats.recent.filter { $0.instanceNumber == nil }.count, 1)
        XCTAssertEqual(chats.conversation(id: currentID)?.messages.last?.preview, "Continue the discussion")
    }

    func testMainEmployeeRowKeepsTheRunningSessionReachable() throws {
        var threads = try XCTUnwrap(snapshot["threads"] as? [[String: Any]])
        let runningID = try XCTUnwrap(threads[0]["id"] as? String)
        threads[0]["status"] = "running"
        threads[0]["activity"] = "Reading the document"
        var newer = threads[0]
        newer["id"] = "00000000-0000-4000-8000-000000000023"
        newer["status"] = "ready"
        newer["updatedAt"] = "2026-09-08T12:00:00.000Z"
        newer["messages"] = []
        threads.append(newer)
        snapshot["threads"] = threads
        let decoded = try JSONDecoder().decode(SyncSnapshot.self, from: JSONSerialization.data(withJSONObject: snapshot!))
        let chats = DemoChatStore(isDemo: false)
        chats.receive(decoded, pending: [])
        let main = try XCTUnwrap(chats.recent.first { $0.instanceNumber == nil })
        XCTAssertEqual(main.id, runningID)
        XCTAssertEqual(main.status, .running)
        XCTAssertEqual(main.preview, "Reading the document")
        XCTAssertEqual(chats.conversation(id: newer["id"] as! String)?.id, runningID)
    }

    func testTaskNumbersFollowVisibleChatsAfterExpiry() throws {
        var threads = try XCTUnwrap(snapshot["threads"] as? [[String: Any]])
        let remainingID = try XCTUnwrap(threads[1]["id"] as? String)
        let expiry = Date.now.addingTimeInterval(60)
        threads[2]["sidebarExpiresAt"] = expiry.ISO8601Format()
        snapshot["threads"] = threads
        let decoded = try JSONDecoder().decode(SyncSnapshot.self, from: JSONSerialization.data(withJSONObject: snapshot!))
        let chats = DemoChatStore(isDemo: false)
        chats.receive(decoded, pending: [])
        XCTAssertEqual(chats.recent.compactMap(\.instanceNumber).sorted(), [1, 2])
        chats.refreshVisibility(now: expiry.addingTimeInterval(1))
        XCTAssertEqual(chats.recent.compactMap(\.instanceNumber), [1])
        XCTAssertEqual(chats.conversation(id: remainingID)?.instanceNumber, 1)
        XCTAssertEqual(chats.recent.filter { $0.instanceNumber == nil }.count, 1)
    }

    func testCompletedChatExpiryKeepsUnviewedChatsAndTheOpenConversation() throws {
        var threads = try XCTUnwrap(snapshot["threads"] as? [[String: Any]])
        let id = try XCTUnwrap(threads[1]["id"] as? String)
        let now = Date.now
        let expiry = now.addingTimeInterval(60)
        threads[1]["sidebarExpiresAt"] = expiry.ISO8601Format()
        snapshot["threads"] = threads
        let data = try JSONSerialization.data(withJSONObject: snapshot!)
        let decoded = try JSONDecoder().decode(SyncSnapshot.self, from: data)
        let chats = DemoChatStore(isDemo: false)
        chats.receive(decoded, pending: [])
        chats.refreshVisibility(now: expiry.addingTimeInterval(-1))
        XCTAssertTrue(chats.recent.contains { $0.id == id })
        chats.openConversationID = id
        chats.refreshVisibility(now: expiry.addingTimeInterval(1))
        XCTAssertTrue(chats.recent.contains { $0.id == id })
        chats.openConversationID = nil
        XCTAssertFalse(chats.recent.contains { $0.id == id })
        XCTAssertNotNil(chats.conversation(id: id))
        XCTAssertEqual(chats.recent.count, 2)
        let restarted = DemoChatStore(isDemo: false)
        restarted.receive(decoded, pending: [])
        restarted.refreshVisibility(now: expiry.addingTimeInterval(1))
        XCTAssertFalse(restarted.recent.contains { $0.id == id })
        XCTAssertEqual(restarted.recent.count, 2)
    }

    func testViewingTaskChatQueuesSharedTimeAndDoesNotResetIt() async throws {
        var tasks = try XCTUnwrap(snapshot["tasks"] as? [[String: Any]])
        tasks[0]["status"] = "done"
        snapshot["tasks"] = tasks
        let store = makeStore()
        let chats = DemoChatStore(isDemo: false)
        store.attach(todos: try makeTodos(), chats: chats)
        await store.sync()
        let id = "00000000-0000-4000-8000-000000000021"
        chats.view(id)
        let firstView = try XCTUnwrap(chats.conversation(id: id)?.viewedAt)
        XCTAssertEqual(chats.conversation(id: id)?.sidebarExpiresAt, firstView.addingTimeInterval(24 * 60 * 60))
        chats.view(id)
        XCTAssertEqual(chats.conversation(id: id)?.viewedAt, firstView)
        XCTAssertEqual(store.changes.filter { $0.command.action["type"] == "chat.viewed" }.count, 1)
    }

    func testWireContractAndRealAgentInstances() async throws {
        let store = makeStore()
        let todos = try makeTodos()
        let chats = DemoChatStore(isDemo: false)
        store.attach(todos: todos, chats: chats)
        await store.sync()
        XCTAssertEqual(todos.items.count, 2)
        XCTAssertEqual(store.mode, "suggest")
        XCTAssertEqual(chats.agents.map(\.name), ["General Assistant"])
        XCTAssertEqual(chats.recent.count, 3)
        XCTAssertEqual(chats.recent.compactMap(\.instanceNumber).sorted(), [1, 2])
        XCTAssertTrue(chats.recent.contains { $0.status == .running })
        XCTAssertTrue(chats.recent.contains { $0.status == .blocked })
        XCTAssertEqual(store.snapshot?.threads.last?.question?.questions.first?.responseKind, "resource")
    }

    func testTaskChatRemainsAvailableAfterAgentWorkStopsAndTaskCompletes() async throws {
        let store = makeStore()
        let taskID = UUID(uuidString: "00000000-0000-4000-8000-000000000010")!
        var threads = try XCTUnwrap(snapshot["threads"] as? [[String: Any]])
        var tasks = try XCTUnwrap(snapshot["tasks"] as? [[String: Any]])
        tasks[0]["status"] = "done"
        tasks[0]["completedAt"] = "2026-09-07T13:00:00.000Z"
        snapshot["tasks"] = tasks
        for status in ["ready", "blocked", "failed"] {
            threads[1]["status"] = status
            threads[1]["runId"] = NSNull()
            snapshot["threads"] = threads
            await store.sync()
            XCTAssertEqual(store.taskThread(for: taskID)?.id, threads[1]["id"] as? String)
        }
    }

    func testTaskChatUsesLatestUnarchivedThreadForThatTask() async throws {
        let store = makeStore()
        let taskID = UUID(uuidString: "00000000-0000-4000-8000-000000000010")!
        var threads = try XCTUnwrap(snapshot["threads"] as? [[String: Any]])
        var latest = threads[1]
        latest["id"] = UUID().uuidString.lowercased()
        latest["updatedAt"] = "2026-09-07T13:00:00.000Z"
        threads.insert(latest, at: 0)
        snapshot["threads"] = threads
        await store.sync()
        XCTAssertEqual(store.taskThread(for: taskID)?.id, latest["id"] as? String)
        XCTAssertNil(store.taskThread(for: UUID()))

        threads[0]["archivedAt"] = "2026-09-07T14:00:00.000Z"
        snapshot["threads"] = threads
        await store.sync()
        XCTAssertEqual(store.taskThread(for: taskID)?.id, "00000000-0000-4000-8000-000000000021")

        threads[2]["archivedAt"] = "2026-09-07T14:00:00.000Z"
        snapshot["threads"] = threads
        await store.sync()
        XCTAssertNil(store.taskThread(for: taskID))
    }

    func testQuestionTaskRoutesToItsExactThreadAndIgnoresArchivedQuestions() async throws {
        let store = makeStore()
        await store.sync()
        let taskID = UUID(uuidString: "00000000-0000-4000-8000-000000000011")!
        XCTAssertEqual(store.questionThread(for: taskID)?.id, "00000000-0000-4000-8000-000000000022")
        XCTAssertNil(store.questionThread(for: UUID(uuidString: "00000000-0000-4000-8000-000000000010")!))
        var threads = try XCTUnwrap(snapshot["threads"] as? [[String: Any]])
        threads[2]["archivedAt"] = Date.now.ISO8601Format()
        snapshot["threads"] = threads
        await store.sync()
        XCTAssertNil(store.questionThread(for: taskID))
    }

    func testAnsweredCardsSurviveSyncAndRestartAndRemainSearchable() async throws {
        var threads = try XCTUnwrap(snapshot["threads"] as? [[String: Any]])
        threads[2]["question"] = NSNull()
        threads[2]["status"] = "ready"
        threads[2]["messages"] = [[
            "id": "answered-message", "role": "user", "status": "complete", "content": "Latest proposal",
            "createdAt": "2026-09-08T12:00:00.000Z", "questionAnswer": [
                "id": "answered-question", "header": "Proposal review", "answers": [
                    ["question": "Which proposal should I review?", "answer": "Latest proposal"]
                ]
            ]
        ]]
        snapshot["threads"] = threads
        let store = makeStore()
        let chats = DemoChatStore(isDemo: false)
        store.attach(todos: try makeTodos(), chats: chats)
        await store.sync()
        let threadID = "00000000-0000-4000-8000-000000000022"
        XCTAssertEqual(chats.conversation(id: threadID)?.messages.count, 1)
        XCTAssertEqual(chats.conversation(id: threadID)?.messages.first?.questionAnswer?.answers.first?.answer, "Latest proposal")
        let restored = makeStore()
        let restoredChats = DemoChatStore(isDemo: false)
        restored.attach(todos: try makeTodos(), chats: restoredChats)
        XCTAssertEqual(restoredChats.conversation(id: threadID)?.messages.first?.questionAnswer?.id, "answered-question")
        XCTAssertTrue(restoredChats.conversation(id: threadID)?.messages.first?.searchableText.contains("Which proposal") == true)
    }

    func testStopTargetsTheRunningAgentAndPreventsDuplicateStops() async throws {
        let store = makeStore()
        await store.sync()
        let running = try XCTUnwrap(store.snapshot?.threads.first { $0.status == "running" })
        store.stop(running)
        store.stop(running)
        XCTAssertTrue(store.isStopping(running))
        XCTAssertEqual(store.changes.count, 1)
        XCTAssertEqual(store.changes.first?.command.action["runId"], running.runId.map(SyncValue.string))
        let ready = try XCTUnwrap(store.snapshot?.threads.first { $0.status == "ready" })
        store.stop(ready)
        XCTAssertEqual(store.changes.count, 1)
    }

    func testQueuedQuestionAnswersSurviveReopeningWithoutDuplicateSubmission() async throws {
        let store = makeStore()
        await store.sync()
        let question = try XCTUnwrap(store.snapshot?.threads.last?.question)
        let response: SyncValue = .object([
            "action": "accept", "answers": .array([
                .object(["type": "option", "questionId": "proposal", "selectedOptionId": "latest"])
            ]), "files": .array([])
        ])
        XCTAssertTrue(store.answer(question, taskId: nil, response: response))
        let restored = makeStore()
        XCTAssertNotNil(restored.answerChange(question.id))
        XCTAssertFalse(restored.answer(question, taskId: nil, response: response))
        XCTAssertEqual(restored.changes.count, 1)
        await restored.sync()
        XCTAssertEqual(sent.first?.action["response"], response)
        XCTAssertEqual(sent.first?.action["taskId"], .null)
        XCTAssertEqual(sent.first?.action["questionId"], .string(question.id))
    }

    func testFailedQuestionAnswerCanBeRetriedWithItsOriginalSelections() async throws {
        let store = makeStore()
        await store.sync()
        let question = try XCTUnwrap(store.snapshot?.threads.last?.question)
        let response: SyncValue = .object([
            "action": "accept", "answers": .array([
                .object(["type": "options", "questionId": "focus", "selectedOptionIds": .array(["clarity", "scope"])])
            ]), "files": .array([])
        ])
        XCTAssertTrue(store.answer(question, taskId: nil, response: response))
        await store.sync()
        let command = try XCTUnwrap(sent.first)
        receipts = [["id": command.id, "status": "failed", "error": "Try again."]]
        await store.sync()
        XCTAssertEqual(store.answerChange(question.id)?.error, "Try again.")
        store.retry(command.id)
        XCTAssertNil(store.answerChange(question.id)?.error)
        XCTAssertEqual(store.answerChange(question.id)?.command.action["response"], response)
        XCTAssertNotEqual(store.answerChange(question.id)?.id, command.id)
    }

    func testOutboxRestoresCreatesEditsAndDeletionWithoutResurrectingTasks() async throws {
        let store = makeStore()
        let todos = try attach(store)
        await store.sync()
        let removed = todos.items[0]
        todos.delete(removed)
        todos.add("Write release notes")
        let added = try XCTUnwrap(todos.items.first { $0.title == "Write release notes" })
        todos.update(added, title: "Write final release notes", dueDate: "2026-09-12")
        let restored = makeStore()
        let restoredTodos = try attach(restored)
        XCTAssertFalse(restoredTodos.items.contains { $0.id == removed.id })
        XCTAssertEqual(restoredTodos.items.first { $0.id == added.id }?.title, "Write final release notes")
        XCTAssertEqual(restoredTodos.items.first { $0.id == added.id }?.dueDate, "2026-09-12")
        XCTAssertEqual(restored.changes.map(\.id), store.changes.map(\.id))
        await restored.sync()
        XCTAssertFalse(restoredTodos.items.contains { $0.id == removed.id })
        XCTAssertEqual(sent.count, 1)
    }

    func testDependentEditsWaitForAcknowledgementAndUseItsNewRevision() async throws {
        let store = makeStore()
        let todos = try attach(store)
        await store.sync()
        let item = todos.items[0]
        todos.rename(item, to: "Phone edit one")
        todos.rename(item, to: "Phone edit two")
        await store.sync()
        let first = try XCTUnwrap(sent.first)
        XCTAssertEqual(sent.count, 1)
        var tasks = snapshot["tasks"] as! [[String: Any]]
        let index = tasks.firstIndex { $0["id"] as? String == item.id.uuidString.lowercased() }!
        tasks[index]["title"] = "Phone edit one"
        tasks[index]["updatedAt"] = "2026-09-07T12:01:00.000Z"
        snapshot["tasks"] = tasks
        revision += 1
        receipts = [
            [
                "id": first.id, "status": "completed", "error": NSNull(),
                "taskVersions": [
                    item.id.uuidString.lowercased(): [
                        "before": first.action["expectedUpdatedAt"]!.string!,
                        "after": "2026-09-07T12:01:00.000Z",
                    ]
                ],
            ]
        ]
        await store.sync()
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent.last?.action["expectedUpdatedAt"], .string("2026-09-07T12:01:00.000Z"))
        XCTAssertEqual(todos.items.first { $0.id == item.id }?.title, "Phone edit two")
        XCTAssertEqual(store.changes.count, 1)
    }

    func testConflictsPreserveTheProposedEditUntilExplicitRetry() async throws {
        let store = makeStore()
        let todos = try attach(store)
        await store.sync()
        let item = todos.items[0]
        let original = item.title
        todos.rename(item, to: "Proposed phone edit")
        await store.sync()
        let id = try XCTUnwrap(sent.first?.id)
        receipts = [["id": id, "status": "conflict", "error": "The desktop changed this task."]]
        await store.sync()
        XCTAssertEqual(store.failedChanges.count, 1)
        XCTAssertEqual(item.title, original)
        XCTAssertEqual(
            store.failedChanges[0].command.action["patch"],
            .object(["title": "Proposed phone edit", "dueDate": "2026-09-10"]))
        store.retry(id)
        XCTAssertNotEqual(store.changes.first?.id, id)
        XCTAssertEqual(item.title, "Proposed phone edit")
    }

    func testModePickerUsesTheSharedSettingAndPersistsPendingChoice() async throws {
        let store = makeStore()
        _ = try attach(store)
        await store.sync()
        store.setMode("proactive")
        XCTAssertEqual(store.mode, "proactive")
        let restored = makeStore()
        _ = try attach(restored)
        XCTAssertEqual(restored.mode, "proactive")
        await restored.sync()
        XCTAssertEqual(sent.first?.action["type"], "mode.set")
        XCTAssertEqual(sent.first?.action["expectedMode"], "suggest")
    }

    func testAgentTagsSurviveQueuedCreationEditingAndRestart() async throws {
        let store = makeStore()
        let todos = try attach(store)
        await store.sync()
        let item = try XCTUnwrap(todos.add("Review @general-assistant", dueDate: nil, parent: nil))
        todos.rename(item, to: "Review @general-assistant with @research")

        let restored = makeStore()
        let restoredTodos = try attach(restored)
        XCTAssertEqual(restoredTodos.items.first { $0.id == item.id }?.title, "Review @general-assistant with @research")
        let create = try XCTUnwrap(restored.changes.first)
        guard case .object(let input) = create.command.action["input"] else { return XCTFail("Missing task input") }
        XCTAssertEqual(input["title"], "Review @general-assistant")
        let edit = try XCTUnwrap(restored.changes.last)
        guard case .object(let patch) = edit.command.action["patch"] else { return XCTFail("Missing task patch") }
        XCTAssertEqual(patch["title"], "Review @general-assistant with @research")
        XCTAssertEqual(edit.dependsOn, create.id)
    }

    func testReorderUsesDesktopOrderWhileShowingNewestRootTasksFirst() async throws {
        let store = makeStore()
        let todos = try attach(store)
        await store.sync()
        let before = todos.active.map(\.id)
        todos.move(from: IndexSet(integer: 0), to: 2, completed: false)
        await store.sync()
        let command = try XCTUnwrap(sent.first)
        XCTAssertEqual(
            command.action["expectedOrder"],
            .array(before.reversed().map { .string($0.uuidString.lowercased()) }))
        XCTAssertEqual(todos.active.map(\.id), Array(before.reversed()))
    }

    func testFailedDependencyDoesNotBlockUnrelatedTasksOrRunDependentEditsEarly() async throws {
        let store = makeStore()
        let todos = try attach(store)
        await store.sync()
        let item = todos.items[0]
        todos.rename(item, to: "First proposal")
        todos.rename(item, to: "Second proposal")
        todos.rename(item, to: "Third proposal")
        todos.add("Independent task")
        await store.sync()
        let first = try XCTUnwrap(sent.first)
        receipts = [["id": first.id, "status": "conflict", "error": "Desktop changed"]]
        await store.sync()
        XCTAssertEqual(store.failedChanges.count, 3)
        XCTAssertEqual(sent.last?.action["type"], "task.create")
        let dependent = store.changes[1]
        store.retry(dependent.id)
        XCTAssertEqual(store.changes[1].id, dependent.id)
        XCTAssertNotNil(store.changes[1].error)
    }

    func testAcknowledgementDoesNotRebaseOverANewerDesktopEdit() async throws {
        let store = makeStore()
        let todos = try attach(store)
        await store.sync()
        let item = todos.items[0]
        todos.rename(item, to: "Phone one")
        todos.rename(item, to: "Phone two")
        await store.sync()
        let first = try XCTUnwrap(sent.first)
        var tasks = snapshot["tasks"] as! [[String: Any]]
        let index = tasks.firstIndex { $0["id"] as? String == item.id.uuidString.lowercased() }!
        tasks[index]["updatedAt"] = "2026-09-07T12:02:00.000Z"
        tasks[index]["title"] = "A newer desktop edit"
        snapshot["tasks"] = tasks
        receipts = [
            [
                "id": first.id, "status": "completed",
                "taskVersions": [
                    item.id.uuidString.lowercased(): [
                        "before": first.action["expectedUpdatedAt"]!.string!,
                        "after": "2026-09-07T12:01:00.000Z",
                    ]
                ],
            ]
        ]
        await store.sync()
        // The second edit will conflict against 12:02, retaining the desktop edit for review.
        XCTAssertEqual(sent.last?.action["expectedUpdatedAt"], .string("2026-09-07T12:01:00.000Z"))
    }

    func testRevocationStopsFurtherEditsAndKeepsPendingData() async throws {
        let store = makeStore()
        let todos = try attach(store)
        await store.sync()
        todos.add("A queued task")
        CompanionURLProtocol.handle = { _ in (401, Data("{\"error\":\"Phone disconnected\"}".utf8)) }
        await store.sync()
        XCTAssertEqual(store.changes.count, 1)
        XCTAssertFalse(store.enqueue("mode.set", ["mode": "proactive", "expectedMode": "suggest"]))
        XCTAssertTrue(todos.items.contains { $0.title == "A queued task" })
    }
    func testSignedOutAgentModeOpensPaywall() {
        connection = nil
        let store = makeStore()
        store.setMode("suggest")
        XCTAssertTrue(store.showingPaywall)
        XCTAssertFalse(store.showingCloudSignIn)
        XCTAssertEqual(store.mode, "off")
        XCTAssertTrue(store.changes.isEmpty)
        XCTAssertFalse(store.showingPairing)
        XCTAssertNil(store.errorMessage)
    }

    func testCloudSessionRenewalKeepsPendingChangesAndRejectsAnotherAccount() async throws {
        connection = CompanionConnection(server: URL(string: "https://cloud.test")!, token: "expired-token", deviceId: "phone", desktopId: "workspace", desktopName: "Dony Cloud", accountId: "owner", transport: "cloud")
        let existing = CompanionURLProtocol.handle!
        var expired = false
        CompanionURLProtocol.handle = { request in
            if request.url?.lastPathComponent == "account" {
                return (200, Data("{\"workspaceId\":\"workspace\",\"pro\":true,\"executionTarget\":\"cloud\",\"dailyLimitUsd\":10,\"dailySpentUsd\":0,\"resetsAt\":\"2026-09-10\",\"configured\":true}".utf8))
            }
            if expired { return (401, Data("{\"error\":\"Session expired\"}".utf8)) }
            let (status, data) = try existing(request)
            var response = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            response["pro"] = true
            response["executionTarget"] = "cloud"
            return (status, try JSONSerialization.data(withJSONObject: response))
        }
        let store = makeStore()
        let todos = try attach(store)
        await store.sync()
        todos.add("Keep this change")
        let pendingID = try XCTUnwrap(store.changes.first?.id)
        expired = true
        await store.sync()
        XCTAssertTrue(store.needsCloudSignIn)
        do {
            try await store.renewCloudSession(token: "wrong-token", user: CloudAccount(id: "someone-else", name: nil, email: nil))
            XCTFail("Another account must not replace the pending workspace")
        } catch {}
        XCTAssertEqual(store.connection?.token, "expired-token")
        XCTAssertEqual(store.changes.first?.id, pendingID)
        try await store.renewCloudSession(token: "renewed-token", user: CloudAccount(id: "owner", name: nil, email: nil))
        store.setActive(false)
        XCTAssertFalse(store.needsCloudSignIn)
        XCTAssertNil(store.connectionError)
        XCTAssertEqual(store.connection?.token, "renewed-token")
        XCTAssertEqual(store.changes.first?.id, pendingID)
        XCTAssertTrue(todos.items.contains { $0.title == "Keep this change" })
        XCTAssertEqual(makeStore().changes.first?.id, pendingID)
        expired = false
        await store.sync()
        XCTAssertEqual(sent.first?.id, pendingID)
        XCTAssertEqual(sent.first?.executionTarget, "cloud")
    }

    func testCloudOfflineFailureCanRetryWithoutComputer() async throws {
        connection = CompanionConnection(server: URL(string: "https://cloud.test")!, token: "token", deviceId: "phone", desktopId: "workspace", desktopName: "Dony Cloud", accountId: "owner", transport: "cloud")
        let existing = CompanionURLProtocol.handle!
        CompanionURLProtocol.handle = { _ in throw URLError(.notConnectedToInternet) }
        let store = makeStore()
        await store.sync()
        XCTAssertEqual(store.connectionError, "You’re offline.")
        XCTAssertFalse(store.showingPairing)
        CompanionURLProtocol.handle = existing
        await store.sync()
        XCTAssertNil(store.connectionError)
        XCTAssertTrue(store.serverOnline)
    }

    func testCloudUsesMobileRoutesAndKeepsBasicWorkspaceEditableWithoutSubscription() async throws {
        connection = CompanionConnection(server: URL(string: "https://cloud.test")!, token: "test-cloud-token", deviceId: "phone", desktopId: "workspace", desktopName: "Dony Cloud", accountId: "owner", transport: "cloud")
        let existing = CompanionURLProtocol.handle!
        var pro = true
        var paths: [String] = []
        CompanionURLProtocol.handle = { request in
            paths.append(request.url!.path)
            let (status, data) = try existing(request)
            if request.url?.lastPathComponent != "state" { return (status, data) }
            var response = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            response["pro"] = pro; response["executionTarget"] = "cloud"
            return (status, try JSONSerialization.data(withJSONObject: response))
        }
        let store = makeStore()
        let todos = try attach(store)
        await store.sync()
        XCTAssertTrue(store.isCloud)
        XCTAssertEqual(store.executionTarget, "cloud")
        XCTAssertTrue(store.enqueue("mode.set", ["mode": "off", "expectedMode": .string(store.mode)]))
        await store.sync()
        XCTAssertEqual(sent.last?.executionTarget, "cloud")
        XCTAssertTrue(paths.contains("/v1/mobile/commands"))
        receipts = [["id": sent.last!.id, "status": "completed"]]
        pro = false
        await store.sync()
        XCTAssertFalse(store.proEnabled)
        XCTAssertFalse(todos.items.isEmpty)
        XCTAssertFalse(store.enqueue("chat.create", ["threadId": .string(UUID().uuidString), "agentId": "agent"]))
        XCTAssertTrue(store.showingPaywall)
        XCTAssertFalse(store.statusText.contains("Read only"))
    }

    func testDeletingCloudAccountUsesAuthenticatedMobileRouteAndSignsOut() async throws {
        connection = CompanionConnection(server: URL(string: "https://cloud.test")!, token: "delete-token", deviceId: "phone", desktopId: "workspace", desktopName: "Dony Cloud", accountId: "owner", transport: "cloud")
        var requestPath: String?
        var requestMethod: String?
        var authorization: String?
        CompanionURLProtocol.handle = { request in
            requestPath = request.url?.path
            requestMethod = request.httpMethod
            authorization = request.value(forHTTPHeaderField: "Authorization")
            return (200, Data("{\"ok\":true}".utf8))
        }
        let store = makeStore()

        try await store.deleteCloudAccount()

        XCTAssertEqual(requestPath, "/v1/mobile/account")
        XCTAssertEqual(requestMethod, "DELETE")
        XCTAssertEqual(authorization, "Bearer delete-token")
        XCTAssertFalse(store.isConnected)
        XCTAssertFalse(store.isCloud)
    }

    func testCloudStillReadsUpdatesWhilePairedComputerIsOffline() async throws {
        let desktop = PairedDesktop(connection)
        connection = CompanionConnection(server: URL(string: "https://cloud.test")!, token: "test-cloud-token", deviceId: "phone", desktopId: "workspace", desktopName: "Dony Cloud", accountId: "owner", transport: "cloud", pairedDesktop: desktop)
        let existing = CompanionURLProtocol.handle!
        CompanionURLProtocol.handle = { request in
            if request.url?.host == "companion.test" { throw URLError(.cannotConnectToHost) }
            let (status, data) = try existing(request)
            if request.url?.lastPathComponent != "state" { return (status, data) }
            var response = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            response["pro"] = true; response["executionTarget"] = "computer"
            return (status, try JSONSerialization.data(withJSONObject: response))
        }
        let store = makeStore()
        let todos = try attach(store)
        await store.sync()
        XCTAssertTrue(store.enqueue("chat.send", ["threadId": .string(UUID().uuidString), "message": "Hi", "files": .array([])]))
        var tasks = snapshot["tasks"] as! [[String: Any]]
        tasks[0]["title"] = "Updated from Cloud"
        snapshot["tasks"] = tasks; revision += 1
        await store.sync()
        XCTAssertTrue(todos.items.contains { $0.title == "Updated from Cloud" })
        XCTAssertTrue(store.serverOnline)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(store.changes.first?.command.executionTarget, "computer")
    }

    func testConnectBannerWaitsForFailedMacChecksAndDisappearsAfterReconnectOrSubscription() async throws {
        var mac = connection!
        mac.certificateFingerprint = String(repeating: "a", count: 64)
        connection = CompanionConnection(server: URL(string: "https://cloud.test")!, token: "cloud-token", deviceId: "phone",
            desktopId: "workspace", desktopName: "Cloud", accountId: "owner", transport: "cloud", pairedDesktop: PairedDesktop(mac))
        var paid = false
        var localOnline = false
        var cloudOnline = true
        var remoteRequests = 0
        let existing = CompanionURLProtocol.handle!
        CompanionURLProtocol.handle = { request in
            if request.url?.host == "companion.test" && !localOnline { throw URLError(.cannotConnectToHost) }
            if request.url?.host == "cloud.test" && !cloudOnline { throw URLError(.notConnectedToInternet) }
            if request.url?.lastPathComponent == "account" {
                return (200, try JSONSerialization.data(withJSONObject: [
                    "workspaceId": "workspace", "pro": false, "executionTarget": "computer",
                    "dailyLimitUsd": 0, "dailySpentUsd": 0, "resetsAt": "", "configured": true,
                    "billing": ["accountToken": "billing-token", "configured": true,
                        "monthlyUsedPercent": 0, "extraRemainingPercent": 0,
                        "canRunCloud": false, "canUseRemoteDesktop": paid, "limitReached": false]
                ]))
            }
            if request.url?.host == "cloud.test" && request.url?.path.hasPrefix("/v1/companion/") == true {
                remoteRequests += 1
                XCTAssertTrue(paid)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-phone-token")
            }
            let (status, data) = try existing(request)
            guard request.url?.lastPathComponent == "state" else { return (status, data) }
            var body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            body["executionTarget"] = "computer"
            return (status, try JSONSerialization.data(withJSONObject: body))
        }
        let store = makeStore()
        _ = try attach(store)
        XCTAssertFalse(store.shouldShowConnectBanner)
        await store.sync()
        XCTAssertFalse(store.shouldShowConnectBanner)
        await store.sync()
        XCTAssertTrue(store.shouldShowConnectBanner)
        store.showConnectPlan()
        XCTAssertTrue(store.showingPaywall)
        XCTAssertTrue(store.showingConnectPlan)
        store.connectBannerDismissed = true
        XCTAssertFalse(store.shouldShowConnectBanner)
        localOnline = true
        await store.sync()
        XCTAssertFalse(store.localMacUnavailable)
        XCTAssertFalse(store.connectBannerDismissed)
        localOnline = false
        await store.sync(); await store.sync()
        XCTAssertTrue(store.shouldShowConnectBanner)
        cloudOnline = false
        await store.sync()
        XCTAssertFalse(store.shouldShowConnectBanner)
        cloudOnline = true; paid = true
        try await store.refreshCloudAccount()
        await store.sync()
        XCTAssertFalse(store.shouldShowConnectBanner)
        XCTAssertTrue(store.desktopOnline)
        XCTAssertGreaterThan(remoteRequests, 0)
        XCTAssertTrue(store.enqueue("chat.send", ["threadId": .string(UUID().uuidString), "message": "Remote work", "files": .array([])]))
        await store.sync()
        XCTAssertEqual(sent.last?.action["message"], "Remote work")
        XCTAssertFalse(store.cloudStatus!.billing!.canRunCloud)
    }

    func testSignedOutAIActionsShowPaywallEveryTimeWithoutQueueing() {
        connection = nil
        let store = makeStore()
        for type in ["chat.create", "chat.send", "task.suggestion", "question.answer"] {
            store.showingPaywall = false
            XCTAssertFalse(store.enqueue(type, [:]))
            XCTAssertTrue(store.showingPaywall, type)
            XCTAssertTrue(store.changes.isEmpty)
        }
    }

    func testAgentCreationWithoutAccessDoesNotSendRequest() async {
        connection = CompanionConnection(server: URL(string: "https://cloud.test")!, token: "token", deviceId: "phone", desktopId: "workspace", desktopName: "Cloud", accountId: "owner", transport: "cloud")
        CompanionURLProtocol.handle = { _ in
            XCTFail("Blocked creation must not reach the server")
            return (200, Data())
        }
        let store = makeStore()
        do {
            try await store.saveCloudAgent(name: "Agent", instructions: "Help", color: "blue")
            XCTFail("Creation must require access")
        } catch {}
        XCTAssertTrue(store.showingPaywall)
    }

    func testCloudAccessFollowsAllowanceIncludingExtraUsage() async throws {
        connection = CompanionConnection(server: URL(string: "https://cloud.test")!, token: "token", deviceId: "phone", desktopId: "workspace", desktopName: "Cloud", accountId: "owner", transport: "cloud")
        let store = makeStore()
        for allowed in [true, false] {
            CompanionURLProtocol.handle = { _ in
                let body: [String: Any] = [
                    "workspaceId": "workspace", "pro": allowed, "executionTarget": "cloud",
                    "dailyLimitUsd": 7, "dailySpentUsd": 0, "resetsAt": "2026-10-19", "configured": true,
                    "billing": ["accountToken": "token", "configured": true,
                                "monthlyUsedPercent": 0, "extraRemainingPercent": allowed ? 100 : 0,
                                "canRunCloud": allowed, "limitReached": !allowed]
                ]
                return (200, try JSONSerialization.data(withJSONObject: body))
            }
            try await store.refreshCloudAccount()
            store.showingPaywall = false
            XCTAssertEqual(store.requireAIAccess(), allowed)
            XCTAssertEqual(store.showingPaywall, !allowed)
            XCTAssertEqual(store.showingUsagePacks, !allowed)
        }
    }

    func testLocalMacAccessDoesNotRequireSubscriptionOrLiveConnection() {
        let store = makeStore()
        XCTAssertFalse(store.desktopOnline)
        XCTAssertTrue(store.requireAIAccess())
        XCTAssertFalse(store.showingPaywall)
    }

}

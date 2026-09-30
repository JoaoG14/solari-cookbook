import Foundation
import Observation
import UIKit
import UserNotifications

@MainActor
@Observable
final class CompanionStore {
    private(set) var connection: CompanionConnection?
    private(set) var snapshot: SyncSnapshot?
    private(set) var changes: [PendingChange] = []
    private(set) var desktopOnline = false
    private(set) var serverOnline = false
    private(set) var mode = "off"
    private(set) var proEnabled = false
    private(set) var executionTarget = "cloud"
    var notificationThreadID: String?
    private(set) var cloudStatus: CloudAccountStatus?
    private let cloudSignIn = CloudSignIn()
    var errorMessage: String?
    var pairingURL: URL?
    var showingPairing = false
    var showingCloudSignIn = false
    var showingPaywall = false
    var showingUsagePacks = false
    var showingConnectPlan = false
    var connectBannerDismissed = false
    private(set) var localMacUnavailable = false
    private var macConnectionFailures = 0
    private var usingRemoteMac = false
    private var retryLocalMacAt = Date.distantPast
    var shouldShowConnectBanner: Bool {
        !demo && localMacUnavailable && !blockedByRevocation && !connectBannerDismissed
            && cloudStatus?.billing?.hasRemoteDesktop != true
            && (!isCloud || (serverOnline && executionTarget == "computer"))
    }
    func showConnectPlan() {
        showingUsagePacks = false
        showingConnectPlan = true
        if isCloud { showingPaywall = true }
        else { showingCloudSignIn = true }
    }
    var canOrganizeVoiceTasks: Bool {
        guard isCloud, let plan = cloudStatus?.billing?.plan else { return false }
        return (plan == .pro || plan == .plus) && cloudStatus?.billing?.canRunCloud == true
    }

    func requestVoiceTasks() -> Bool {
        if canOrganizeVoiceTasks { return true }
        if !isCloud { showingCloudSignIn = true }
        else {
            showingUsagePacks = cloudStatus?.billing?.limitReached == true
            showingPaywall = true
        }
        return false
    }

    func organizeTasks(_ transcript: String) async throws -> [String] {
        guard canOrganizeVoiceTasks, let connection else {
            throw CompanionFailure("Dony Pro or Max with available AI usage is required.")
        }
        struct Result: Decodable { let tasks: [String] }
        let result: Result = try await request(server: connection.server, token: connection.token,
            endpoint: "tasks/organize", body: ["transcript": .string(transcript)])
        guard self.connection?.accountId == connection.accountId else { throw CancellationError() }
        return result.tasks
    }
    private(set) var connectionError: String?
    var previewURL: URL?

    private var revision = -1
    private var loop: Task<Void, Never>?
    private var syncDelay: Task<Void, Never>?
    private var artifactSyncTask: Task<Void, Never>?
    private var syncing = false
    private var syncFailures = 0
    private var lastBillingRefresh = Date.distantPast
    private var todos: TodoStore?
    private var chats: DemoChatStore?
    private let credentials: CompanionCredentials
    private let session: URLSession
    private var localSession: URLSession?
    private var localSessionKey: String?
    private let cacheURL: URL
    private let demo: Bool
    private var generation = 0
    private var blockedByRevocation = false
    private var outboxVersion = 0
    private var needsCheckpoint = false
    private let cacheWriter = CompanionCacheWriter()
    private var outboxURL: URL { cacheURL.appendingPathExtension("outbox") }

    struct Cache: Codable {
        let desktopId: String
        let snapshot: SyncSnapshot?
        let changes: [PendingChange]
        let revision: Int
        var outboxVersion: Int? = nil
        var proEnabled: Bool? = nil
        var executionTarget: String? = nil
    }
    private struct Outbox: Codable {
        let desktopId: String
        let version: Int
        let changes: [PendingChange]
    }
    var isConnected: Bool { connection != nil }
    var isCloud: Bool { connection?.isCloud == true }
    var needsCloudSignIn: Bool { isCloud && blockedByRevocation }
    var isDemo: Bool { demo }
    var statusText: String {
        if !isConnected { return "Sign in to Dony to run cloud agents" }
        if blockedByRevocation { return "Phone disconnected · Link it again" }
        if !serverOnline {
            return connection?.isLocal == true
                ? "Waiting for your Mac on Wi-Fi · Changes saved on this iPhone"
                : "Offline · Changes saved on this iPhone"
        }
        if isCloud {
            return changes.contains(where: { $0.error == nil }) ? "Syncing changes…" : "Synced with Dony"
        }
        if !desktopOnline { return "Waiting for desktop" }
        return changes.contains(where: { $0.error == nil })
            ? "Syncing changes…" : "Connected to \(connection?.desktopName ?? "desktop")"
    }
    var failedChanges: [PendingChange] { changes.filter { $0.error != nil } }

    init(
        demo: Bool = false, session: URLSession = .shared, cacheURL: URL? = nil,
        credentials: CompanionCredentials = CompanionCredentials()
    ) {
        self.demo = demo
        self.session = session
        self.credentials = credentials
        self.cacheURL = cacheURL ?? URL.applicationSupportDirectory.appending(path: "companion.json")
        if demo { return }
        do {
            connection = try credentials.read()
            if let connection, FileManager.default.fileExists(atPath: self.cacheURL.path) {
                let cache = try JSONDecoder().decode(Cache.self, from: Data(contentsOf: self.cacheURL))
                guard cache.desktopId == connection.desktopId else {
                    throw CompanionFailure(
                        "The saved workspace belongs to another Dony connection. Review your account in Settings.")
                }
                snapshot = cache.snapshot
                changes = cache.changes
                revision = cache.revision
                outboxVersion = cache.outboxVersion ?? 0
                mode = snapshot?.mode ?? "off"
                proEnabled = cache.proEnabled ?? false
                executionTarget = cache.executionTarget ?? "cloud"
            }
            if let connection, FileManager.default.fileExists(atPath: outboxURL.path) {
                let outbox = try JSONDecoder().decode(Outbox.self, from: Data(contentsOf: outboxURL))
                if outbox.desktopId == connection.desktopId && outbox.version > outboxVersion {
                    changes = outbox.changes
                    outboxVersion = outbox.version
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func attach(todos: TodoStore, chats: DemoChatStore) {
        self.todos = todos
        self.chats = chats
        if isConnected {
            installHandlers()
            reconcile()
        }
    }

    func setActive(_ active: Bool) {
        loop?.cancel()
        syncDelay?.cancel()
        loop = nil
        if !active { artifactSyncTask?.cancel() }
        if !active || demo || !isConnected || blockedByRevocation { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.sync()
                if Task.isCancelled { return }
                let delay = self.nextSyncDelay
                let sleep = Task<Void, Never> { try? await Task.sleep(for: delay) }
                self.syncDelay = sleep
                await sleep.value
            }
        }
    }

    var nextSyncDelay: Duration {
        if syncFailures > 0 {
            return .seconds(min(300, 5 * (1 << min(syncFailures - 1, 6))))
        }
        let pending = changes.contains { $0.error == nil }
        let running = snapshot?.threads.contains { $0.status == "running" } == true
        // Local actions wake syncDelay immediately. Idle cloud/relay reads are bounded.
        return pending || running || connection?.isLocal == true ? .seconds(2) : .seconds(30)
    }

    func pair(url: URL, importIDs: Set<UUID>? = nil) async throws {
        guard !isConnected || isCloud else {
            throw CompanionFailure("Disconnect the current desktop before linking another workspace.")
        }
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            parts.scheme == "dony-solari-mobile", parts.host == "pair",
            let serverText = parts.queryItems?.first(where: { $0.name == "server" })?.value,
            let server = URL(string: serverText), server.user == nil, server.password == nil,
            let code = parts.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw CompanionFailure("Use the connection link or QR code shown in Dony’s desktop Settings.")
        }
        let transport = parts.queryItems?.first(where: { $0.name == "transport" })?.value
        let fingerprint = parts.queryItems?.first(where: { $0.name == "fingerprint" })?.value
        if transport == "local" {
            guard server.scheme == "https", CompanionLocalTrust.isLocalHost(server.host ?? ""),
                let fingerprint, fingerprint.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
            else {
                throw CompanionFailure("Generate a new Wi-Fi connection code in Dony on your Mac.")
            }
        } else if transport != nil || fingerprint != nil {
            throw CompanionFailure("This connection link is not supported. Generate a new code on your Mac.")
        }
        var allowed = server.scheme == "https"
        #if DEBUG
            allowed =
                allowed
                || (server.scheme == "http" && ["localhost", "127.0.0.1"].contains(server.host ?? ""))
        #endif
        guard allowed else { throw CompanionFailure("The desktop must use a secure HTTPS Dony backend.") }
        struct PairResponse: Decodable {
            let token: String
            let deviceId: String
            let desktopId: String
            let desktopName: String
            let accountId: String
        }
        let response: PairResponse = try await request(
            server: server, token: nil, endpoint: "pair",
            body: ["code": .string(code), "name": .string(UIDevice.current.name)],
            fingerprint: fingerprint)
        let connection = CompanionConnection(
            server: server, token: response.token, deviceId: response.deviceId, desktopId: response.desktopId,
            desktopName: response.desktopName, accountId: response.accountId,
            certificateFingerprint: fingerprint)
        if isCloud, var cloud = self.connection {
            guard cloud.accountId == connection.accountId else { throw CompanionFailure("Sign in to the same Dony account on your computer before pairing it.") }
            cloud.pairedDesktop = PairedDesktop(connection)
            resetMacConnection()
            try credentials.save(cloud)
            self.connection = cloud
            return
        }
        // Save local tasks before replacing them, and before committing the new credential.
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try todos?.backupLocalTasks(
            to: cacheURL.deletingLastPathComponent().appending(path: "todos-before-pairing.json"))
        self.connection = connection
        generation += 1
        snapshot = nil
        revision = -1
        changes = []
        blockedByRevocation = false
        for item in (todos?.items ?? []).sorted(by: {
            ($0.parentID == nil ? 0 : 1) < ($1.parentID == nil ? 0 : 1)
        }) where importIDs?.contains(item.id) ?? !item.isDemo {
            var fields: [String: SyncValue] = [
                "title": .string(item.title), "dueDate": .optional(item.dueDate),
                "notes": .optional(item.notes),
                "parentTaskId": .optional(item.parentID?.uuidString.lowercased()),
            ]
            fields["title"] = .string(item.title)
            changes.append(
                PendingChange(
                    command: SyncCommand(
                        id: UUID().uuidString.lowercased(),
                        action: [
                            "type": "task.create", "taskId": .string(item.id.uuidString.lowercased()),
                            "input": .object(fields),
                        ])))
            if item.isCompleted {
                changes.append(
                    PendingChange(
                        command: SyncCommand(
                            id: UUID().uuidString.lowercased(),
                            action: [
                                "type": "task.update", "taskId": .string(item.id.uuidString.lowercased()),
                                "expectedUpdatedAt": "", "patch": .object(["status": "done"]),
                            ]), dependsOn: changes.last?.id))
            }
        }
        do {
            try persist()
            try await checkpoint()
            try credentials.save(connection)
        } catch {
            self.connection = nil
            changes = []
            throw error
        }
        installHandlers()
        reconcile()
        setActive(true)
        await sync()
    }

    func disconnect() async throws {
        if isCloud { try await signOutCloud(); return }
        guard let connection else { return }
        guard blockedByRevocation || !changes.contains(where: { $0.error == nil }) else {
            throw CompanionFailure("Wait for your pending changes to sync before disconnecting.")
        }
        // Revocation is confirmed by the desktop or relay before dropping the credential.
        if !blockedByRevocation {
            let _: EmptyResponse = try await request(
                server: connection.server, token: connection.token, endpoint: "device", method: "DELETE")
        }
        try todos?.restoreLocalTasks(
            from: cacheURL.deletingLastPathComponent().appending(path: "todos-before-pairing.json"))
        setActive(false)
        generation += 1
        try credentials.remove()
        localSession?.invalidateAndCancel()
        localSession = nil
        localSessionKey = nil
        self.connection = nil
        snapshot = nil
        changes = []
        revision = -1
        mode = "off"
        todos?.onMutation = nil
        chats?.disconnect()
        try? FileManager.default.removeItem(at: outboxURL)
        await cacheWriter.remove(cacheURL)
        resetMacConnection()
        desktopOnline = false
        serverOnline = false
        connectionError = nil
    }

    @discardableResult
    func requireAIAccess(target: String? = nil) -> Bool {
        if demo { return true }
        let target = target ?? executionTarget
        let usesMac = isConnected && (!isCloud || (target == "computer" && connection?.pairedDesktop != nil))
        let usesCloud = isCloud && target != "computer" && cloudStatus?.billing?.canRunCloud == true
        if !blockedByRevocation && (usesMac || usesCloud) {
            return true
        }
        showingUsagePacks = cloudStatus?.billing?.limitReached == true
        showingPaywall = true
        return false
    }

    @discardableResult
    func enqueue(_ type: String, _ fields: [String: SyncValue]) -> Bool {
        let thread = snapshot?.threads.first {
            $0.id == fields["threadId"]?.string || $0.question?.id == fields["questionId"]?.string
        }
        let target = ["run.stop", "question.answer"].contains(type) ? (thread?.executionTarget ?? executionTarget) : executionTarget
        let needsAI = ["chat.create", "chat.send", "task.suggestion", "question.answer"].contains(type)
            || (type == "mode.set" && fields["mode"]?.string != "off")
        if needsAI && !requireAIAccess(target: target) { return false }
        guard isConnected, !blockedByRevocation else {
            if !isConnected || isCloud { showingCloudSignIn = true }
            else { errorMessage = "This connection is unavailable. Review your connection in Settings." }
            return false
        }
        var action = fields
        action["type"] = .string(type)
        var pending = PendingChange(command: SyncCommand(id: UUID().uuidString.lowercased(), action: action))
        if isCloud {
            let usesComputer = target == "computer" && ["chat.send", "task.suggestion", "question.answer", "run.stop"].contains(type)
            if usesComputer && connection?.pairedDesktop == nil { errorMessage = "This action is unavailable. Choose Cloud in Settings to continue."; return false }
            pending.command.executionTarget = usesComputer ? "computer" : "cloud"
        }
        if type == "task.review" {
            pending.relatedTaskID = snapshot?.results.first { $0.id == fields["resultId"]?.string }?.taskId
        }
        if type == "chat.archive" {
            pending.relatedTaskID = snapshot?.threads.first {
                $0.id == fields["threadId"]?.string && $0.origin == "task"
            }?.taskId
        }
        pending.dependsOn =
            changes.last(where: {
                if $0.target == pending.target { return true }
                if let taskID = pending.taskID, $0.taskID == taskID { return true }
                let previous = $0.command.action["type"]?.string ?? ""
                if type.hasPrefix("task."), previous == "task.reorder" { return true }
                if type == "task.reorder", previous.hasPrefix("task.") { return true }
                if type == "task.create", case .object(let input) = fields["input"] {
                    return $0.target == input["parentTaskId"]?.string
                }
                return false
            })?.id
        changes.append(pending)
        do {
            try persist()
            syncDelay?.cancel()
            return true
        } catch {
            changes.removeLast()
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setMode(_ value: String) {
        if demo {
            mode = value
            return
        }
        guard value != mode else { return }
        if enqueue("mode.set", ["mode": .string(value), "expectedMode": .string(mode)]) { mode = value }
    }

    func task(_ id: UUID) -> SyncedTask? { snapshot?.tasks.first { $0.id == id.uuidString.lowercased() } }
    func linkedTask(for threadID: String) -> TodoItem? {
        guard let thread = snapshot?.threads.first(where: { $0.id == threadID && $0.origin == "task" && $0.archivedAt == nil }),
              let taskID = thread.taskId else { return nil }
        return todos?.items.first { $0.id.uuidString.lowercased() == taskID }
    }
    func results(_ id: UUID) -> [SyncResult] {
        snapshot?.results.filter { $0.taskId == id.uuidString.lowercased() } ?? []
    }
    func pendingSuggestion(_ taskID: String) -> PendingChange? {
        changes.first { $0.error == nil && $0.command.action["type"] == "task.suggestion" && $0.target == taskID }
    }
    func pendingReview(_ resultID: String) -> PendingChange? {
        changes.first { $0.error == nil && $0.command.action["type"] == "task.review" && $0.target == resultID }
    }
    func isAwaitingReview(_ result: SyncResult) -> Bool {
        result.outcome == "review" && result.dismissedAt == nil && pendingReview(result.id) == nil
    }
    var inboxQuestions: [InboxQuestion] {
        guard let snapshot else { return [] }
        let agentQuestions = snapshot.threads.compactMap { thread -> InboxQuestion? in
            guard thread.archivedAt == nil, let question = thread.question else { return nil }
            let agent = snapshot.agents.first { $0.id == thread.agentId }
            return InboxQuestion(question: question, title: thread.title, agent: DemoAgent(
                id: thread.agentId, name: agent?.name ?? "Agent", colorHex: agent?.color ?? "2080FB", description: ""
            ))
        }
        let plannerQuestions = mode == "suggest" ? [] : snapshot.tasks.compactMap { task -> InboxQuestion? in
            guard let question = task.proactiveQuestion else { return nil }
            return InboxQuestion(question: question, title: task.title, agent: DemoAgent(
                id: "planner", name: "Dony Planner", colorHex: "FFA800", description: ""
            ), taskId: task.id)
        }
        return agentQuestions + plannerQuestions
    }
    var inboxPendingCount: Int {
        inboxQuestions.filter { question in
            guard let change = answerChange(question.id) else { return true }
            return change.error != nil
        }.count
    }
    var inboxResults: [SyncResult] {
        let dismissed = Set(changes.filter {
            $0.command.action["type"] == "result.dismiss" && $0.error == nil
        }.compactMap { $0.command.action["resultId"]?.string })
        return snapshot?.results.filter {
            $0.outcome != "review" && $0.dismissedAt == nil && !dismissed.contains($0.id)
        } ?? []
    }
    func dismissInboxResult(_ result: SyncResult) {
        guard result.outcome != "review", !hasPending(result.id) else { return }
        if let failed = changes.first(where: {
            $0.command.action["type"] == "result.dismiss" && $0.target == result.id && $0.error != nil
        }) {
            retry(failed.id)
            return
        }
        _ = enqueue("result.dismiss", ["resultId": .string(result.id)])
    }
    func clearInboxResults() {
        for result in inboxResults { dismissInboxResult(result) }
    }
    func isPending(_ id: UUID) -> Bool { hasPending(id.uuidString.lowercased()) }
    func hasPending(_ target: String) -> Bool { changes.contains { $0.target == target && $0.error == nil } }
    func thread(_ id: String) -> SyncedThread? { snapshot?.threads.first { $0.id == id } }

    func taskThread(for taskID: UUID) -> SyncedThread? {
        snapshot?.threads
            .filter { $0.taskId == taskID.uuidString.lowercased() && $0.archivedAt == nil }
            .max { $0.updatedAt < $1.updatedAt }
    }

    func questionThread(for taskID: UUID) -> SyncedThread? {
        snapshot?.threads
            .filter { $0.taskId == taskID.uuidString.lowercased() && $0.archivedAt == nil && $0.question != nil }
            .max { $0.updatedAt < $1.updatedAt }
    }

    func answerChange(_ questionID: String) -> PendingChange? {
        changes.first { $0.command.action["type"] == "question.answer" && $0.command.action["questionId"]?.string == questionID }
    }

    func suggestion(_ task: SyncedTask, action: String) {
        guard pendingSuggestion(task.id) == nil else { return }
        _ = enqueue(
            "task.suggestion",
            [
                "taskId": .string(task.id), "expectedUpdatedAt": .string(task.updatedAt),
                "action": .string(action),
            ])
    }
    @discardableResult
    func review(_ result: SyncResult, feedback: String? = nil) -> Bool {
        guard isAwaitingReview(result) else { return false }
        guard enqueue(
            "task.review",
            [
                "resultId": .string(result.id), "action": feedback == nil ? "accept" : "changes",
                "feedback": .string(feedback ?? ""),
            ]) else { return false }
        if let snapshot { todos?.receive(snapshot.tasks, pending: changes, results: snapshot.results) }
        return true
    }
    @discardableResult
    func answer(_ question: SyncQuestion, taskId: String?, response: SyncValue) -> Bool {
        guard answerChange(question.id) == nil else { return false }
        return enqueue(
            "question.answer",
            ["questionId": .string(question.id), "taskId": .optional(taskId), "response": response])
    }
    func stop(_ thread: SyncedThread) {
        guard thread.status == "running", let runId = thread.runId, !isStopping(thread) else { return }
        _ = enqueue("run.stop", ["threadId": .string(thread.id), "runId": .string(runId)])
    }

    func isStopping(_ thread: SyncedThread) -> Bool {
        changes.contains {
            $0.error == nil && $0.command.action["type"] == "run.stop"
                && $0.command.action["runId"]?.string == thread.runId
        }
    }
    func openArtifact(_ result: SyncResult, index: Int) {
        guard !isOpeningArtifact(result, index: index),
            enqueue("artifact.read", ["resultId": .string(result.id), "index": .number(index)]),
            let commandID = changes.last?.id else { return }
        artifactSyncTask?.cancel()
        let generation = generation
        artifactSyncTask = Task { [weak self] in
            // Explicit file opens should not wait through two normal polling intervals.
            let deadline = Date.now.addingTimeInterval(10)
            while !Task.isCancelled && Date.now < deadline {
                guard let self, self.generation == generation,
                    self.changes.contains(where: { $0.id == commandID && $0.error == nil }) else { return }
                if !self.syncing {
                    await self.sync()
                    if !self.serverOnline { return }
                }
                do { try await Task.sleep(for: .milliseconds(200)) }
                catch { return }
            }
        }
    }

    func isOpeningArtifact(_ result: SyncResult, index: Int) -> Bool {
        changes.contains {
            $0.error == nil && $0.command.action["type"] == "artifact.read"
                && $0.command.action["resultId"] == .string(result.id)
                && $0.command.action["index"] == .number(index)
        }
    }

    func discard(_ id: String) {
        // A submitted command may already be running; only terminal failures can be dismissed.
        guard changes.first(where: { $0.id == id })?.error != nil else { return }
        changes.removeAll { $0.id == id }
        for index in changes.indices where changes[index].dependsOn == id {
            changes[index].dependsOn = nil
            changes[index].error = "The previous change was dismissed. Review this change before applying it."
        }
        do {
            try persist()
            reconcile()
            syncDelay?.cancel()
        } catch { errorMessage = error.localizedDescription }
    }
    func retry(_ id: String) {
        guard let index = changes.firstIndex(where: { $0.id == id && $0.error != nil }) else { return }
        var pending = changes[index]
        if let dependency = pending.dependsOn, changes.contains(where: { $0.id == dependency }) {
            errorMessage = "Resolve the earlier change before applying this one."
            return
        }
        rebase(&pending)
        let oldId = pending.id
        pending.command = SyncCommand(id: UUID().uuidString.lowercased(), action: pending.command.action)
        pending.error = nil
        pending.submitted = false
        pending.dependsOn = nil
        changes[index] = pending
        for position in changes.indices where changes[position].dependsOn == oldId {
            changes[position].dependsOn = pending.id
        }
        do {
            try persist()
            reconcile()
            syncDelay?.cancel()
        } catch { errorMessage = error.localizedDescription }
    }

    private func resetMacConnection() {
        macConnectionFailures = 0
        localMacUnavailable = false
        connectBannerDismissed = false
        usingRemoteMac = false
        retryLocalMacAt = .distantPast
    }

    private func macRequest<T: Decodable>(_ desktop: PairedDesktop, endpoint: String,
                                         body: [String: SyncValue]? = nil, encodedBody: Data? = nil) async throws -> T {
        guard let connection else { throw CompanionFailure("Connect your Mac first.") }
        let canRelay = cloudStatus?.billing?.hasRemoteDesktop == true && desktop.certificateFingerprint != nil
        if !canRelay || !usingRemoteMac || Date.now >= retryLocalMacAt {
            do {
                let value: T = try await request(server: desktop.server, token: desktop.token, endpoint: endpoint,
                    body: body, encodedBody: encodedBody, fingerprint: desktop.certificateFingerprint,
                    apiPrefix: "v1/companion", timeout: 3)
                if usingRemoteMac { resetMacSubmissions() }
                resetMacConnection()
                return value
            } catch {
                // Invalid credentials and rejected commands must not switch transports.
                if error is HTTPFailure { throw error }
                macConnectionFailures += 1
                localMacUnavailable = macConnectionFailures >= 2
                guard canRelay else { throw error }
            }
        }
        if !usingRemoteMac { resetMacSubmissions() }
        usingRemoteMac = true
        if Date.now >= retryLocalMacAt { retryLocalMacAt = Date.now.addingTimeInterval(30) }
        return try await request(server: connection.server, token: desktop.token, endpoint: endpoint,
            body: body, encodedBody: encodedBody, apiPrefix: "v1/companion")
    }

    private func resetMacSubmissions() {
        // A different transport may not have seen the original receipt. The Mac deduplicates the same command ID.
        for index in changes.indices where changes[index].command.executionTarget == "computer" && changes[index].error == nil {
            changes[index].submitted = false
        }
    }

    func sync() async {
        guard let connection, !syncing, !blockedByRevocation else { return }
        syncing = true
        let generation = generation
        defer {
            syncing = false
            if serverOnline { syncFailures = 0 }
        }
        do {
            struct State: Decodable {
                let revision: Int
                let desktopOnline: Bool
                let snapshot: SyncSnapshot?
                let receipts: [SyncReceipt]
                let pro: Bool?
                let executionTarget: String?
            }
            var state: State = try await request(
                server: connection.server, token: connection.token, endpoint: "state",
                body: [
                    "revision": .number(revision),
                    "commandIds": .array(
                        changes.filter { $0.error == nil }.prefix(100).map { .string($0.id) }),
                ])
            guard generation == self.generation else { return }
            if isCloud && Date().timeIntervalSince(lastBillingRefresh) >= 300 {
                lastBillingRefresh = Date()
                try? await refreshCloudAccount()
                guard generation == self.generation else { return }
            }
            if let pro = state.pro { proEnabled = pro }
            if let target = state.executionTarget { executionTarget = target }
            var receipts = state.receipts
            var computerAvailable = !isCloud
            if isCloud, let desktop = connection.pairedDesktop,
               (executionTarget == "computer" || changes.contains(where: { $0.command.executionTarget == "computer" && $0.error == nil })) {
                let local: State? = try? await macRequest(desktop, endpoint: "state",
                    body: ["revision": .number(-1), "commandIds": .array(changes.filter { $0.command.executionTarget == "computer" && $0.error == nil }.prefix(100).map { .string($0.id) })])
                if let local, !local.receipts.isEmpty {
                    // The desktop publishes its cloud snapshot before relay receipts. Refresh that state before acknowledging work.
                    state = try await request(server: connection.server, token: connection.token, endpoint: "state",
                        body: ["revision": .number(revision), "commandIds": .array(changes.filter { $0.error == nil }.prefix(100).map { .string($0.id) })])
                    guard generation == self.generation else { return }
                    receipts = state.receipts + local.receipts
                }
                computerAvailable = local?.desktopOnline == true
            }
            let receivedChanges = state.snapshot != nil || receipts.contains { receipt in
                changes.contains { $0.id == receipt.id }
            }
            if let snapshot = state.snapshot { self.snapshot = snapshot }
            if receivedChanges || revision != state.revision { needsCheckpoint = true }
            revision = state.revision
            desktopOnline = isCloud && executionTarget == "computer" ? computerAvailable : state.desktopOnline
            if !isCloud { resetMacConnection() }
            serverOnline = true
            connectionError = isCloud && !computerAvailable && changes.contains(where: { $0.command.executionTarget == "computer" && $0.error == nil })
                ? "Your Mac is unreachable. Keep it awake with Dony open." : nil
            for receipt in receipts {
                guard let index = changes.firstIndex(where: { $0.id == receipt.id }) else { continue }
                if receipt.status == "completed" {
                    if let file = receipt.file { try savePreview(file, id: receipt.id) }
                    let applied = changes.remove(at: index).command.action
                    for position in changes.indices {
                        let action = changes[position].command.action
                        if let taskId = action["taskId"]?.string, let version = receipt.taskVersions?[taskId],
                            action["expectedUpdatedAt"]?.string == (version.before ?? "")
                        {
                            changes[position].command.action["expectedUpdatedAt"] = .string(version.after)
                        }
                        if applied["type"] == "mode.set", action["type"] == "mode.set",
                            action["expectedMode"] == applied["expectedMode"]
                        {
                            changes[position].command.action["expectedMode"] = applied["mode"]
                        }
                    }
                    for position in changes.indices where changes[position].dependsOn == receipt.id {
                        changes[position].dependsOn = nil
                        if changes[position].error == "An earlier change needs attention first." {
                            changes[position].error = nil
                        }
                    }
                } else {
                    changes[index].error = receipt.error ?? "This change could not be applied."
                    if isCloud && changes[index].command.executionTarget != "computer" {
                        try? await refreshCloudAccount()
                        if cloudStatus?.billing?.canRunCloud == false {
                            showingUsagePacks = cloudStatus?.billing?.limitReached == true
                            showingPaywall = true
                        }
                    }
                    blockDependents(of: receipt.id)
                }
            }
            if receivedChanges { reconcile() }
            if needsCheckpoint {
                try await checkpoint()
                guard generation == self.generation else { return }
                needsCheckpoint = false
            }
            // Preserve the user's order. Each change is acknowledged before its dependent change is sent.
            guard let index = changes.firstIndex(where: {
                $0.error == nil && (!isCloud || $0.command.executionTarget != "computer" || computerAvailable)
            }), changes[index].dependsOn == nil,
                !changes[index].submitted
            else { return }
            let command = changes[index].command
            if isCloud, command.executionTarget == "computer", let desktop = connection.pairedDesktop {
                let _: EmptyResponse = try await macRequest(desktop, endpoint: "commands", encodedBody: await Self.encode(command))
            } else {
              let _: EmptyResponse = try await request(
                server: connection.server, token: connection.token, endpoint: "commands",
                encodedBody: await Self.encode(command))
            }
            guard generation == self.generation else { return }
            if let index = changes.firstIndex(where: { $0.id == command.id }) {
                changes[index].submitted = true
            }
            try persist()
        } catch {
            guard generation == self.generation, !Task.isCancelled else { return }
            serverOnline = false
            syncFailures = min(syncFailures + 1, 7)
            if connection.isLocal, (error as? URLError)?.code == .notConnectedToInternet { localMacUnavailable = false }
            if connection.isLocal, error is URLError, (error as? URLError)?.code != .notConnectedToInternet {
                macConnectionFailures += 1
                localMacUnavailable = macConnectionFailures >= 2
            }
            // Local data and the outbox remain intact, including on transient authentication/network errors.
            if (error as? HTTPFailure)?.status == 401 {
                blockedByRevocation = true
                connectionError = isCloud ? "Sign in again to continue." : "Check your connection in Settings."
            } else if let failure = error as? HTTPFailure, [400, 403, 409, 413].contains(failure.status),
                let index = changes.firstIndex(where: { $0.error == nil })
            {
                changes[index].error = failure.message
                blockDependents(of: changes[index].id)
                try? persist()
                reconcile()
            } else if !(error is URLError) && !(error is HTTPFailure) {
                errorMessage = error.localizedDescription
            } else {
                connectionError = (error as? URLError)?.code == .notConnectedToInternet
                    ? "You’re offline." : "Couldn’t connect. Try again."
            }
        }
    }

    private func blockDependents(of id: String) {
        var failed = Set([id])
        for index in changes.indices {
            if let dependency = changes[index].dependsOn, failed.contains(dependency) {
                changes[index].error = "An earlier change needs attention first."
                failed.insert(changes[index].id)
            }
        }
    }

    private func installHandlers() {
        todos?.onMutation = { [weak self] type, fields in self?.enqueue(type, fields) ?? false }
        chats?.isDemo = false
        chats?.onCreate = { [weak self] agentId, threadId in
            self?.enqueue("chat.create", ["agentId": .string(agentId), "threadId": .string(threadId)])
                ?? false
        }
        chats?.onSend = { [weak self] text, files, threadId, thinking in
            do {
                guard files.count <= 5 else { throw CompanionFailure("Send up to five files at a time.") }
                let uploads = try files.map { try SyncFile($0) }
                guard uploads.reduce(0, { $0 + $1.base64.utf8.count }) <= 28_000_000 else {
                    throw CompanionFailure("Attachments must total 20 MB or less.")
                }
                let payload = uploads.map(\.payload)
                var fields: [String: SyncValue] = ["threadId": .string(threadId), "message": .string(text), "files": .array(payload)]
                if let thinking { fields["thinking"] = .string(thinking.rawValue) }
                return self?.enqueue("chat.send", fields)
                    ?? false
            } catch {
                self?.errorMessage = error.localizedDescription
                return false
            }
        }
        chats?.onView = { [weak self] id, viewedAt in
            guard let self, self.enqueue("chat.viewed", ["threadId": .string(id), "viewedAt": .string(viewedAt.ISO8601Format())]) else { return false }
            self.reconcile()
            return true
        }
        chats?.onArchive = { [weak self] id in
            guard let self, self.enqueue("chat.archive", ["threadId": .string(id)]) else { return false }
            self.reconcile()
            return true
        }
    }

    private func reconcile() {
        if let snapshot {
            todos?.receive(snapshot.tasks, pending: changes, results: snapshot.results)
            chats?.receive(snapshot, pending: changes)
            mode =
                changes.last(where: { $0.command.action["type"] == "mode.set" && $0.error == nil })?.command
                .action["mode"]?.string ?? snapshot.mode
        }
    }

    private func rebase(_ change: inout PendingChange) {
        if change.command.action["expectedUpdatedAt"] != nil,
            let taskId = change.command.action["taskId"]?.string,
            let task = snapshot?.tasks.first(where: { $0.id == taskId })
        {
            change.command.action["expectedUpdatedAt"] = .string(task.updatedAt)
        }
        if change.command.action["type"] == "mode.set" {
            change.command.action["expectedMode"] = .string(snapshot?.mode ?? "off")
        }
    }
    private func persist() throws {
        guard let connection else { return }
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let version = outboxVersion + 1
        let data = try JSONEncoder().encode(Outbox(desktopId: connection.desktopId, version: version, changes: changes))
        try data.write(to: outboxURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        outboxVersion = version
    }
    private func checkpoint() async throws {
        guard let connection else { return }
        // A newer outbox wins on restart if the user edits while this snapshot is being written.
        let cache = Cache(desktopId: connection.desktopId, snapshot: snapshot, changes: changes,
                          revision: revision, outboxVersion: outboxVersion, proEnabled: proEnabled, executionTarget: executionTarget)
        try await cacheWriter.save(cache, to: cacheURL)
    }
    private nonisolated static func encode<T: Encodable>(_ value: T) async throws -> Data {
        try JSONEncoder().encode(value)
    }
    private func savePreview(_ file: SyncFile, id: String) throws {
        guard let data = Data(base64Encoded: file.base64) else {
            throw CompanionFailure("Couldn’t decode the downloaded output.")
        }
        let directory = URL.temporaryDirectory.appending(path: "dony-output-\(id)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: (file.name as NSString).lastPathComponent)
        try data.write(to: url, options: .atomic)
        previewURL = url
    }
    private struct EmptyResponse: Decodable { let ok: Bool }
    private struct HTTPFailure: LocalizedError {
        let status: Int
        let message: String
        var errorDescription: String? { message }
    }
    func connectorRequest<T: Decodable>(_ body: [String: SyncValue]) async throws -> T {
        guard let connection, !blockedByRevocation else {
            throw CompanionFailure("Sign in to Dony to manage tools.")
        }
        let currentGeneration = generation
        do {
            let result: T = try await request(server: connection.server, token: connection.token,
                                              endpoint: "connectors", body: body)
            guard currentGeneration == generation, self.connection?.deviceId == connection.deviceId else {
                throw CancellationError()
            }
            return result
        } catch let error as HTTPFailure where error.status == 404 {
            throw CompanionFailure(isCloud ? "Tools are temporarily unavailable. Try again later." : "Update Dony on your computer to connect tools from your phone.")
        }
    }

    private func request<T: Decodable>(
        server: URL, token: String?, endpoint: String, method: String = "POST",
        body: [String: SyncValue]? = nil, encodedBody: Data? = nil, fingerprint: String? = nil, apiPrefix: String? = nil, timeout: TimeInterval = 30
    ) async throws -> T {
        let prefix = apiPrefix ?? (fingerprint != nil ? "v1/companion" : isCloud ? "v1/mobile" : "v1/companion")
        var request = URLRequest(url: server.appending(path: "\(prefix)/\(endpoint)"))
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try encodedBody ?? body.map { try JSONEncoder().encode($0) }
        let pin = fingerprint ?? (server == connection?.server ? connection?.certificateFingerprint : nil)
        let trust = CompanionLocalTrust(host: server.host ?? "", fingerprint: pin)
        var transport = session
        if let pin {
            let key = server.absoluteString + pin
            if localSessionKey != key {
                localSession?.invalidateAndCancel()
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = session.configuration.protocolClasses
                localSession = URLSession(configuration: configuration)
                localSessionKey = key
            }
            transport = localSession!
        }
        let (data, response) = try await transport.data(for: request, delegate: trust)
        guard let response = response as? HTTPURLResponse else {
            throw CompanionFailure("Invalid response from Dony.")
        }
        guard (200..<300).contains(response.statusCode) else {
            let message =
                (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                ?? "The Dony connection is unavailable."
            throw HTTPFailure(status: response.statusCode, message: message)
        }
        return try await Self.decode(T.self, from: data)
    }
    func signInCloud(importTodos: Bool) async throws {
        guard isCloud || changes.isEmpty else { throw CompanionFailure("Finish or resolve your changes in Settings before switching accounts.") }
        try await finishCloudSignIn(try await cloudSignIn.signIn(), importTodos: importTodos)
    }
    func signInCloudWithApple(importTodos: Bool) async throws {
        guard isCloud || changes.isEmpty else { throw CompanionFailure("Finish or resolve your changes in Settings before switching accounts.") }
        try await finishCloudSignIn(try await cloudSignIn.signInWithApple(), importTodos: importTodos)
    }
    private func finishCloudSignIn(_ signIn: (String, CloudAccount), importTodos: Bool) async throws {
        let (token, user) = signIn
        if isCloud {
            try await renewCloudSession(token: token, user: user)
            showingCloudSignIn = false
            return
        }
        let account: CloudAccountStatus = try await request(server: CloudSignIn.server, token: token, endpoint: "account", method: "GET", apiPrefix: "v1/mobile")
        let previous = connection
        if let previous, previous.accountId != user.id {
            throw CompanionFailure("Sign in to the same Dony account as your paired Mac to keep your connection and pending changes.")
        }
        let previousChanges = changes
        let pendingTaskIDs = Set(previousChanges.filter { $0.command.action["type"] == "task.create" }.compactMap { $0.taskID })
        let localTasks = importTodos ? (todos?.items.filter { !$0.isDemo } ?? []) : []
        let backup = cacheURL.deletingLastPathComponent().appending(path: "todos-before-pairing.json")
        if !FileManager.default.fileExists(atPath: backup.path) { try todos?.backupLocalTasks(to: backup) }
        let cloud = CompanionConnection(server: CloudSignIn.server, token: token, deviceId: UUID().uuidString.lowercased(),
            desktopId: account.workspaceId, desktopName: "Dony Cloud", accountId: user.id, transport: "cloud",
            pairedDesktop: previous?.accountId == user.id ? previous.map(PairedDesktop.init) : nil)
        struct InitialState: Decodable { let revision: Int; let snapshot: SyncSnapshot }
        let state: InitialState = try await request(server: cloud.server, token: token, endpoint: "state", body: ["revision": .number(-1), "commandIds": .array([])], apiPrefix: "v1/mobile")
        try credentials.save(cloud)
        setActive(false)
        generation += 1; connection = cloud; snapshot = state.snapshot; revision = state.revision; changes = previousChanges.map { change in
            var change = change; change.command.executionTarget = "computer"; return change
        }; blockedByRevocation = false
        cloudStatus = account; proEnabled = account.pro; executionTarget = account.executionTarget
        for task in localTasks.sorted(by: { $0.parentID == nil && $1.parentID != nil }) {
            let id = task.id.uuidString.lowercased()
            if pendingTaskIDs.contains(id) || snapshot?.tasks.contains(where: { $0.id == id }) == true { continue }
            let command = SyncCommand(id: UUID().uuidString.lowercased(), action: ["type": "task.create", "taskId": .string(id),
                "input": .object(["title": .string(task.title), "notes": .optional(task.notes), "dueDate": .optional(task.dueDate), "parentTaskId": .optional(task.parentID?.uuidString.lowercased())])], executionTarget: "cloud")
            var pending = PendingChange(command: command)
            if let parent = task.parentID { pending.dependsOn = changes.last(where: { $0.taskID == parent.uuidString.lowercased() })?.id }
            changes.append(pending)
            if task.isCompleted {
                changes.append(PendingChange(command: SyncCommand(id: UUID().uuidString.lowercased(), action: ["type": "task.update", "taskId": .string(id), "expectedUpdatedAt": "", "patch": .object(["status": "done"])], executionTarget: "cloud"), dependsOn: command.id))
            }
        }
        try persist(); try await checkpoint()
        installHandlers(); reconcile(); setActive(true)
        connectionError = nil
        showingCloudSignIn = false
        if cloud.pairedDesktop != nil { try await setCloudSettings(executionTarget: "computer") }
        if showingConnectPlan { showingPaywall = true }
        try? await registerCloudPush()
    }

    func renewCloudSession(token: String, user: CloudAccount) async throws {
        guard var connection, isCloud, connection.accountId == user.id else {
            throw CompanionFailure("Sign in to the same Dony account to continue. Your changes haven’t been removed.")
        }
        let generation = generation
        let account: CloudAccountStatus = try await request(server: connection.server, token: token, endpoint: "account", method: "GET")
        guard generation == self.generation else { throw CancellationError() }
        guard account.workspaceId == connection.desktopId else {
            throw CompanionFailure("This is a different workspace. Your changes haven’t been removed.")
        }
        connection.token = token
        try credentials.save(connection)
        setActive(false)
        self.generation += 1
        self.connection = connection
        blockedByRevocation = false
        connectionError = nil
        cloudStatus = account
        proEnabled = account.pro
        executionTarget = account.executionTarget
        // Keep the snapshot, command IDs, and receipts intact across session renewal.
        try await checkpoint()
        setActive(true)
    }
    func refreshCloudAccount() async throws {
        guard let connection, isCloud else { return }
        let account: CloudAccountStatus = try await request(server: connection.server, token: connection.token, endpoint: "account", method: "GET")
        guard self.connection?.accountId == connection.accountId else { return }
        cloudStatus = account; proEnabled = account.pro; executionTarget = account.executionTarget
        lastBillingRefresh = Date()
    }
    func syncBilling(transactions: [String], accountToken: String) async throws -> BillingStatus {
        guard let connection, isCloud, cloudStatus?.billing?.accountToken == accountToken else {
            throw CompanionFailure("Sign in to the Dony account that made this purchase.")
        }
        let status: BillingStatus = try await request(server: connection.server, token: connection.token,
            endpoint: "sync", body: ["transactions": .array(transactions.map(SyncValue.string))], apiPrefix: "v1/billing")
        guard self.connection?.accountId == connection.accountId else {
            throw CompanionFailure("Your Dony account changed. Please restore purchases in the correct account.")
        }
        try await refreshCloudAccount()
        return status
    }

    func setCloudSettings(pro: Bool? = nil, executionTarget target: String? = nil) async throws {
        guard let connection, isCloud else { return }
        var body: [String: SyncValue] = [:]
        if let pro { body["pro"] = .bool(pro) }
        if let target { body["executionTarget"] = .string(target) }
        let status: CloudAccountStatus = try await request(server: connection.server, token: connection.token, endpoint: "settings", body: body)
        proEnabled = status.pro; executionTarget = status.executionTarget; cloudStatus = status
        try await checkpoint()
        await sync()
    }
    func editableAgent(_ id: String) -> SyncedAgent? {
        guard isCloud else { return nil }
        return snapshot?.agents.first { $0.id == id }
    }
    func saveCloudAgent(id: String? = nil, name: String, instructions: String, color: String) async throws {
        if id == nil && !requireAIAccess() {
            throw CompanionFailure("Choose a plan or connect your Mac to create an agent.")
        }
        guard let connection, isCloud else {
            throw CompanionFailure("Sign in to Dony to manage your agents.")
        }
        var body: [String: SyncValue] = ["name": .string(name), "instructions": .string(instructions), "color": .string(color)]
        if let id { body["id"] = .string(id) }
        let _: EmptyResponse = try await request(server: connection.server, token: connection.token, endpoint: "agents", body: body)
        await sync()
    }
    func enableCloudNotifications() async throws {
        let accepted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        if accepted { UIApplication.shared.registerForRemoteNotifications() }
    }
    func registerCloudPush() async throws {
        guard let connection, isCloud, let token = UserDefaults.standard.string(forKey: "cloudPushToken") else { return }
        #if DEBUG
        let environment = "development"
        #else
        let environment = "production"
        #endif
        let _: EmptyResponse = try await request(server: connection.server, token: connection.token, endpoint: "push", body: ["token": .string(token), "environment": .string(environment)])
    }
    func signOutCloud() async throws {
        guard let connection, isCloud else { return }
        guard changes.isEmpty else { throw CompanionFailure("Some changes haven’t finished. Try again, or review them in Settings before signing out.") }
        if let token = UserDefaults.standard.string(forKey: "cloudPushToken") {
            let _: EmptyResponse = try await request(server: connection.server, token: connection.token, endpoint: "push", method: "DELETE", body: ["token": .string(token)])
        }
        try await disconnectCloud()
    }
    func deleteCloudAccount() async throws {
        guard let connection, isCloud else { return }
        guard changes.isEmpty else { throw CompanionFailure("Some changes haven’t finished. Try again, or review them in Settings before deleting your account.") }
        let _: EmptyResponse = try await request(server: connection.server, token: connection.token, endpoint: "account", method: "DELETE")
        try await disconnectCloud()
    }
    private func disconnectCloud() async throws {
        setActive(false); generation += 1
        try credentials.remove()
        resetMacConnection()
        self.connection = nil; snapshot = nil; revision = -1; mode = "off"; proEnabled = false; executionTarget = "cloud"; cloudStatus = nil
        todos?.onMutation = nil; chats?.disconnect()
        let backup = cacheURL.deletingLastPathComponent().appending(path: "todos-before-pairing.json")
        if FileManager.default.fileExists(atPath: backup.path) { try todos?.restoreLocalTasks(from: backup) }
        try? FileManager.default.removeItem(at: outboxURL)
        await cacheWriter.remove(cacheURL)
        serverOnline = false; desktopOnline = false
        blockedByRevocation = false; connectionError = nil
    }

    private nonisolated static func decode<T: Decodable>(_ type: T.Type, from data: Data) async throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}

private actor CompanionCacheWriter {
    func save(_ cache: CompanionStore.Cache, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(cache)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

import SwiftData
import XCTest
@testable import DonyMobile

@MainActor
final class MobileOnboardingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "DonyOnboardingTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func store() throws -> TodoStore {
        let container = try ModelContainer(for: TodoItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return try TodoStore(container: container, defaults: defaults, seedExamples: false)
    }

    func testFreshInstallStaysInOnboardingAfterTodoInitializationAndRelaunch() throws {
        MobileOnboarding.prepare(defaults: defaults)
        XCTAssertFalse(MobileOnboarding(defaults: defaults).completed)
        XCTAssertEqual(MobileOnboarding(defaults: defaults).step, -1)
        XCTAssertTrue(try store().items.isEmpty)
        MobileOnboarding.prepare(defaults: defaults)
        XCTAssertFalse(MobileOnboarding(defaults: defaults).completed)
        XCTAssertEqual(MobileOnboarding(defaults: defaults).step, -1)
    }

    func testExistingInstallKeepsItsWorkspaceAccessible() {
        defaults.set(true, forKey: "hasSeededTodos")
        MobileOnboarding.prepare(defaults: defaults)
        XCTAssertTrue(MobileOnboarding(defaults: defaults).completed)
    }

    func testRelaunchRestoresStepAndSelection() {
        let progress = MobileOnboarding(defaults: defaults)
        progress.step = 6
        progress.tasks[0].selected = true
        let restored = MobileOnboarding(defaults: defaults)
        XCTAssertEqual(restored.step, 6)
        XCTAssertEqual(restored.tasks.map(\.id), progress.tasks.map(\.id))
        XCTAssertEqual(restored.tasks.filter(\.selected).map(\.title), ["List recurring paid subscriptions"])
    }

    func testPartialSaveCanRetryAfterRelaunchWithoutDuplicateTasks() throws {
        let todos = try store()
        let progress = MobileOnboarding(defaults: defaults)
        progress.tasks[0].selected = true
        progress.tasks[1].selected = true
        var mutations = 0
        todos.onMutation = { _, _ in mutations += 1; return mutations == 1 }
        XCTAssertFalse(progress.finish(todos: todos))
        XCTAssertFalse(progress.completed)
        XCTAssertEqual(todos.items.count, 1)

        let restored = MobileOnboarding(defaults: defaults)
        todos.onMutation = { _, _ in mutations += 1; return true }
        XCTAssertTrue(restored.finish(todos: todos))
        XCTAssertEqual(todos.items.count, 2)
        XCTAssertEqual(mutations, 3)
        XCTAssertTrue(MobileOnboarding(defaults: defaults).completed)
    }

    func testEmptyListDoesNotCreateSuggestionsOrDeleteExistingWork() throws {
        let todos = try store()
        todos.add("Existing task")
        let progress = MobileOnboarding(defaults: defaults)
        progress.tasks[0].selected = true
        XCTAssertTrue(progress.finish(todos: todos, empty: true))
        XCTAssertEqual(todos.items.map(\.title), ["Existing task"])
    }

    func testDefaultsAreUnselectedAndSaveTheirDescriptions() throws {
        let progress = MobileOnboarding(defaults: defaults)
        XCTAssertEqual(progress.tasks.map(\.title), [
            "List recurring paid subscriptions",
            "Find upcoming renewals and deadlines",
            "Prep for next external meeting",
            "Unsubscribe from promotional emails"
        ])
        XCTAssertTrue(progress.tasks.allSatisfy { !$0.selected })
        XCTAssertTrue(progress.tasks.allSatisfy { !($0.notes ?? "").isEmpty })
        progress.tasks[0].selected = true
        let restored = MobileOnboarding(defaults: defaults)
        XCTAssertEqual(restored.tasks.map(\.id), progress.tasks.map(\.id))
        let todos = try store()
        XCTAssertTrue(restored.finish(todos: todos))
        XCTAssertEqual(todos.items.count, 1)
        XCTAssertEqual(todos.items.first?.notes,
            "Go through my email to find recurring subscriptions. List each service, amount, renewal date, and anything that looks unused.")
    }

    func testLegacyTasksKeepUserWorkAndReplaceUnselectedSuggestions() throws {
        let saved = [
            MobileOnboarding.FirstTask(id: UUID(), title: "Draft a project update"),
            MobileOnboarding.FirstTask(id: UUID(), title: "AI suggestion", emailSubject: "An email"),
            MobileOnboarding.FirstTask(id: UUID(), title: "Selected suggestion", selected: true, emailSubject: "Another email", notes: "Saved context"),
            MobileOnboarding.FirstTask(id: UUID(), title: "My own task", selected: true)
        ]
        defaults.set(try JSONEncoder().encode(saved), forKey: "mobileOnboardingTasks")
        defaults.set(5, forKey: "mobileOnboardingStep")
        let progress = MobileOnboarding(defaults: defaults)
        XCTAssertEqual(progress.step, 4)
        XCTAssertEqual(progress.tasks.count, 6)
        XCTAssertEqual(progress.tasks.filter(\.selected).map(\.id), [saved[2].id, saved[3].id])
        XCTAssertEqual(progress.tasks.first { $0.id == saved[2].id }?.notes, "Saved context")
        let restored = MobileOnboarding(defaults: defaults)
        XCTAssertEqual(restored.step, 4)
        XCTAssertEqual(restored.tasks.map(\.id), progress.tasks.map(\.id))
    }

    func testLegacyEmailStepShowsTasksBeforeConnecting() throws {
        defaults.set(try JSONEncoder().encode([MobileOnboarding.FirstTask(id: UUID(), title: "Draft a project update")]),
            forKey: "mobileOnboardingTasks")
        defaults.set(4, forKey: "mobileOnboardingStep")
        XCTAssertEqual(MobileOnboarding(defaults: defaults).step, 4)
        XCTAssertEqual(MobileOnboarding(defaults: defaults).step, 4)
    }
}

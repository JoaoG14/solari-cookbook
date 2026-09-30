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
        progress.step = 4
        progress.tasks[0].selected = true
        let restored = MobileOnboarding(defaults: defaults)
        XCTAssertEqual(restored.step, 4)
        XCTAssertEqual(restored.tasks.map(\.id), progress.tasks.map(\.id))
        XCTAssertEqual(restored.tasks.filter(\.selected).map(\.title), ["Research solar energy"])
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
            "Research solar energy",
            "Compare browser automation tools",
            "Plan a weekend in Lisbon",
            "Explore the history of the web"
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
            "Use the cloud browser to read https://en.wikipedia.org/wiki/Solar_energy, follow a relevant link, and summarize three facts with source links.")
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

    func testRemovedStepsReturnToTasksAndPreserveSelectedWork() throws {
        for oldStep in [5, 6] {
            let saved = [
                MobileOnboarding.FirstTask(id: UUID(), title: "List recurring paid subscriptions"),
                MobileOnboarding.FirstTask(id: UUID(), title: "My selected task", selected: true, notes: "Keep this")
            ]
            defaults.removeObject(forKey: "mobileOnboardingBrowserTasks")
            defaults.set(true, forKey: "mobileOnboardingFixedTasks")
            defaults.set(try JSONEncoder().encode(saved), forKey: "mobileOnboardingTasks")
            defaults.set(oldStep, forKey: "mobileOnboardingStep")
            let progress = MobileOnboarding(defaults: defaults)
            XCTAssertEqual(progress.step, 4)
            XCTAssertFalse(progress.tasks.contains { $0.title == "List recurring paid subscriptions" })
            XCTAssertEqual(progress.tasks.filter(\.selected).map(\.id), [saved[1].id])
            XCTAssertEqual(MobileOnboarding(defaults: defaults).step, 4)
        }
    }
}

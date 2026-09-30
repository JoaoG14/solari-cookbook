import SwiftData
import XCTest
@testable import DonyMobile

@MainActor
final class TodoStoreTests: XCTestCase {
    private func defaults(seeded: Bool = true) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "DonyMobileUnitTests")!
        defaults.removePersistentDomain(forName: "DonyMobileUnitTests")
        defaults.set(seeded, forKey: "hasSeededTodos")
        return defaults
    }

    private func makeStore() throws -> TodoStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: TodoItem.self, configurations: configuration)
        return try TodoStore(container: container, defaults: defaults())
    }

    func testCreateEditCompleteReopenAndDelete() async throws {
        let store = try makeStore()
        store.add("  Review the proposal  ")
        store.add(" \n ")
        XCTAssertEqual(store.active.map(\.title), ["Review the proposal"])

        let item = try XCTUnwrap(store.active.first)
        store.rename(item, to: "  Review the revised proposal\n")
        store.rename(item, to: "   ")
        XCTAssertEqual(item.title, "Review the revised proposal")

        store.toggle(item)
        XCTAssertTrue(store.active.isEmpty)
        XCTAssertEqual(store.completed.map(\.id), [item.id])
        store.toggle(item)
        XCTAssertTrue(store.completed.isEmpty)
        XCTAssertEqual(store.active.map(\.id), [item.id])

        store.delete(item)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.errorMessage)
    }

    func testReorderingAndSectionTransitions() async throws {
        let store = try makeStore()
        ["One", "Two", "Three"].forEach(store.add)
        store.move(from: IndexSet(integer: 0), to: 3, completed: false)
        XCTAssertEqual(store.active.map(\.title), ["Two", "Three", "One"])

        let two = store.active[0]
        let three = store.active[1]
        store.toggle(two)
        store.toggle(three)
        store.move(from: IndexSet(integer: 0), to: 2, completed: true)
        XCTAssertEqual(store.completed.map(\.title), ["Three", "Two"])

        store.toggle(two)
        XCTAssertEqual(store.active.map(\.title), ["One", "Two"])
        XCTAssertEqual(store.completed.map(\.title), ["Three"])
    }

    func testSubtasksAndDueDates() throws {
        let store = try makeStore()
        store.add("Prepare launch", dueDate: "2026-09-10", parent: nil)
        let parent = try XCTUnwrap(store.active.first)
        store.add("Review copy", dueDate: "2026-09-09", parent: parent)
        store.add("Check links", dueDate: nil, parent: parent)
        let child = try XCTUnwrap(store.children(of: parent).first)
        XCTAssertEqual(store.active.count, 1)
        XCTAssertEqual(store.children(of: parent).map(\.title), ["Review copy", "Check links"])

        store.toggle(parent)
        XCTAssertFalse(child.isCompleted)
        store.toggle(child)
        XCTAssertEqual(store.children(of: parent).last?.id, child.id)
        store.update(child, title: "Review final copy", dueDate: nil)
        XCTAssertNil(child.dueDate)
        XCTAssertEqual(parent.dueDate, "2026-09-10")
        store.delete(child)
        XCTAssertEqual(store.children(of: parent).count, 1)
        store.delete(parent)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testDueDateKeepsItsCalendarDayAcrossTimeZones() {
        var east = Calendar(identifier: .gregorian)
        east.timeZone = TimeZone(secondsFromGMT: 14 * 3600)!
        var west = Calendar(identifier: .gregorian)
        west.timeZone = TimeZone(secondsFromGMT: -10 * 3600)!
        let key = "2026-09-10"
        XCTAssertEqual(TodoDueDate.key(TodoDueDate.date(key, calendar: east), calendar: east), key)
        XCTAssertEqual(TodoDueDate.key(TodoDueDate.date(key, calendar: west), calendar: west), key)
        let today = TodoDueDate.date(key)
        XCTAssertEqual(TodoDueDate.label(key, now: today), "Today")
        XCTAssertEqual(TodoDueDate.label("2026-09-11", now: today), "Tomorrow")
    }

    func testCompactDueDateKeepsRelativeLabelsAndOtherYears() {
        let today = TodoDueDate.date("2026-09-10")
        XCTAssertEqual(TodoDueDate.compactLabel("2026-09-10", now: today), "Today")
        XCTAssertEqual(TodoDueDate.compactLabel("2026-09-11", now: today), "Tomorrow")
        XCTAssertFalse(TodoDueDate.compactLabel("2026-09-15", now: today).contains("2026"))
        XCTAssertTrue(TodoDueDate.compactLabel("2027-01-15", now: today).contains("2027"))
        XCTAssertTrue(TodoDueDate.compactLabel("2025-12-15", now: today).contains("2025"))
    }

    func testDiskPersistenceAndSeedOnlyOnceAfterErasure() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Todos.store")
        let defaults = defaults(seeded: false)

        func openStore() throws -> TodoStore {
            let configuration = ModelConfiguration(url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: TodoItem.self, configurations: configuration)
            return try TodoStore(container: container, defaults: defaults)
        }

        var store: TodoStore? = try openStore()
        XCTAssertEqual(store?.items.count, 3)
        store?.add("A task that survives relaunch")
        let first = try XCTUnwrap(store?.active.first)
        store?.rename(first, to: "Edited before relaunch")
        store?.update(first, title: first.title, dueDate: "2026-09-10")
        store?.add("Persistent subtask", dueDate: "2026-09-09", parent: first)
        store?.toggle(first)
        store?.move(from: IndexSet(integer: 2), to: 0, completed: false)
        let expectedOrder = store?.active.map(\.title)
        store = nil

        store = try openStore()
        XCTAssertEqual(store?.items.count, 5)
        let reopenedParent = try XCTUnwrap(store?.completed.first)
        XCTAssertEqual(reopenedParent.dueDate, "2026-09-10")
        XCTAssertEqual(store?.children(of: reopenedParent).first?.dueDate, "2026-09-09")
        XCTAssertEqual(store?.active.map(\.title), expectedOrder)
        XCTAssertEqual(store?.completed.map(\.title), ["Edited before relaunch"])

        store?.eraseAll()
        XCTAssertNil(store?.errorMessage)
        store = nil
        store = try openStore()
        XCTAssertTrue(try XCTUnwrap(store).items.isEmpty)
        XCTAssertTrue(defaults.bool(forKey: "hasSeededTodos"))
    }
}

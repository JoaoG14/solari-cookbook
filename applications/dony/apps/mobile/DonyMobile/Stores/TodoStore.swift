import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class TodoStore {
    private(set) var items: [TodoItem]
    var errorMessage: String?
    var onMutation: ((String, [String: SyncValue]) -> Bool)?

    private let context: ModelContext
    private let defaults: UserDefaults

    var active: [TodoItem] { sortedItems(completed: false) }
    var completed: [TodoItem] { sortedItems(completed: true) }

    init(container: ModelContainer, defaults: UserDefaults = .standard, seedExamples: Bool = true) throws {
        self.context = ModelContext(container)
        self.context.autosaveEnabled = false
        self.defaults = defaults
        self.items = try context.fetch(FetchDescriptor<TodoItem>())

        guard !defaults.bool(forKey: "hasSeededTodos") else { return }
        if items.isEmpty && seedExamples {
            let titles = ["Prepare the weekly update", "Review the landing page", "Share feedback on the proposal"]
            for (index, title) in titles.enumerated() {
                let item = TodoItem(title: title, sortOrder: index)
                item.isDemo = true
                context.insert(item)
                items.append(item)
            }
            try context.save()
        }
        defaults.set(true, forKey: "hasSeededTodos")
    }

    func add(_ title: String) {
        add(title, dueDate: nil, parent: nil)
    }

    @discardableResult
    func add(_ title: String, dueDate: String?, parent: TodoItem?, id: UUID = UUID(), notes: String? = nil) -> TodoItem? {
        if let existing = items.first(where: { $0.id == id }) { return existing }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        // Subtasks have one level and always belong to a top-level task.
        if let parent, parent.parentID != nil { return nil }
        let item = TodoItem(title: title, sortOrder: nextOrder(completed: false, parentID: parent?.id))
        item.id = id
        if onMutation != nil, parent == nil { item.sortOrder = (active.first?.sortOrder ?? 0) - 1 }
        parent?.isDemo = false
        item.parentID = parent?.id
        item.dueDate = dueDate
        item.notes = notes
        let input: [String: SyncValue] = ["title": .string(item.title), "dueDate": .optional(dueDate), "parentTaskId": .optional(parent?.id.uuidString.lowercased()), "notes": .optional(notes)]
        if let onMutation, !onMutation("task.create", ["taskId": .string(item.id.uuidString.lowercased()), "input": .object(input)]) { return nil }
        context.insert(item)
        items.append(item)
        guard save() else { return nil }
        return item
    }

    func rename(_ item: TodoItem, to title: String) {
        update(item, title: title, dueDate: item.dueDate)
    }

    func update(_ item: TodoItem, title: String, dueDate: String?) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if let onMutation, !onMutation("task.update", ["taskId": .string(item.id.uuidString.lowercased()), "expectedUpdatedAt": .string(item.desktopUpdatedAt ?? ""), "patch": .object(["title": .string(title), "dueDate": .optional(dueDate)])]) { return }
        item.isDemo = false
        item.title = title
        item.dueDate = dueDate
        save()
    }

    func children(of item: TodoItem) -> [TodoItem] {
        sortedItems(completed: false, parentID: item.id) + sortedItems(completed: true, parentID: item.id)
    }

    func toggle(_ item: TodoItem) {
        if let onMutation, !onMutation("task.update", ["taskId": .string(item.id.uuidString.lowercased()), "expectedUpdatedAt": .string(item.desktopUpdatedAt ?? ""), "patch": .object(["status": item.isCompleted ? "todo" : "done"])]) { return }
        item.isDemo = false
        item.sortOrder = onMutation != nil && !item.isCompleted
            ? (sortedItems(completed: true, parentID: item.parentID).first?.sortOrder ?? 0) - 1
            : nextOrder(completed: !item.isCompleted, parentID: item.parentID)
        item.isCompleted.toggle()
        save()
    }

    func delete(_ item: TodoItem) {
        if let onMutation, !onMutation("task.delete", ["taskId": .string(item.id.uuidString.lowercased()), "expectedUpdatedAt": .string(item.desktopUpdatedAt ?? "")]) { return }
        let removed = children(of: item) + [item]
        let ids = Set(removed.map(\.id))
        items.removeAll { ids.contains($0.id) }
        for item in removed { context.delete(item) }
        save()
    }

    func move(from offsets: IndexSet, to destination: Int, completed: Bool) {
        let expectedOrder = (Array(active.reversed()) + self.completed.reversed()).map { SyncValue.string($0.id.uuidString.lowercased()) }
        var section = sortedItems(completed: completed)
        section.move(fromOffsets: offsets, toOffset: destination)
        let ordered = completed ? Array(active.reversed()) + section.reversed() : Array(section.reversed()) + self.completed.reversed()
        if let onMutation, !onMutation("task.reorder", ["input": .object(["parentTaskId": .null, "taskIds": .array(ordered.map { .string($0.id.uuidString.lowercased()) })]), "expectedOrder": .array(expectedOrder)]) { return }
        for (index, item) in section.enumerated() {
            item.sortOrder = index
        }
        save()
    }

    func eraseAll() {
        guard onMutation == nil else { errorMessage = "Delete shared tasks individually from your To-do List."; return }
        for item in items { context.delete(item) }
        items.removeAll()
        save()
    }

    func receive(_ tasks: [SyncedTask], pending: [PendingChange], results: [SyncResult] = []) {
        let pendingCreates = Set(pending.filter { $0.error == nil && $0.command.action["type"] == "task.create" }.compactMap { $0.command.action["taskId"]?.string })
        let remoteIds = Set(tasks.map(\.id)).union(pendingCreates)
        let removed = items.filter { !remoteIds.contains($0.id.uuidString.lowercased()) }
        for item in removed { context.delete(item) }
        let removedIds = Set(removed.map(\.id))
        items.removeAll { removedIds.contains($0.id) }
        for task in tasks {
            guard let id = UUID(uuidString: task.id) else { continue }
            let item = items.first { $0.id == id } ?? TodoItem(title: task.title, sortOrder: task.sortOrder)
            if !items.contains(where: { $0.id == id }) { item.id = id; context.insert(item); items.append(item) }
            item.title = task.title
            item.isCompleted = task.status == "done"
            item.parentID = task.parentTaskId.flatMap(UUID.init(uuidString:))
            item.dueDate = task.dueDate
            item.notes = task.notes
            item.desktopUpdatedAt = task.updatedAt
            item.isDemo = false
            item.sortOrder = task.parentTaskId == nil ? -task.sortOrder : task.sortOrder
        }
        // Rebuild the optimistic view from the durable outbox, including after an app restart.
        for change in pending where change.error == nil {
            let action = change.command.action
            let id = action["taskId"]?.string.flatMap(UUID.init(uuidString:))
            switch action["type"]?.string {
            case "task.review":
                guard action["action"] == "accept",
                      let taskID = change.taskID ?? results.first(where: { $0.id == action["resultId"]?.string })?.taskId,
                      let item = items.first(where: { $0.id.uuidString.lowercased() == taskID }) else { continue }
                if !item.isCompleted {
                    item.sortOrder = (sortedItems(completed: true, parentID: item.parentID).first?.sortOrder ?? 0) - 1
                    item.isCompleted = true
                }
            case "task.create":
                guard let id, case .object(let input) = action["input"], !items.contains(where: { $0.id == id }) else { continue }
                let parentID = input["parentTaskId"]?.string.flatMap(UUID.init(uuidString:))
                let item = TodoItem(title: input["title"]?.string ?? "", sortOrder: nextOrder(completed: false, parentID: parentID))
                item.id = id
                if parentID == nil { item.sortOrder = (active.first?.sortOrder ?? 0) - 1 }
                item.parentID = parentID
                item.dueDate = input["dueDate"]?.string
                item.notes = input["notes"]?.string
                context.insert(item)
                items.append(item)
            case "task.update":
                guard let item = items.first(where: { $0.id == id }), case .object(let patch) = action["patch"] else { continue }
                if let title = patch["title"]?.string { item.title = title }
                if patch["dueDate"] != nil { item.dueDate = patch["dueDate"]?.string }
                if patch["notes"] != nil { item.notes = patch["notes"]?.string }
                if let status = patch["status"]?.string {
                    let completed = status == "done"
                    if completed != item.isCompleted {
                        item.sortOrder = completed ? (sortedItems(completed: true, parentID: item.parentID).first?.sortOrder ?? 0) - 1 : nextOrder(completed: false, parentID: item.parentID)
                    }
                    item.isCompleted = completed
                }
            case "task.delete", "chat.archive":
                guard let id = change.taskID.flatMap(UUID.init(uuidString:)) else { continue }
                let removed = items.filter { $0.id == id || $0.parentID == id }
                for item in removed { context.delete(item) }
                let removedIds = Set(removed.map(\.id))
                items.removeAll { removedIds.contains($0.id) }
            case "task.reorder":
                guard case .object(let input) = action["input"], case .array(let ids) = input["taskIds"] else { continue }
                for (order, value) in ids.enumerated() {
                    if let item = items.first(where: { $0.id.uuidString.lowercased() == value.string }) { item.sortOrder = item.parentID == nil ? -order : order }
                }
            default: continue
            }
        }
        save()
    }

    private struct LocalTask: Codable {
        let id: UUID; let title: String; let completed: Bool; let order: Int
        let parentID: UUID?; let dueDate: String?; let notes: String?; let demo: Bool
    }
    func backupLocalTasks(to url: URL) throws {
        let backup = items.map { LocalTask(id: $0.id, title: $0.title, completed: $0.isCompleted, order: $0.sortOrder, parentID: $0.parentID, dueDate: $0.dueDate, notes: $0.notes, demo: $0.isDemo) }
        try JSONEncoder().encode(backup).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func restoreLocalTasks(from url: URL) throws {
        let backup = try JSONDecoder().decode([LocalTask].self, from: Data(contentsOf: url))
        for item in items { context.delete(item) }
        items = backup.map { task in
            let item = TodoItem(title: task.title, sortOrder: task.order, isCompleted: task.completed)
            item.id = task.id; item.parentID = task.parentID; item.dueDate = task.dueDate; item.notes = task.notes; item.isDemo = task.demo
            context.insert(item); return item
        }
        try context.save()
    }

    private func sortedItems(completed: Bool, parentID: UUID? = nil) -> [TodoItem] {
        items.filter { $0.isCompleted == completed && $0.parentID == parentID }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func nextOrder(completed: Bool, parentID: UUID? = nil) -> Int {
        (sortedItems(completed: completed, parentID: parentID).last?.sortOrder ?? -1) + 1
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try context.save()
            errorMessage = nil
            return true
        } catch {
            context.rollback()
            do {
                items = try context.fetch(FetchDescriptor<TodoItem>())
            } catch {
                items = []
            }
            errorMessage = "Your last change could not be saved. Please try again.\n\(error.localizedDescription)"
            return false
        }
    }
}

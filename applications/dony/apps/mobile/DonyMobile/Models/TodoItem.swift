import Foundation
import SwiftData

@Model
final class TodoItem {
    var id: UUID
    var title: String
    var isCompleted: Bool
    var sortOrder: Int
    var parentID: UUID?
    var dueDate: String?
    var notes: String?
    var desktopUpdatedAt: String?
    var isDemo: Bool = false

    init(title: String, sortOrder: Int, isCompleted: Bool = false) {
        self.id = UUID()
        self.title = title
        self.sortOrder = sortOrder
        self.isCompleted = isCompleted
    }
}

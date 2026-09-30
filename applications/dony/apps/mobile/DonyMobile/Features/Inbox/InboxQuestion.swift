import Foundation

struct InboxQuestion: Identifiable {
    let question: SyncQuestion
    let title: String
    let agent: DemoAgent
    var taskId: String? = nil
    var id: String { question.id }
}

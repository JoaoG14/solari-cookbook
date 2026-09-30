import SwiftUI

struct TodoRow: View {
    @Environment(CompanionStore.self) private var companion
    @Environment(DemoChatStore.self) private var chats
    @State private var expandedThread: SyncedThread?
    let item: TodoItem
    let toggle: () -> Void
    let edit: () -> Void
    var showsDueDate = true

    private var questionThread: SyncedThread? {
        item.isCompleted ? nil : companion.questionThread(for: item.id)
    }

    private var runningThread: SyncedThread? {
        companion.snapshot?.threads
            .filter { $0.taskId == item.id.uuidString.lowercased() && $0.archivedAt == nil && $0.status == "running" }
            .max { $0.updatedAt < $1.updatedAt }
    }

    private var isRunning: Bool {
        !item.isCompleted && questionThread == nil && (runningThread != nil || companion.task(item.id)?.proactiveExecutionStatus == "running")
    }

    private var reviewResults: [SyncResult] {
        item.isCompleted ? [] : companion.results(item.id).filter { companion.isAwaitingReview($0) }
    }

    private var taskThread: SyncedThread? {
        questionThread ?? runningThread ?? companion.taskThread(for: item.id)
    }

    private var dueDateDescription: String {
        guard let dueDate = item.dueDate else { return "" }
        let prefix = dueDate < TodoDueDate.key(.now) && !item.isCompleted ? "Overdue" : "Due"
        return "\(prefix) \(TodoDueDate.label(dueDate))"
    }

    private var showsDateBadge: Bool {
        guard showsDueDate else { return false }
        if item.isCompleted { return true }
        if isRunning || questionThread != nil || !reviewResults.isEmpty { return false }
        if companion.pendingSuggestion(item.id.uuidString.lowercased()) != nil { return false }
        if companion.isPending(item.id) && !companion.serverOnline { return false }
        guard let task = companion.task(item.id) else { return true }
        return !task.proactiveSuggestionPending
            && task.proactiveQuestion == nil
            && !["pending", "failed"].contains(task.proactivePlanningStatus ?? "")
            && !["running", "queued", "blocked", "failed"].contains(task.proactiveExecutionStatus ?? "")
    }

    private func openTask() {
        if let thread = taskThread {
            expandedThread = thread
        } else {
            edit()
        }
    }

    var body: some View {
        Group {
            if let thread = questionThread {
                Button { expandedThread = thread } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 1) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(Color("TodoQuiet"))
                                .frame(width: 44, height: 44)
                                .accessibilityHidden(true)
                            titleLabel
                        }
                        HStack(spacing: 8) {
                            Text("Answer questions")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(Color(red: 1, green: 165 / 255, blue: 0), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.leading, 45)
                        .overlay(alignment: .topLeading) {
                            Path { path in
                                path.move(to: CGPoint(x: 22, y: 2))
                                path.addLine(to: CGPoint(x: 22, y: 12))
                                path.addQuadCurve(to: CGPoint(x: 27, y: 17), control: CGPoint(x: 22, y: 17))
                                path.addLine(to: CGPoint(x: 35, y: 17))
                            }
                            .stroke(Color("TodoQuiet"), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .accessibilityHidden(true)
                        }
                    }
                    .padding(.bottom, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Answer questions for \(item.title)")
                .accessibilityValue(dueDateDescription)
                .accessibilityHint("Opens this task’s chat")
                .accessibilityIdentifier("answer-questions-\(item.id.uuidString.lowercased())")
            } else if isRunning {
                Button(action: openTask) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 1) {
                            // The stroke extends one point beyond the path: 20 + 2 = the 22pt checkbox.
                            AgentWorkingIndicator(size: 20)
                                .frame(width: 44, height: 44)
                            titleLabel
                        }
                        TaskRunningRow(
                            agent: chats.agents.first {
                                $0.id == (runningThread?.agentId ?? companion.task(item.id)?.proactiveAssignedAgentId)
                            },
                            activity: runningThread?.activity ?? "Working…"
                        )
                    }
                    .padding(.bottom, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Expand \(item.title) agent work")
                .accessibilityValue([runningThread?.activity ?? "Working…", dueDateDescription].filter { !$0.isEmpty }.joined(separator: ", "))
                .accessibilityIdentifier("running-task-\(item.id.uuidString.lowercased())")
            } else if !reviewResults.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 1) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color("TodoQuiet"))
                            .frame(width: 44, height: 44)
                            .accessibilityLabel("Ready for review")
                        Button(action: openTask) { titleLabel }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Review \(item.title)")
                            .accessibilityValue(dueDateDescription)
                            .accessibilityHint(taskThread == nil ? "Opens task details" : "Opens this task’s chat")
                    }
                    if let result = reviewResults.first {
                        TaskOutputReviewView(result: result, outputs: reviewResults.filter { !$0.artifacts.isEmpty })
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    editableRow
                    if !item.isCompleted, let task = companion.task(item.id), task.proactiveSuggestionPending,
                       companion.pendingSuggestion(task.id) == nil {
                        suggestionRow(task)
                    }
                }
            }
        }
        .sheet(item: $expandedThread) { thread in
            NavigationStack {
                ChatDetailView(conversationID: thread.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", systemImage: "xmark") { expandedThread = nil }
                        }
                    }
            }
        }
    }

    private var editableRow: some View {
        HStack(alignment: .top, spacing: 1) {
            Button(action: toggle) {
                TodoCompletionMark(isCompleted: item.isCompleted)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(item.isCompleted ? "Reopen" : "Complete") \(item.title)")
            .accessibilityValue(item.isCompleted ? "Completed" : "Active")

            Button(action: openTask) {
                titleLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(taskThread == nil ? "Edit" : "Open chat for") \(item.title)")
            .accessibilityValue(dueDateDescription)
        }
        .accessibilityElement(children: .contain)
    }

    private func suggestionRow(_ task: SyncedTask) -> some View {
        HStack(spacing: 0) {
            Button {
                companion.suggestion(task, action: "accept")
            } label: {
                HStack(spacing: 6) {
                    Image("ModeSuggestion")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                    Text(task.proactiveSuggestionLabel ?? "Do with AI")
                        .multilineTextAlignment(.leading)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    chats.agents.first { $0.id == task.proactiveAssignedAgentId }?.color
                        ?? Color(red: 163 / 255, green: 85 / 255, blue: 1),
                    in: Capsule()
                )
                .frame(minHeight: 44, alignment: .top)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("accept-suggestion-\(task.id)")

            Button {
                companion.suggestion(task, action: "dismiss")
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color("TodoQuiet"))
                    .frame(width: 44, height: 32)
                    .frame(minHeight: 44, alignment: .top)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss suggestion for \(item.title)")
            .accessibilityIdentifier("dismiss-suggestion-\(task.id)")
        }
        .padding(.leading, 45)
        .overlay(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: 22, y: 2))
                path.addLine(to: CGPoint(x: 22, y: 11))
                path.addQuadCurve(to: CGPoint(x: 27, y: 16), control: CGPoint(x: 22, y: 16))
                path.addLine(to: CGPoint(x: 35, y: 16))
            }
            .stroke(Color("TodoQuiet"), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .padding(.bottom, 8)
    }

    private var titleLabel: some View {
        TodoRowLabel(title: item.title, isCompleted: item.isCompleted, isSubtask: item.parentID != nil) {
            if showsDateBadge, let dueDate = item.dueDate {
                TodoDueDateBadge(dueDate: dueDate, isCompleted: item.isCompleted)
            } else if !isRunning && questionThread == nil && reviewResults.isEmpty {
                TaskAgentStatus(item: item)
            }
        }
    }
}

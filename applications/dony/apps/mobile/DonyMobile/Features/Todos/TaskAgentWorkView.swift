import SwiftUI

struct TaskRunningStatus: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let agent: DemoAgent?
    let activity: String

    var body: some View {
        HStack(spacing: 8) {
            if let agent { AgentAvatar(agent: agent, size: 22) }
            Text(activity)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color("TodoMuted"))
                .lineLimit(1)
                .overlay {
                    if !reduceMotion {
                        GeometryReader { geometry in
                            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: scenePhase != .active)) { context in
                                let progress = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2
                                LinearGradient(colors: [.clear, Color("TodoInk").opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: geometry.size.width)
                                    .offset(x: geometry.size.width * (progress * 3 - 1.5))
                            }
                        }
                        .mask(Text(activity).font(.caption.weight(.medium)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Image("TaskExpand")
                    .resizable()
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
                Text("Expand")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color("TodoMuted"))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color("TodoMuted").opacity(0.1), in: Capsule())
            .fixedSize()
        }
    }
}

struct TaskAgentStatus: View {
    @Environment(CompanionStore.self) private var companion
    let item: TodoItem
    var body: some View {
        if !item.isCompleted && companion.pendingSuggestion(item.id.uuidString.lowercased()) == nil {
            if companion.isPending(item.id) && !companion.serverOnline {
                if companion.connectionError == nil {
                    ProgressView("Updating…")
                        .font(.caption).foregroundStyle(Color("TodoMuted"))
                }
            } else if let task = companion.task(item.id) {
                HStack(spacing: 6) {
                    if task.proactiveExecutionStatus == "running" || task.proactivePlanningStatus == "pending" {
                        AgentWorkingIndicator(size: 10)
                        Text(
                            task.proactiveExecutionStatus == "running" ? "Working…" : "Thinking about this task…")
                    } else if task.proactiveQuestion != nil || task.proactiveExecutionStatus == "blocked" {
                        Image(systemName: "questionmark.bubble")
                        Text("Needs your input")
                    } else if companion.results(item.id).contains(where: { companion.isAwaitingReview($0) }) {
                        Image(systemName: "checkmark.bubble")
                        Text("Ready for review")
                    } else if task.proactiveExecutionStatus == "queued" {
                        AgentWorkingIndicator(size: 10)
                        Text("Starting…")
                    } else if task.proactiveExecutionStatus == "failed"
                        || task.proactivePlanningStatus == "failed"
                    {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle")
                            Text("Needs attention")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(red: 1, green: 165 / 255, blue: 0), in: Capsule())
                    }
                }
                .font(.caption).foregroundStyle(Color("TodoMuted"))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct TaskAgentWorkView: View {
    @Environment(CompanionStore.self) private var companion
    let item: TodoItem

    var body: some View {
        if let task = companion.task(item.id) {
            VStack(alignment: .leading, spacing: 16) {
                TaskAgentStatus(item: item)
                if companion.isCloud {
                    ForEach(companion.snapshot?.threads.filter { $0.taskId == task.id && $0.executionTarget == "cloud" && $0.status == "running" } ?? []) { thread in
                        CloudBrowserButton(threadID: thread.id)
                    }
                }
                if let notes = task.notes, !notes.isEmpty {
                    Text(.init(notes)).font(.subheadline).textSelection(.enabled)
                }
                if task.proactivePlanningStatus == "failed", companion.pendingSuggestion(task.id) == nil {
                    Button("Try again") { companion.suggestion(task, action: "retry") }
                }
                if let question = task.proactiveQuestion {
                    AgentQuestionView(question: question, taskId: task.id).id(question.id)
                }
                ForEach(
                    companion.snapshot?.threads.filter { $0.taskId == task.id && $0.question != nil } ?? []
                ) { thread in
                    if let question = thread.question {
                        AgentQuestionView(question: question).id(question.id)
                    }
                }
                ForEach(companion.results(item.id)) { result in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(!item.isCompleted && companion.isAwaitingReview(result) ? "Ready for review" : "Agent result").font(.headline)
                        Text(.init(result.preview)).font(.subheadline).textSelection(.enabled)
                        if result.outcome != "review" || item.isCompleted {
                            ForEach(Array(result.artifacts.enumerated()), id: \.offset) { index, artifact in
                                if let link = artifact.url, let url = URL(string: link), url.scheme == "https" {
                                    Link(artifact.name, destination: url)
                                } else {
                                    Button(artifact.name, systemImage: "doc") {
                                        companion.openArtifact(result, index: index)
                                    }
                                }
                            }
                        }
                    }.padding(16).background(
                        .primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }
}

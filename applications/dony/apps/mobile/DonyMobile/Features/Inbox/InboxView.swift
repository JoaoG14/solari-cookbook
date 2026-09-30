import SwiftUI

struct InboxView: View {
    @Environment(CompanionStore.self) private var companion
    @Environment(DemoChatStore.self) private var chats
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedResult: SyncResult?
    @State private var showingDone = false

    private var secondaryInk: Color { Color("TodoInk").opacity(0.65) }
    private var showsClearButton: Bool { showingDone && !companion.inboxResults.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                filter("Pending", count: companion.inboxPendingCount, done: false)
                filter("Done", count: companion.inboxResults.count, done: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)


            ZStack {
                inboxList(done: false)
                    .opacity(showingDone ? 0 : 1)
                    .disabled(showingDone)
                    .allowsHitTesting(!showingDone)
                    .accessibilityHidden(showingDone)
                inboxList(done: true)
                    .opacity(showingDone ? 1 : 0)
                    .allowsHitTesting(showingDone)
                    .accessibilityHidden(!showingDone)
            }
        }
        .background(Color("TodoSurface"))
        .foregroundStyle(Color("TodoInk"))
        .tint(Color("TodoInk"))
        .tabTitle("Inbox")
        .toolbar {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) { clearButton }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) { clearButton }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: companion.inboxResults.map(\.id))
        .navigationDestination(isPresented: Binding(
            get: { selectedResult != nil },
            set: { if !$0 { selectedResult = nil } }
        )) {
            if let result = selectedResult {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        agentHeader(agent(for: result), subtitle: title(for: result))
                        Text(.init(result.preview))
                            .font(.body)
                            .textSelection(.enabled)
                        InboxArtifacts(result: result)
                        if chats.conversation(id: result.threadId) != nil {
                            NavigationLink {
                                ChatDetailView(conversationID: result.threadId)
                            } label: {
                                Label("Open conversation", systemImage: "bubble.left")
                                    .frame(minHeight: 44)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                }
                .background(Color("TodoSurface"))
                .navigationTitle("Result")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
            }
        }
    }

    private var clearButton: some View {
        Button("Clear") { companion.clearInboxResults() }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .opacity(showsClearButton ? 1 : 0)
            .disabled(!showsClearButton)
            .accessibilityHidden(!showsClearButton)
            .accessibilityLabel("Clear done items")
            .accessibilityIdentifier("inbox-clear-done")
    }

    private func inboxList(done: Bool) -> some View {
        List {
            Group {
                if done {
                    ForEach(companion.inboxResults) { result in
                        resultCard(result)
                            .swipeActions {
                                Button("Dismiss", systemImage: "checkmark") {
                                    companion.dismissInboxResult(result)
                                }
                                .tint(secondaryInk)
                                .disabled(companion.hasPending(result.id))
                                .accessibilityIdentifier("inbox-dismiss-\(result.id)")
                            }
                            .accessibilityAction(named: "Dismiss") { companion.dismissInboxResult(result) }
                    }
                } else {
                    ForEach(companion.inboxQuestions) { question in
                        questionCard(question)
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .overlay {
            if done ? companion.inboxResults.isEmpty : companion.inboxQuestions.isEmpty {
                GeometryReader { geometry in
                    ScrollView {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: geometry.size.height)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: showingDone ? "checkmark" : "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(secondaryInk)
                .frame(width: 72, height: 72)
                .background(Color("TodoInk").opacity(0.04), in: Circle())
                .accessibilityHidden(true)
            Text(showingDone ? "Nothing here yet" : "You’re all caught up")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(companion.isConnected
                 ? showingDone ? "Finished work will be waiting here." : "When an agent needs you, you’ll find it here."
                 : "Sign in to see questions and finished work from your agents.")
                .font(.subheadline)
                .foregroundStyle(secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 280)
            if !companion.isConnected {
                Button { companion.showingCloudSignIn = true } label: {
                    Text("Sign in to Dony")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-empty")
    }

    private func filter(_ title: String, count: Int, done: Bool) -> some View {
        let selected = showingDone == done
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 7))
        return Button { showingDone = done } label: {
            VStack(spacing: 0) {
                layout {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text("\(count)")
                        .font(.caption.weight(.medium).monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color("TodoInk").opacity(0.06), in: Capsule())
                }
                .foregroundStyle(selected ? Color("TodoInk") : secondaryInk)
                .padding(.vertical, 14)
                Capsule()
                    .fill(selected ? Color("TodoInk") : .clear)
                    .frame(height: 2)
            }
            .fixedSize(horizontal: true, vertical: false)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue("\(count) items")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(done ? "inbox-filter-done" : "inbox-filter-pending")
    }

    private func agentHeader(_ agent: DemoAgent, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AgentAvatar(agent: agent, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(subtitle).font(.headline)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                Text(agent.name)
                    .font(.subheadline)
                    .foregroundStyle(secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func questionCard(_ pending: InboxQuestion) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            agentHeader(pending.agent, subtitle: pending.title)
            AgentQuestionView(question: pending.question, taskId: pending.taskId, embedded: true)
                .id(pending.id)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-question-\(pending.id)")
    }

    private func resultCard(_ result: SyncResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 0) {
                agentHeader(agent(for: result), subtitle: title(for: result))
                Button { companion.dismissInboxResult(result) } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryInk)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(companion.hasPending(result.id))
                .accessibilityLabel("Dismiss \(title(for: result))")
                .accessibilityIdentifier("inbox-dismiss-\(result.id)")
                .padding(.trailing, -10)
                .padding(.top, -8)
            }
            Text(.init(result.preview.isEmpty ? "Done." : result.preview))
                .font(.subheadline)
                .foregroundStyle(secondaryInk)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 4)
            InboxArtifacts(result: result, limit: 3)
            HStack {
                if let completedAt = result.completedAt {
                    Text(syncDate(completedAt), style: .relative)
                        .font(.caption)
                        .foregroundStyle(secondaryInk)
                }
                Spacer(minLength: 8)
                Button { selectedResult = result } label: {
                    Text("Read more")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("inbox-read-\(result.id)")
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inbox-result-\(result.id)")
    }

    private func title(for result: SyncResult) -> String {
        result.taskTitle ?? companion.snapshot?.tasks.first { $0.id == result.taskId }?.title ?? "Finished work"
    }

    private func agent(for result: SyncResult) -> DemoAgent {
        let agentID = result.agentId ?? companion.thread(result.threadId)?.agentId
        let agent = companion.snapshot?.agents.first { $0.id == agentID }
        return DemoAgent(id: agentID ?? result.id, name: result.agentName ?? agent?.name ?? "Agent",
                         colorHex: result.agentColor ?? agent?.color ?? "2080FB", description: "")
    }
}

private struct InboxArtifacts: View {
    @Environment(CompanionStore.self) private var companion
    let result: SyncResult
    var limit = Int.max

    var body: some View {
        ForEach(Array(result.artifacts.prefix(limit).enumerated()), id: \.offset) { index, artifact in
            Group {
                if let link = artifact.url, let url = URL(string: link), url.scheme == "https" {
                    Link(destination: url) { label(artifact, opening: false) }
                } else {
                    Button { companion.openArtifact(result, index: index) } label: {
                        label(artifact, opening: companion.isOpeningArtifact(result, index: index))
                    }
                    .disabled(companion.hasPending(result.id))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(artifact.name)")
            .accessibilityIdentifier("inbox-artifact-\(result.id)-\(index)")
        }
    }

    private func label(_ artifact: SyncResult.Artifact, opening: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: artifact.type == "link" ? "link" : "doc.text")
            Text(artifact.name).lineLimit(2).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if opening { ProgressView().controlSize(.small) }
            else { Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)) }
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .background(Color("TodoInk").opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}

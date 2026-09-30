import SwiftUI

/// An isolated illustration using the same row components as the real to-do list.
struct OnboardingTaskDemo: View {
    let suspended: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var stageHeight = 338
    @State private var taskIDs = [-2, -1, 0, 1, 2]
    @State private var exampleIndex = 0
    @State private var phase = 0
    @State private var entered = false

    private var example: WelcomeTaskExample { WelcomeTaskExample.all[exampleIndex % WelcomeTaskExample.all.count] }
    private var staticDemo: Bool { reduceMotion || voiceOver }
    private var currentPhase: Int { staticDemo ? 8 : phase }
    private var completedCount: Int { min(max(0, currentPhase - 4), 3) }
    private var finished: Bool { currentPhase >= 8 }
    private var running: Bool { currentPhase > 0 && !finished }
    private var visibleSubtasks: Range<Int> {
        let shown = min(max(0, currentPhase - 1), 3)
        let removed = min(max(0, (currentPhase - 9) / 2), shown)
        return 0..<(shown - removed)
    }
    private var agentIndex: Int { min(max(0, currentPhase - 4), 2) }
    private var playing: Bool { !suspended && !staticDemo && scenePhase == .active }
    private var spring: Animation { .spring(response: 0.58, dampingFraction: 0.78) }
    private var exitAnimation: Animation { .easeOut(duration: 0.15) }
    private var rowEntrance: AnyTransition {
        staticDemo ? .opacity : .asymmetric(
            insertion: .modifier(active: DemoRowEntrance(y: 14, scale: 0.97, blur: 3), identity: .identity),
            removal: .modifier(active: DemoRowEntrance(y: -8, scale: 0.98, blur: 2), identity: .identity)
        )
    }
    private var listRowTransition: AnyTransition {
        staticDemo ? .opacity : .asymmetric(
            insertion: .opacity,
            removal: .modifier(active: DemoRowEntrance(y: -12, scale: 0.98, blur: 2), identity: .identity)
                .animation(.easeOut(duration: 0.22))
        )
    }

    var body: some View {
        DemoTaskListLayout {
            ForEach(taskIDs, id: \.self) { id in
                taskRow(id)
                    .layoutValue(key: DemoTaskFocusKey.self, value: id == exampleIndex)
                    .transition(listRowTransition)
            }
        }
        .modifier(entered || staticDemo ? DemoRowEntrance.identity : DemoRowEntrance(y: 18, scale: 0.97, blur: 3))
        .frame(height: stageHeight)
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.14),
                .init(color: .black, location: 0.86),
                .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
        .padding(.leading, -11)
        .environment(\.scenePhase, playing ? .active : .inactive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example task: \(example.title). Dony agents work through three subtasks for you.")
        .accessibilityValue(finished ? "Completed" : "\(completedCount) of 3 subtasks completed")
        .accessibilityIdentifier("welcome-task-example")
        .onAppear { withAnimation(staticDemo ? nil : spring) { entered = true } }
        .task(id: Playback(example: exampleIndex, playing: playing)) { await animateExample() }
    }

    private func taskTitle(_ id: Int) -> String {
        switch id {
        case -2: "Pick a movie for tonight"
        case -1: "Find a birthday gift for Alex"
        default: WelcomeTaskExample.all[id % WelcomeTaskExample.all.count].title
        }
    }

    private func taskRow(_ id: Int) -> some View {
        let focused = id == exampleIndex
        let working = focused && running
        let completed = focused && finished
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 1) {
                ZStack {
                    if working {
                        AgentWorkingIndicator(size: 20)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    } else {
                        completionMark(done: completed)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                }
                .frame(width: 44, height: 44)
                TodoRowLabel(title: taskTitle(id), isCompleted: completed, isSubtask: false) { }
                    .lineLimit(focused ? nil : 1)
            }
            .background {
                if focused && (!visibleSubtasks.isEmpty || running) {
                    GeometryReader { geometry in
                        Path { path in
                            path.move(to: CGPoint(x: 22, y: 36))
                            path.addLine(to: CGPoint(x: 22, y: geometry.size.height))
                        }
                        .trim(from: 0, to: currentPhase >= 14 ? 0 : 1)
                        .stroke(Color("TodoQuiet"), lineWidth: 2)
                        .animation(staticDemo ? nil : .easeOut(duration: 0.09), value: currentPhase >= 14)
                    }
                }
            }

            ForEach(focused ? visibleSubtasks : 0..<0, id: \.self) { index in
                let dismissing = currentPhase >= 10 + (2 - index) * 2
                HStack(alignment: .top, spacing: 1) {
                    completionMark(done: index < completedCount)
                        .frame(width: 44, height: 44)
                    TodoRowLabel(title: example.subtasks[index], isCompleted: index < completedCount, isSubtask: true) { }
                }
                .padding(.leading, 28)
                .opacity(dismissing ? 0 : 1)
                .blur(radius: dismissing && !staticDemo ? 2 : 0)
                .animation(staticDemo ? nil : .easeOut(duration: 0.08).delay(0.02), value: dismissing)
                .scaleEffect(dismissing && !staticDemo ? 0.98 : 1, anchor: .leading)
                .offset(y: dismissing && !staticDemo ? -12 : 0)
                .background {
                    subtaskConnector(continues: index < visibleSubtasks.upperBound - 1 || running, dismissing: dismissing)
                }
                .transition(rowEntrance)
            }

            if focused && currentPhase > 0 && currentPhase < 9 && !staticDemo {
                ZStack {
                    TaskRunningRow(agent: example.agents[agentIndex], activity: currentPhase >= 7 ? "Finishing up…" : example.activities[agentIndex], isDismissing: finished)
                        .id(agentIndex)
                        .transition(rowEntrance)
                }
                .padding(.bottom, 8)
                .animation(exitAnimation, value: finished)
                .transition(rowEntrance)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(focused ? 1 : 0.55)
        .allowsHitTesting(false)
    }

    private func subtaskConnector(continues: Bool, dismissing: Bool) -> some View {
        GeometryReader { geometry in
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 22, y: -4))
                    path.addLine(to: CGPoint(x: 22, y: 17))
                    path.addQuadCurve(to: CGPoint(x: 27, y: 22), control: CGPoint(x: 22, y: 22))
                    path.addLine(to: CGPoint(x: 35, y: 22))
                }
                .trim(from: 0, to: dismissing ? 0 : 1)
                .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .animation(staticDemo ? nil : .easeOut(duration: 0.09), value: dismissing)

                Path { path in
                    path.move(to: CGPoint(x: 22, y: 17))
                    path.addLine(to: CGPoint(x: 22, y: geometry.size.height))
                }
                .trim(from: 0, to: continues && !dismissing ? 1 : 0)
                .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .animation(staticDemo ? nil : .easeOut(duration: 0.11), value: continues && !dismissing)
            }
            .foregroundStyle(Color("TodoQuiet"))
        }
    }

    private func completionMark(done: Bool) -> some View {
        TodoCompletionMark(isCompleted: done)
            .keyframeAnimator(initialValue: CGFloat(1), trigger: done && !staticDemo) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                CubicKeyframe(1.2, duration: 0.12)
                CubicKeyframe(0.94, duration: 0.12)
                CubicKeyframe(1, duration: 0.2)
            }
    }

    private func nextExample() {
        withAnimation(staticDemo ? nil : spring) {
            taskIDs.removeAll { $0 == exampleIndex }
            exampleIndex += 1
            taskIDs.append(exampleIndex + 2)
            phase = 0
        }
    }

    private func animateExample() async {
        guard playing else { return }
        // Close the agent's space, then lift and fade subtasks from bottom to top.
        let holds = [1.0, 1.0, 0.24, 0.24, 1.45, 1.5, 1.45, 1.15, 0.17, 0.45, 0.12, 0.14, 0.12, 0.14, 0.12, 0.16]
        do {
            while phase < holds.count {
                try await Task.sleep(for: .seconds(holds[phase]))
                if phase == holds.count - 1 {
                    nextExample()
                    return
                }
                let nextPhase = phase + 1
                let fadingSubtask = nextPhase >= 10 && nextPhase.isMultiple(of: 2)
                let animation: Animation
                if fadingSubtask {
                    animation = .easeOut(duration: 0.11)
                } else if nextPhase >= 11 {
                    animation = .easeOut(duration: 0.13)
                } else {
                    animation = nextPhase >= 9 ? exitAnimation : spring
                }
                withAnimation(animation) { phase = nextPhase }
            }
        } catch { /* Pausing or swapping examples cancels this sequence. */ }
    }

    private struct Playback: Equatable {
        let example: Int
        let playing: Bool
    }
}

private struct DemoTaskFocusKey: LayoutValueKey {
    static let defaultValue = false
}

/// Keeps the active row centered while the same neighboring views slide around it.
private struct DemoTaskListLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let focused = subviews.firstIndex(where: { $0[DemoTaskFocusKey.self] }) else { return }
        let rowProposal = ProposedViewSize(width: bounds.width, height: nil)
        let heights = subviews.map { $0.sizeThatFits(rowProposal).height }
        let precedingHeight = heights.prefix(focused).reduce(0) { $0 + $1 + 6 }
        var y = bounds.midY - heights[focused] / 2 - precedingHeight

        for index in subviews.indices {
            subviews[index].place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                                  proposal: ProposedViewSize(width: bounds.width, height: heights[index]))
            y += heights[index] + 6
        }
    }
}

private struct DemoRowEntrance: ViewModifier {
    let y: CGFloat
    let scale: CGFloat
    let blur: CGFloat
    static let identity = Self(y: 0, scale: 1, blur: 0)

    func body(content: Content) -> some View {
        content
            .opacity(blur == 0 ? 1 : 0)
            .blur(radius: blur)
            .scaleEffect(scale, anchor: .leading)
            .offset(y: y)
    }
}

private struct WelcomeTaskExample {
    let title: String
    let subtasks: [String]
    let activities: [String]
    let agents: [DemoAgent]

    private static let sunny = DemoAgent(id: "sunny", name: "Sunny", colorHex: "FFAF38", description: "Planning")
    private static let fern = DemoAgent(id: "fern", name: "Fern", colorHex: "63D6A1", description: "Everyday life")
    private static let nova = DemoAgent(id: "nova", name: "Nova", colorHex: "B49AFA", description: "Research")
    private static let blue = DemoAgent(id: "blue", name: "Blue", colorHex: "79B9F8", description: "Writing")
    private static let peach = DemoAgent(id: "peach", name: "Peach", colorHex: "F995AF", description: "Ideas")

    static let all: [Self] = [
        .init(title: "Plan a weekend in Lisbon", subtasks: ["Find a cozy place to stay", "Map the little local spots", "Make room for pastéis"],
              activities: ["Finding your kind of places…", "Taking the scenic route…", "Saving the best for last…"],
              agents: [sunny, nova, peach]),
        .init(title: "Sort out next week’s lunches", subtasks: ["Find five easy recipes", "Build the grocery list", "Plan a Sunday prep session"],
              activities: ["Planning easy lunches…", "Checking the ingredients…", "Putting it all together…"],
              agents: [fern, sunny, blue]),
        .init(title: "Find my next headphones", subtasks: ["Compare the best options", "Check what people love", "Shortlist three good picks"],
              activities: ["Going down the rabbit hole…", "Reading the reviews…", "Finding your perfect match…"],
              agents: [nova, blue, fern]),
        .init(title: "Plan a birthday for Sam", subtasks: ["Dream up a few gift ideas", "Find a great cake recipe", "Draft a little invitation"],
              activities: ["Finding a thoughtful gift…", "Making it a little sweeter…", "Finding just the right words…"],
              agents: [peach, fern, blue]),
        .init(title: "Turn my notes into an update", subtasks: ["Pull out the highlights", "Write a clear first draft", "Polish the final details"],
              activities: ["Making sense of the scribbles…", "Connecting the dots…", "One last little polish…"],
              agents: [blue, nova, sunny]),
        .init(title: "Get ready for Friday’s exam", subtasks: ["Break down the big topics", "Make a set of flashcards", "Put together a practice quiz"],
              activities: ["Taking it one topic at a time…", "Making the tricky bits stick…", "Putting together a quiz…"],
              agents: [nova, peach, fern])
    ]
}

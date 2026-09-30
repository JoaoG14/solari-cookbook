import SwiftUI

struct ChatThinkingPicker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: ChatThinking
    let agentColor: Color
    @State private var dragPosition: CGFloat?

    private var lastIndex: Int { ChatThinking.allCases.count - 1 }
    private var isInteracting: Bool { dragPosition != nil }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 5) {
                Text(selection.title)
                    .font(.headline)
                    .contentTransition(.numericText())
                Text(selection.detail)
                    .font(.caption)
                    .foregroundStyle(Color("TodoMuted"))
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }
            .accessibilityHidden(true)

            GeometryReader { geometry in
                let inset: CGFloat = 26
                let travel = max(1, geometry.size.width - inset * 2)
                let position = dragPosition ?? CGFloat(selection.index) / CGFloat(lastIndex)
                let thumbX = inset + position * travel

                ZStack(alignment: .leading) {
                    Capsule().fill(Color("TodoInk").opacity(0.05))
                    Capsule()
                        .fill(agentColor)
                        .frame(width: thumbX + 26)

                    ForEach(ChatThinking.allCases) { option in
                        Circle()
                            .fill(option.index <= selection.index ? Color.white.opacity(0.4) : Color("TodoInk").opacity(0.25))
                            .frame(width: 10, height: 10)
                            .position(x: inset + CGFloat(option.index) / CGFloat(lastIndex) * travel, y: geometry.size.height / 2)
                    }

                    Circle()
                        .fill(.white)
                        .overlay { Circle().strokeBorder(agentColor, lineWidth: 3) }
                        .frame(width: 44, height: 44)
                        .position(x: thumbX, y: geometry.size.height / 2)
                }
                .contentShape(Capsule())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let position = min(1, max(0, (value.location.x - inset) / travel))
                            dragPosition = position
                            let next = ChatThinking.allCases[Int((position * CGFloat(lastIndex)).rounded())]
                            if next != selection { selection = next }
                        }
                        .onEnded { _ in
                            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86)) {
                                dragPosition = nil
                            }
                        }
                )
            }
            .frame(height: 52)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Thinking level")
            .accessibilityValue("\(selection.title). \(selection.detail)")
            .accessibilityHint("Swipe up or down to change how much thought goes into your reply.")
            .accessibilityAdjustableAction { direction in
                let index = selection.index + (direction == .increment ? 1 : -1)
                selection = ChatThinking.allCases[min(lastIndex, max(0, index))]
            }
            .accessibilityIdentifier("chat-thinking-slider")
        }
        .foregroundStyle(Color("TodoInk"))
        .sensoryFeedback(.selection, trigger: selection)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: isInteracting) { _, isInteracting in
            isInteracting
        }
    }
}

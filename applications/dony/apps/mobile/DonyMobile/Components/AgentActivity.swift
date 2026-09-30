import SwiftUI

struct AgentWorkingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var size: CGFloat = 12

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) {
            context in
            Circle()
                .stroke(Color("TodoMuted").opacity(0.3), lineWidth: 2)
                .overlay {
                    Circle().trim(from: 0, to: 0.3)
                        .stroke(Color("TodoInk"), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(
                            .degrees(
                                reduceMotion
                                    ? -90
                                    : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(
                                        dividingBy: 0.8) / 0.8 * 360))
                }
                .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}

struct AgentStatusAvatar: View {
    let agent: DemoAgent
    var size: CGFloat = 48
    var working = false
    var instanceNumber: Int?
    var needsAttention = false

    var body: some View {
        AgentAvatar(agent: agent, size: size)
            .overlay(alignment: .bottomLeading) {
                if let instanceNumber {
                    Text(instanceNumber, format: .number)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color("TodoSurface"))
                        .padding(.horizontal, 4)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Color("TodoInk"), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color("TodoSurface"), lineWidth: 2))
                        .offset(x: -4, y: 4)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if working {
                    AgentWorkingIndicator()
                        .frame(width: 20, height: 20)
                        .background(Color("TodoSurface"), in: Circle())
                        .offset(x: 4, y: 4)
                }
            }
            .overlay(alignment: .topTrailing) {
                if needsAttention {
                    Text("!").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 19, height: 19).background(.red, in: Circle())
                        .overlay(Circle().stroke(Color("TodoSurface"), lineWidth: 2)).offset(x: 4, y: -4)
                }
            }
            .accessibilityHidden(true)
    }
}

struct CompanionStatusView: View {
    @Environment(CompanionStore.self) private var companion
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(
                companion.desktopOnline && companion.serverOnline ? Color("TodoAccent") : Color("TodoMuted")
            ).frame(width: 6, height: 6)
            Text(companion.statusText).font(.caption).foregroundStyle(Color("TodoMuted"))
        }
        .accessibilityElement(children: .combine)
    }
}

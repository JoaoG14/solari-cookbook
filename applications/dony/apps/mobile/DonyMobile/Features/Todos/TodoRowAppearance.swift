import SwiftUI

// Shared with the welcome demo so its tasks use the app's actual row appearance.
struct TodoCompletionMark: View {
    let isCompleted: Bool

    var body: some View {
        Circle()
            .fill(isCompleted ? Color("TodoAccent") : .clear)
            .overlay {
                Circle().strokeBorder(Color(isCompleted ? "TodoAccent" : "TodoQuiet"), lineWidth: 2)
            }
            .overlay {
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color("TodoSurface"))
                }
            }
            .frame(width: 22, height: 22)
    }
}

struct TodoRowLabel<Detail: View>: View {
    let title: String
    let isCompleted: Bool
    let isSubtask: Bool
    @ViewBuilder var detail: Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TodoTitleText(title: title)
                .font(.system(isSubtask ? .subheadline : .body, weight: .medium))
                .tracking(-0.16)
                .multilineTextAlignment(.leading)
                .strikethrough(isCompleted, color: Color("TodoQuiet"))
                .foregroundStyle(Color(isCompleted ? "TodoMuted" : "TodoInk"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            detail
        }
        .padding(.top, 11)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct TaskRunningRow: View {
    let agent: DemoAgent?
    let activity: String
    var isDismissing = false

    var body: some View {
        TaskRunningStatus(agent: agent, activity: activity)
            .opacity(isDismissing ? 0 : 1)
            .padding(.leading, 11)
            .background {
                GeometryReader { geometry in
                    Path { path in
                        path.move(to: CGPoint(x: 22, y: -12))
                        // End four points above the centered 22pt avatar.
                        path.addLine(to: CGPoint(x: 22, y: (geometry.size.height - 22) / 2 - 4))
                    }
                    .trim(from: 0, to: isDismissing ? 0 : 1)
                    .stroke(Color("TodoQuiet"), lineWidth: 2)
                    .animation(.easeOut(duration: 0.25), value: isDismissing)
                }
                .allowsHitTesting(false)
            }
            .padding(.top, 8)
    }
}

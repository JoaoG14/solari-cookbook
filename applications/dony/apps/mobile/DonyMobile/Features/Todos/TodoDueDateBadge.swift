import SwiftUI

struct TodoDueDateBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let dueDate: String
    let isCompleted: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let today = TodoDueDate.key(context.date)
            let overdue = dueDate < today && !isCompleted
            let label = TodoDueDate.label(dueDate, now: context.date)
            let tint = color(today: today, label: label)
            let background = dueDate == today && !isCompleted
                ? Color(red: 1, green: 0.80, blue: 0.20)
                : tint.opacity(colorScheme == .dark ? 0.16 : 0.09)

            HStack(spacing: 4) {
                Image(systemName: overdue ? "clock.arrow.circlepath" : dueDate == today ? "sun.max.fill" : "calendar")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
                Text(TodoDueDate.compactLabel(dueDate, now: context.date))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(overdue ? "Overdue" : "Due") \(label)")
            .accessibilityIdentifier("todo-due-date")
        }
    }

    private func color(today: String, label: String) -> Color {
        let neutral = colorScheme == .dark ? Color("TodoInk").opacity(0.65) : Color("TodoMuted")
        if isCompleted { return neutral }
        if dueDate < today {
            return colorScheme == .dark
                ? Color(red: 1, green: 0.57, blue: 0.51)
                : Color(red: 0.72, green: 0.22, blue: 0.17)
        }
        if dueDate == today {
            return Color(red: 0.30, green: 0.19, blue: 0)
        }
        if label == "Tomorrow" {
            return colorScheme == .dark
                ? Color(red: 0.48, green: 0.72, blue: 1)
                : Color(red: 0.16, green: 0.39, blue: 0.73)
        }
        return neutral
    }
}

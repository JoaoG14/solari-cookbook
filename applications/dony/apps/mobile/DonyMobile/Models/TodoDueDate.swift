import Foundation

// Store a calendar date, not an instant, so traveling never changes the due day.
enum TodoDueDate {
    static func key(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    static func date(_ key: String, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    }

    static func label(_ key: String, now: Date = .now) -> String {
        let calendar = Calendar(identifier: .gregorian)
        if key == self.key(now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), key == self.key(tomorrow) {
            return "Tomorrow"
        }
        return date(key).formatted(date: .abbreviated, time: .omitted)
    }

    static func compactLabel(_ key: String, now: Date = .now) -> String {
        let label = label(key, now: now)
        if label == "Today" || label == "Tomorrow" { return label }
        let date = date(key)
        let calendar = Calendar(identifier: .gregorian)
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
            return label
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

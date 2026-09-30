import Foundation
import Observation

@MainActor
@Observable
final class MobileOnboarding {
    static let completedKey = "mobileOnboardingCompleted"
    private let defaults: UserDefaults

    var completed: Bool { didSet { defaults.set(completed, forKey: Self.completedKey) } }
    var step: Int { didSet { defaults.set(step, forKey: "mobileOnboardingStep") } }
    var tasks: [FirstTask] { didSet { persistTasks() } }

    struct FirstTask: Codable, Identifiable {
        let id: UUID
        let title: String
        var selected = false
        var emailSubject: String? = nil
        var notes: String? = nil

        var sourceLabel: String? {
            switch title {
            case "List recurring paid subscriptions", "Unsubscribe from promotional emails":
                return "Uses email"
            case "Find upcoming renewals and deadlines", "Prep for next external meeting":
                return "Uses email & calendar"
            default:
                return emailSubject == nil ? nil : "Uses email"
            }
        }
    }

    // Evaluate this before TodoStore records its first launch. Existing installations
    // retain their workspace and don't acquire a new sign-in gate after updating.
    static func prepare(defaults: UserDefaults, bypass: Bool = false) {
        if bypass {
            defaults.set(true, forKey: completedKey)
        } else if defaults.object(forKey: completedKey) == nil {
            defaults.set(defaults.bool(forKey: "hasSeededTodos"), forKey: completedKey)
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        completed = defaults.bool(forKey: Self.completedKey)
        step = defaults.object(forKey: "mobileOnboardingStep") == nil
            ? -1 : min(max(defaults.integer(forKey: "mobileOnboardingStep"), -1), 4)
        if let data = defaults.data(forKey: "mobileOnboardingTasks"),
           let saved = try? JSONDecoder().decode([FirstTask].self, from: data) {
            if defaults.bool(forKey: "mobileOnboardingBrowserTasks") {
                tasks = saved
            } else {
                let oldExamples = ["Draft a project update", "Prepare a meeting agenda", "Research a topic",
                    "List recurring paid subscriptions", "Find upcoming renewals and deadlines",
                    "Prep for next external meeting", "Unsubscribe from promotional emails"]
                let retained = saved.filter { $0.selected || ($0.emailSubject == nil && !oldExamples.contains($0.title)) }
                tasks = Self.defaultTasks.filter { task in !retained.contains { $0.title == task.title } } + retained
                defaults.set(step, forKey: "mobileOnboardingStep")
            }
        } else {
            tasks = Self.defaultTasks
        }
        defaults.set(true, forKey: "mobileOnboardingBrowserTasks")
        persistTasks()
    }

    private static var defaultTasks: [FirstTask] {
        [
            FirstTask(id: UUID(), title: "Research solar energy",
                notes: "Use the cloud browser to read https://en.wikipedia.org/wiki/Solar_energy, follow a relevant link, and summarize three facts with source links."),
            FirstTask(id: UUID(), title: "Compare browser automation tools",
                notes: "Use the cloud browser to visit the official Playwright and Selenium websites. Compare their main features and include source links."),
            FirstTask(id: UUID(), title: "Plan a weekend in Lisbon",
                notes: "Use the cloud browser to research Lisbon attractions on public travel websites. Suggest a two-day itinerary with source links. Do not make bookings."),
            FirstTask(id: UUID(), title: "Explore the history of the web",
                notes: "Use the cloud browser to research the history of the World Wide Web. Summarize key milestones with source links.")
        ]
    }

    @discardableResult
    func finish(todos: TodoStore, empty: Bool = false) -> Bool {
        if !empty {
            for task in tasks where task.selected {
                // Stable IDs let a retry or relaunch finish a partially saved list.
                guard todos.add(task.title, dueDate: nil, parent: nil, id: task.id, notes: task.notes) != nil else { return false }
            }
        }
        completed = true
        return true
    }

    private func persistTasks() {
        defaults.set(try? JSONEncoder().encode(tasks), forKey: "mobileOnboardingTasks")
    }
}

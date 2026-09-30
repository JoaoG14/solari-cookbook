import Foundation

enum ChatThinking: String, CaseIterable, Identifiable {
    case quick, everyday, balanced, thorough, deep

    var id: String { rawValue }
    var title: String {
        switch self {
        case .thorough: "Smart"
        case .deep: "Expert"
        default: rawValue.capitalized
        }
    }
    var index: Int { Self.allCases.firstIndex(of: self)! }

    var detail: String {
        switch self {
        case .quick: "Fast help with simple questions"
        case .everyday: "A little more thought for daily tasks"
        case .balanced: "A balance of speed and thinking"
        case .thorough: "Careful thinking for complex tasks"
        case .deep: "The most thinking for your hardest tasks"
        }
    }
}

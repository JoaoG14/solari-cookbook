import SwiftUI

struct DemoAgent: Identifiable, Equatable {
    let id: String
    let name: String
    let colorHex: String
    let description: String
    var color: Color {
        let hex = colorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let rgb = UInt64(hex, radix: 16), hex.count == 6 else { return Color("TodoAccent") }
        return Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
    var faceColor: Color {
        let hex = colorHex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let rgb = UInt64(hex, radix: 16), hex.count == 6 else { return .black.opacity(0.8) }
        let channels = [16, 8, 0].map { shift -> Double in
            let channel = Double((rgb >> shift) & 255) / 255
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        return luminance <= 0.179 ? .white : .black.opacity(0.8)
    }
    static let atlas = DemoAgent(id: "atlas", name: "Atlas", colorHex: "2080FB", description: "Planning & writing")
    static let mira = DemoAgent(id: "mira", name: "Mira", colorHex: "A96B01", description: "Research & ideas")
    static let pixel = DemoAgent(id: "pixel", name: "Pixel", colorHex: "FF9F2E", description: "Design & code")
    static let allCases = [atlas, mira, pixel]
}

struct DemoMessage: Identifiable {
    enum Role { case user, assistant }
    enum Block {
        case text(String)
        case bullets([String])
        case code(String)
        case result(title: String, detail: String)
        case file(DemoAttachment)
    }

    let id: String
    let role: Role
    let blocks: [Block]
    let createdAt: Date
    let questionAnswer: SyncAnsweredQuestion?

    init(id: String = UUID().uuidString, role: Role, blocks: [Block], createdAt: Date = .now, questionAnswer: SyncAnsweredQuestion? = nil) {
        self.id = id
        self.role = role
        self.blocks = blocks
        self.createdAt = createdAt
        self.questionAnswer = questionAnswer
    }

    var preview: String {
        guard let first = blocks.first else { return "" }
        switch first {
        case .text(let text): return text
        case .bullets(let items): return items.joined(separator: ", ")
        case .code: return "Code example"
        case .result(let title, _): return title
        case .file(let file): return file.name
        }
    }

    var searchableText: String {
        if let questionAnswer {
            return ([questionAnswer.header] + questionAnswer.answers.map { "\($0.question)\n\($0.answer)" }).joined(separator: "\n")
        }
        return blocks.map { block in
            switch block {
            case .text(let text), .code(let text): return text
            case .bullets(let items): return items.joined(separator: "\n")
            case .result(let title, let detail): return "\(title)\n\(detail)"
            case .file(let file): return file.name
            }
        }.joined(separator: "\n")
    }
}

struct DemoConversation: Identifiable {
    enum Status { case ready, running, failed, blocked, waiting }

    let id: String
    let agent: DemoAgent
    var title: String
    var messages: [DemoMessage]
    var status: Status = .ready
    var isArchived = false
    var createdAt = Date.now
    var updatedAt = Date.now
    var instanceNumber: Int?
    var activity: String?
    var viewedAt: Date?
    var sidebarExpiresAt: Date?

    var preview: String {
        switch status {
        case .running: return activity ?? "Working…"
        case .failed: return "This response was interrupted."
        case .blocked: return "Needs your input"
        case .waiting: return "Sending…"
        case .ready: return messages.last?.preview ?? "Start with a message."
        }
    }
}

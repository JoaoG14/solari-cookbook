import Foundation

// JSON command payloads are persisted exactly as sent, including their idempotency ID.
indirect enum SyncValue: Codable, Equatable, ExpressibleByStringLiteral {
    case string(String)
    case number(Int)
    case bool(Bool)
    case array([SyncValue])
    case object([String: SyncValue])
    case null
    init(stringLiteral value: String) { self = .string(value) }
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            self = .null
        } else if let object = try? value.decode([String: SyncValue].self) {
            self = .object(object)
        } else if let array = try? value.decode([SyncValue].self) {
            self = .array(array)
        } else if let string = try? value.decode(String.self) {
            self = .string(string)
        } else if let bool = try? value.decode(Bool.self) {
            self = .bool(bool)
        } else {
            self = .number(try value.decode(Int.self))
        }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let string): try value.encode(string)
        case .number(let number): try value.encode(number)
        case .bool(let bool): try value.encode(bool)
        case .array(let array): try value.encode(array)
        case .object(let object): try value.encode(object)
        case .null: try value.encodeNil()
        }
    }
    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }
    static func optional(_ value: String?) -> SyncValue { value.map(SyncValue.string) ?? .null }
}

struct SyncFile: Codable {
    let name: String
    let base64: String
    let mimeType: String
    init(_ attachment: DemoAttachment) throws {
        let data = try Data(contentsOf: attachment.url)
        guard data.count <= 20 * 1024 * 1024 else {
            throw CompanionFailure("Files must be 20 MB or smaller.")
        }
        name = attachment.name
        base64 = data.base64EncodedString()
        mimeType = "application/octet-stream"
    }
    var payload: SyncValue {
        .object(["name": .string(name), "base64": .string(base64), "mimeType": .string(mimeType)])
    }
}
struct SyncCommand: Codable, Identifiable {
    let id: String
    var action: [String: SyncValue]
    var executionTarget: String? = nil
}
struct PendingChange: Codable, Identifiable {
    var command: SyncCommand
    var dependsOn: String?
    var submitted = false
    var error: String?
    var relatedTaskID: String? = nil
    var id: String { command.id }
    var taskID: String? { command.action["taskId"]?.string ?? relatedTaskID }
    var target: String {
        command.action["taskId"]?.string ?? command.action["threadId"]?.string ?? command.action["resultId"]?
            .string ?? command.action["questionId"]?.string ?? command.action["type"]?.string ?? ""
    }
    var title: String {
        command.action["type"]?.string?.replacingOccurrences(of: ".", with: " ").capitalized ?? "Change"
    }
}
struct SyncReceipt: Codable {
    let id: String
    let status: String
    let error: String?
    let file: SyncFile?
    let taskVersions: [String: TaskVersion]?
    struct TaskVersion: Codable {
        let before: String?
        let after: String
    }
}
struct SyncedTask: Codable, Identifiable {
    let id: String
    let title: String
    let status: String
    let parentTaskId: String?
    let sortOrder: Int
    let notes: String?
    let dueDate: String?
    let updatedAt: String
    let proactivePlanningStatus: String?
    let proactiveSuggestionPending: Bool
    let proactiveSuggestionLabel: String?
    let proactiveExecutionStatus: String?
    let proactiveAssignedAgentId: String?
    let proactiveQuestion: SyncQuestion?
}
struct SyncedAgent: Codable, Identifiable {
    let id: String
    let name: String
    let emoji: String
    let color: String
    let instructions: String
    let welcomeMessage: String?
    let modelOverride: String?
}
struct SyncedMessage: Codable, Identifiable {
    let id: String
    let role: String
    let content: String
    let status: String
    let createdAt: String
    var questionAnswer: SyncAnsweredQuestion? = nil
}

struct SyncAnsweredQuestion: Codable, Identifiable {
    let id: String
    let header: String
    let answers: [Answer]

    struct Answer: Codable {
        let question: String
        let answer: String
    }

    init?(question: SyncQuestion, response: SyncValue) {
        guard case .object(let response) = response,
              response["action"]?.string == "accept",
              case .array(let values) = response["answers"] else { return nil }
        id = question.id
        header = question.header
        answers = values.compactMap { value in
            guard case .object(let value) = value,
                  let item = question.questions.first(where: { $0.id == value["questionId"]?.string }) else { return nil }
            if let text = value["customText"]?.string {
                return Answer(question: item.question, answer: text)
            }
            let selected: [String]
            if let option = value["selectedOptionId"]?.string { selected = [option] }
            else if case .array(let options) = value["selectedOptionIds"] { selected = options.compactMap(\.string) }
            else { return nil }
            let labels = selected.compactMap { id in item.options.first { $0.id == id }?.label }
            return Answer(question: item.question, answer: labels.joined(separator: ", "))
        }
    }
}
struct SyncedThread: Codable, Identifiable {
    let id: String
    let agentId: String
    let origin: String
    let taskId: String?
    let title: String
    var createdAt: String? = nil
    let updatedAt: String
    let archivedAt: String?
    let messages: [SyncedMessage]
    let runId: String?
    var executionTarget: String? = nil
    let status: String
    let activity: String?
    let instanceNumber: Int?
    let viewedAt: String?
    let sidebarExpiresAt: String?
    let question: SyncQuestion?
}
struct SyncQuestion: Codable, Identifiable {
    let id: String
    let header: String
    let question: String
    let questions: [Item]
    struct Item: Codable, Identifiable {
        let id: String
        let header: String?
        let question: String
        let options: [Option]
        let allowCustomAnswer: Bool
        let multiple: Bool
        let responseKind: String?
    }
    struct Option: Codable, Identifiable {
        let id: String
        let label: String
        let description: String?
    }
}
struct SyncResult: Codable, Identifiable {
    let id: String
    let taskId: String
    let threadId: String
    var assistantMessageId: String? = nil
    let preview: String
    let outcome: String?
    let artifacts: [Artifact]
    var taskTitle: String? = nil
    var agentId: String? = nil
    var agentName: String? = nil
    var agentColor: String? = nil
    var completedAt: String? = nil
    var dismissedAt: String? = nil
    struct Artifact: Codable {
        let name: String
        let type: String
        let url: String?
    }
}
struct SyncSnapshot: Codable {
    let version: Int
    let mode: String
    let tasks: [SyncedTask]
    let agents: [SyncedAgent]
    let threads: [SyncedThread]
    let results: [SyncResult]
}
struct CompanionConnection: Codable {
    let server: URL
    var token: String
    let deviceId: String
    let desktopId: String
    let desktopName: String
    let accountId: String
    var certificateFingerprint: String? = nil
    var transport: String? = nil
    var pairedDesktop: PairedDesktop? = nil
    var isCloud: Bool { transport == "cloud" }
    var isLocal: Bool { certificateFingerprint != nil }
}
struct PairedDesktop: Codable {
    let server: URL
    let token: String
    let deviceId: String
    let desktopId: String
    let desktopName: String
    let accountId: String
    let certificateFingerprint: String?
    init(_ connection: CompanionConnection) {
        server = connection.server; token = connection.token; deviceId = connection.deviceId
        desktopId = connection.desktopId; desktopName = connection.desktopName
        accountId = connection.accountId; certificateFingerprint = connection.certificateFingerprint
    }
}
struct CloudAccount: Codable {
    let id: String
    let name: String?
    let email: String?
}
struct CloudAccountStatus: Decodable {
    var billing: BillingStatus? = nil
    let workspaceId: String
    let pro: Bool
    let executionTarget: String
    let dailyLimitUsd: Double
    let dailySpentUsd: Double
    let resetsAt: String
    let configured: Bool
}
struct CompanionFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
func syncDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) ?? .distantPast
}

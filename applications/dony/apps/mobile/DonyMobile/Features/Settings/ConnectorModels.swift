import Foundation

struct MobileConnectorsStatus: Decodable {
    let enabled: Bool
    let disabledReason: String?
    let toolkits: [MobileConnector]
}

struct MobileConnector: Decodable, Identifiable {
    let slug: String
    let name: String
    let description: String
    let group: String
    let logoUrl: URL?
    let isConnected: Bool
    let status: String
    let connectedAccountId: String?
    var id: String { slug }
    var isPaused: Bool { status.uppercased() == "INACTIVE" }
    var isPending: Bool { ["INITIALIZING", "INITIATED"].contains(status.uppercased()) }
    var statusLabel: String {
        if isConnected { return "Connected" }
        if isPaused { return "Paused" }
        if isPending { return "Awaiting authorization" }
        if connectedAccountId != nil { return "Needs attention" }
        return group
    }
}

struct ConnectorAuthorization: Decodable, Identifiable {
    let url: URL?
    var id: String { url?.absoluteString ?? "" }
}

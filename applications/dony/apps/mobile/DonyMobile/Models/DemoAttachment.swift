import Foundation

struct DemoAttachment: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let url: URL

    init(importing source: URL) throws {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        name = source.lastPathComponent
        let directory = URL.temporaryDirectory.appending(path: id.uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: name)
        do {
            try FileManager.default.copyItem(at: source, to: url)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func removeLocalCopy() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

import XCTest
@testable import DonyMobile

@MainActor
final class DemoChatStoreTests: XCTestCase {
    func testAttachmentsAreCopiedAndCanBeSentWithoutText() async throws {
        let source = URL.temporaryDirectory.appending(path: "\(UUID().uuidString)-brief.txt")
        let content = Data("A local project brief".utf8)
        try content.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let file = try DemoAttachment(importing: source)
        defer { file.removeLocalCopy() }
        XCTAssertNotEqual(file.url, source)
        XCTAssertEqual(try Data(contentsOf: file.url), content)

        let store = DemoChatStore()
        store.send("  ", attachments: [file], to: "empty")
        let message = try XCTUnwrap(store.conversation(id: "empty")?.messages.first)
        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.preview, source.lastPathComponent)
        XCTAssertEqual(message.searchableText, source.lastPathComponent)
        guard case .file(let sentFile) = message.blocks.first else {
            return XCTFail("Expected an attached file")
        }
        XCTAssertEqual(try Data(contentsOf: sentFile.url), content)
        store.reset()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testSearchIncludesEveryMessageBlock() {
        let message = DemoMessage(role: .assistant, blocks: [
            .text("Overview"), .bullets(["First step", "Second step"]),
            .code("let greeting = hello"), .result(title: "Brief", detail: "Delivery Friday")
        ])
        for query in ["overview", "second step", "greeting", "brief", "delivery friday"] {
            XCTAssertTrue(message.searchableText.localizedStandardContains(query))
        }
    }

    func testFixturesCoverTheDemoStates() async {
        let store = DemoChatStore()
        XCTAssertEqual(DemoAgent.allCases.count, 3)
        XCTAssertEqual(store.recent.count, 6)
        XCTAssertEqual(Set(store.recent.map(\.id)).count, 6)
        XCTAssertTrue(store.recent.contains { $0.messages.isEmpty })
        XCTAssertTrue(store.recent.contains { $0.status == .running })
        XCTAssertTrue(store.recent.contains { $0.status == .failed })
        XCTAssertEqual(store.recent.map(\.id), DemoChatStore().recent.map(\.id))

        let blocks = store.recent.flatMap(\.messages).flatMap(\.blocks)
        XCTAssertTrue(blocks.contains { if case .code = $0 { return true }; return false })
        XCTAssertTrue(blocks.contains { if case .bullets = $0 { return true }; return false })
        XCTAssertTrue(blocks.contains { if case .result = $0 { return true }; return false })
    }

    func testSendingAppendsLocalMessagesAndMovesChatToTop() async throws {
        let store = DemoChatStore()
        store.send(" \n", to: "empty")
        XCTAssertTrue(try XCTUnwrap(store.conversation(id: "empty")).messages.isEmpty)

        store.send("  Review my plan  ", to: "empty")
        let chat = try XCTUnwrap(store.conversation(id: "empty"))
        XCTAssertEqual(store.recent.first?.id, "empty")
        XCTAssertEqual(chat.title, "Review my plan")
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(chat.messages.first?.role, .user)
        XCTAssertEqual(chat.messages.first?.preview, "Review my plan")
        XCTAssertEqual(chat.messages.last?.role, .assistant)
        XCTAssertTrue(chat.messages.last?.preview.contains("demo reply from Pixel") == true)

        store.send("Continue", to: "running")
        XCTAssertEqual(store.conversation(id: "running")?.status, .ready)
        store.send("Continue", to: "error")
        XCTAssertEqual(store.conversation(id: "error")?.status, .ready)
    }

    func testNewChatArchiveAndReset() async throws {
        let store = DemoChatStore()
        let id = store.createChat(agent: .mira)
        XCTAssertEqual(store.recent.count, 7)
        XCTAssertEqual(store.recent.first?.agent, .mira)
        XCTAssertTrue(try XCTUnwrap(store.conversation(id: id)).messages.isEmpty)

        store.archive(id)
        XCTAssertNil(store.conversation(id: id))
        store.send("Should not reopen", to: id)
        XCTAssertEqual(store.recent.count, 6)

        for chat in store.recent { store.archive(chat.id) }
        XCTAssertTrue(store.recent.isEmpty)
        store.reset()
        XCTAssertEqual(store.recent.count, 6)
        XCTAssertEqual(store.resetCount, 1)
        XCTAssertEqual(store.recent.map(\.id), DemoFixtures.conversations.map(\.id))
    }
}

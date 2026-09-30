import XCTest
@testable import DonyMobile

final class TodoAgentMentionTests: XCTestCase {
    func testTagsMatchDesktopFormat() {
        XCTAssertEqual(TodoAgentMention.tag(for: " General Assistant "), "@general-assistant")
        XCTAssertEqual(TodoAgentMention.tag(for: "Design & Code_2"), "@design-code-2")
        XCTAssertEqual(TodoAgentMention.tag(for: "João"), "@jo-o")
        XCTAssertEqual(TodoAgentMention.normalize("@General-Assistant"), "generalassistant")
    }

    func testQueryOnlyMatchesMentionAtCaret() throws {
        let text = "Write @at tomorrow"
        let query = try XCTUnwrap(TodoAgentMention.query(in: text, caret: 9))
        XCTAssertEqual(query.text, "at")
        XCTAssertEqual(query.range, NSRange(location: 6, length: 3))
        XCTAssertNil(TodoAgentMention.query(in: text, caret: text.utf16.count))
        XCTAssertNil(TodoAgentMention.query(in: "hello@example.com", caret: 13))
        XCTAssertNil(TodoAgentMention.query(in: "@atlas ", caret: 7))
        XCTAssertNil(TodoAgentMention.query(in: "@", caret: 2))
        XCTAssertEqual(TodoAgentMention.query(in: "@", caret: 1)?.text, "")
        XCTAssertEqual(TodoAgentMention.query(in: "Task\n@mi", caret: 8)?.text, "mi")
    }

    func testInsertionPreservesSurroundingTextAndReplacesWholeToken() throws {
        let text = "Write @atlas tomorrow"
        let query = try XCTUnwrap(TodoAgentMention.query(in: text, caret: 9))
        let result = TodoAgentMention.inserting("@mira", into: text, query: query)
        XCTAssertEqual(result.text, "Write @mira tomorrow")
        XCTAssertEqual(result.caret, 12)
        let continued = (result.text as NSString).replacingCharacters(in: NSRange(location: result.caret, length: 0), with: "first ")
        XCTAssertEqual(continued, "Write @mira first tomorrow")
    }

    func testInsertionHandlesEmojiAndMultipleMentions() throws {
        let text = "📋 @atlas ask @mi"
        let query = try XCTUnwrap(TodoAgentMention.query(in: text, caret: text.utf16.count))
        let result = TodoAgentMention.inserting("@mira", into: text, query: query)
        XCTAssertEqual(result.text, "📋 @atlas ask @mira ")
        XCTAssertEqual(result.caret, result.text.utf16.count)
        XCTAssertNil(TodoAgentMention.query(in: result.text, caret: result.caret))
    }

    func testOutdatedAndNonemptySelectionsAreIgnored() {
        let previous = "Review @atlas"
        let cursor = previous.endIndex..<previous.endIndex
        XCTAssertNil(TodoAgentMention.query(in: "", selection: cursor))
        XCTAssertNil(TodoAgentMention.query(in: "@", selection: cursor))
        XCTAssertNil(TodoAgentMention.query(in: previous, selection: previous.startIndex..<previous.endIndex))
        XCTAssertEqual(TodoAgentMention.query(in: previous, selection: cursor)?.text, "atlas")
    }
}

import XCTest

@MainActor
final class DonyMobileBrowserUITests: XCTestCase {
    private let app = XCUIApplication()
    private let server = URL(string: "http://127.0.0.1:18790")!

    private func request(_ path: String, method: String = "POST") async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: path, relativeTo: server)!)
        request.httpMethod = method
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func waitForBrowserPage(_ title: String, timeout: TimeInterval) -> Bool {
        let page = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", title),
            object: element("cloud-browser-image"))
        return XCTWaiter.wait(for: [page], timeout: timeout) == .completed
    }

    private func openEmployees() throws {
        let tab = app.tabBars.buttons["Employees"]
        guard tab.waitForExistence(timeout: 10) else {
            throw NSError(domain: "BrowserUITest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Employees tab did not appear"])
        }
        for _ in 0..<2 {
            tab.tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: tab)
            if XCTWaiter.wait(for: [selected], timeout: 3) == .completed { return }
        }
        throw NSError(domain: "BrowserUITest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Employees tab did not open"])
    }

    func testRepeatedLongRepliesKeepChatResponsive() async throws {
        continueAfterFailure = false
        let fixture = try await request("reset?chat=true")
        let threadID = try XCTUnwrap(fixture["threadId"] as? String)
        app.launchEnvironment["DONY_UI_CLOUD_WORKSPACE"] = fixture["workspaceId"] as? String
        app.launchArguments = ["--ui-testing", "--reset-todos", "--companion-testing", "--cloud-agent-testing"]
        app.launch()
        try openEmployees()
        XCTAssertTrue(element("chat-\(threadID)").waitForExistence(timeout: 15))
        element("chat-\(threadID)").tap()
        for index in 1...4 {
            let composer = element("chat-composer")
            XCTAssertTrue(composer.waitForExistence(timeout: 10))
            composer.tap()
            let details = String(repeating: "Compare solar cells, panels, and power systems with detailed explanations and source links. ", count: index == 3 ? 8 : 2)
            composer.typeText("Research request \(index). " + details)
            element("send-demo-message").tap()
            let reply = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Research reply \(index)")).firstMatch
            XCTAssertTrue(reply.waitForExistence(timeout: 20))
            XCTAssertTrue(element("search-chat-messages").isHittable)
            element("view-cloud-browser").tap()
            XCTAssertTrue(element("cloud-browser-inactive").waitForExistence(timeout: 10))
            app.buttons["Done"].tap()
            // Start the next send away from the bottom, as after reviewing earlier research.
            element("search-chat-messages").tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap()
            search.typeText("Research request 1")
            XCTAssertTrue(element("message-search-result").waitForExistence(timeout: 5))
            element("message-search-result").tap()
        }
        element("search-chat-messages").tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("Research request 3")
        XCTAssertTrue(element("message-search-result").waitForExistence(timeout: 5))
        element("message-search-result").tap()
        XCTAssertTrue(element("chat-composer").isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "four-completed-chat-turns"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testBrowserPreviewUpdatesRecoversAndEndsWithoutControls() async throws {
        continueAfterFailure = false
        let fixture = try await request("reset")
        let threadID = try XCTUnwrap(fixture["threadId"] as? String)
        app.launchEnvironment["DONY_UI_CLOUD_WORKSPACE"] = fixture["workspaceId"] as? String
        app.launchArguments = ["--ui-testing", "--reset-todos", "--companion-testing", "--cloud-agent-testing"]
        app.launch()
        try openEmployees()
        let chat = element("chat-\(threadID)")
        XCTAssertTrue(chat.waitForExistence(timeout: 15))
        chat.tap()
        XCTAssertTrue(element("view-cloud-browser").waitForExistence(timeout: 10))
        element("view-cloud-browser").tap()
        XCTAssertTrue(waitForBrowserPage("Preview first page", timeout: 30))
        XCTAssertTrue(element("cloud-browser-image").exists)
        let streamingBefore = try await request("stats", method: "GET")["frames"] as? Int ?? 0
        try await Task.sleep(for: .seconds(1))
        let streamingAfter = try await request("stats", method: "GET")["frames"] as? Int ?? 0
        XCTAssertGreaterThan(streamingAfter - streamingBefore, 2, "The preview must receive live frames between the old polling intervals")
        XCTAssertEqual(app.webViews.count, 0)
        XCTAssertTrue(app.textFields.allElementsBoundByIndex.allSatisfy { !$0.isHittable })
        XCTAssertFalse(app.buttons["Zoom in"].exists)
        XCTAssertFalse(app.staticTexts["Preview first page"].exists)
        _ = try await request("advance")
        XCTAssertTrue(waitForBrowserPage("Preview second page", timeout: 15))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "read-only-browser-preview"
        attachment.lifetime = .keepAlways
        add(attachment)
        _ = try await request("offline")
        XCTAssertTrue(element("cloud-browser-error").waitForExistence(timeout: 15))
        XCTAssertFalse(element("cloud-browser-image").exists)
        _ = try await request("online")
        XCTAssertTrue(waitForBrowserPage("Preview second page", timeout: 15))
        app.buttons["Done"].tap()
        try await Task.sleep(for: .seconds(1))
        let closedPreview = try await request("stats", method: "GET")
        XCTAssertEqual(closedPreview["streams"] as? Int, 0, "Dismissed previews must detach their screencast")
        let before = closedPreview["requests"] as? Int
        try await Task.sleep(for: .seconds(3))
        let after = try await request("stats", method: "GET")["requests"] as? Int
        XCTAssertEqual(before, after, "Dismissed previews must stop reconnecting")
        element("view-cloud-browser").tap()
        XCTAssertTrue(waitForBrowserPage("Preview second page", timeout: 15))
        _ = try await request("finish")
        XCTAssertTrue(element("cloud-browser-inactive").waitForExistence(timeout: 15))
        XCTAssertFalse(element("cloud-browser-image").exists)
        var closed = false
        for _ in 0..<20 {
            closed = try await request("stats", method: "GET")["closed"] as? Bool == true
            if closed { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        XCTAssertTrue(closed, "The completed run must release its browser")
    }
}

import XCTest

@MainActor
final class DonyMobileUITests: XCTestCase {
    private let app = XCUIApplication()

    private func launch(extraArguments: [String] = []) {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing", "--reset-todos"] + extraArguments
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Employees"].waitForExistence(timeout: 10))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func openChat(_ id: String) {
        let row = element("chat-\(id)")
        for _ in 0..<6 {
            if row.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(row.isHittable)
        row.tap()
    }

    private func openConnectorFixture(extraArguments: [String] = []) async throws {
        let server = URL(string: "http://127.0.0.1:18788")!
        let data: Data
        do { (data, _) = try await URLSession.shared.data(from: server.appending(path: "pair")) }
        catch { throw XCTSkip("Start tests/helpers/connectorMobileServer.ts for connector UI tests.") }
        let pairing = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        launch(extraArguments: ["--companion-testing"] + extraArguments)
        app.open(try XCTUnwrap(URL(string: try XCTUnwrap(pairing["url"]))))
        XCTAssertTrue(element("connect-desktop").waitForExistence(timeout: 5))
        app.switches["bring-todos-to-desktop"].tap()
        for _ in 0..<6 {
            if element("connect-desktop").isHittable { break }
            app.swipeUp()
        }
        element("connect-desktop").tap()
        await fulfillment(of: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"), object: app.tabBars.buttons["Settings"]
        )], timeout: 10)
        app.tabBars.buttons["Settings"].tap()
        for _ in 0..<6 {
            if element("settings-connectors").isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(element("settings-connectors").waitForExistence(timeout: 5))
        element("settings-connectors").tap()
        XCTAssertTrue(element("connector-gmail").waitForExistence(timeout: 20))
    }

    func testConnectorsAuthorizeSyncFilterAndDisconnect() async throws {
        try await openConnectorFixture()
        capture("connectors-light")
        let search = app.textFields["connectors-search"]
        search.tap()
        search.typeText("Figma")
        XCTAssertTrue(element("connector-figma").exists)
        XCTAssertFalse(element("connector-gmail").exists)
        app.buttons["Clear search"].tap()
        app.swipeDown()
        app.buttons["Connect Gmail"].tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))
        var complete = URLRequest(url: URL(string: "http://127.0.0.1:18788/complete")!)
        complete.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: complete)
        XCTAssertTrue(app.buttons["Manage Gmail"].waitForExistence(timeout: 20))
        app.buttons["Filter connectors"].tap()
        app.buttons["Connected"].tap()
        XCTAssertTrue(element("connector-gmail").exists)
        XCTAssertFalse(element("connector-notion").exists)
        capture("connectors-connected-filter")
        app.buttons["Manage Gmail"].tap()
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.staticTexts["No connected tools"].waitForExistence(timeout: 10))
        app.buttons["Filter connectors"].tap()
        app.buttons["All connectors"].tap()
        app.buttons["Manage Gmail"].tap()
        app.buttons["Resume"].tap()
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 10))
        app.buttons["Manage Gmail"].tap()
        app.buttons["Disconnect"].tap()
        app.buttons["Disconnect"].tap()
        XCTAssertTrue(app.buttons["Connect Gmail"].waitForExistence(timeout: 10))
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:18788/status")!)
        let status = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let gmail = try XCTUnwrap((status["toolkits"] as? [[String: Any]])?.first { $0["slug"] as? String == "gmail" })
        XCTAssertEqual(gmail["isConnected"] as? Bool, false)
        capture("connectors-logos")
    }

    func testConnectorsLargeText() async throws {
        try await openConnectorFixture(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["Connect Gmail"].isHittable)
        XCTAssertLessThanOrEqual(app.buttons["Connect Gmail"].frame.maxX, app.frame.maxX)
        capture("connectors-large-text")
    }

    func testConnectorsUnpairedGuidance() {
        launch()
        app.tabBars.buttons["Settings"].tap()
        element("settings-connectors").tap()
        XCTAssertTrue(app.staticTexts["Sign in to Dony"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Connect Gmail"].exists)
        app.buttons["Close connectors"].tap()
    }

    func testVoiceTaskEntryPointsRequireAnAccount() {
        launch()
        app.tabBars.buttons["To-do List"].tap()
        let add = element("add-todo")
        add.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Speak tasks"].waitForExistence(timeout: 3))
        app.buttons["Speak tasks"].tap()
        XCTAssertTrue(app.staticTexts["Sign in to Dony"].waitForExistence(timeout: 3))
        app.buttons["Close"].tap()
        add.tap()
        XCTAssertTrue(element("composer-voice-tasks").waitForExistence(timeout: 3))
    }

    private func toggleInboxInSettings() {
        app.tabBars.buttons["Settings"].tap()
        let toggle = app.switches["settings-inbox-enabled"]
        for _ in 0..<8 {
            if toggle.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(toggle.isHittable)
        toggle.switches.firstMatch.tap()
    }

    func testInboxTabRequiresOptInAndPersists() {
        launch()
        XCTAssertFalse(app.tabBars.buttons["Inbox"].exists)
        XCTAssertEqual(app.tabBars.buttons.count, 3)
        toggleInboxInSettings()
        XCTAssertTrue(app.tabBars.buttons["Inbox"].waitForExistence(timeout: 3))
        capture("settings-inbox-enabled")
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(element("inbox-empty").waitForExistence(timeout: 3))
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Inbox"].waitForExistence(timeout: 10))
        toggleInboxInSettings()
        XCTAssertFalse(app.tabBars.buttons["Inbox"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].isSelected)
        capture("settings-inbox-disabled")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Employees"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.buttons["Inbox"].exists)
    }

    func testInboxEmptyAndLargeText() {
        launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        toggleInboxInSettings()
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(element("inbox-empty").waitForExistence(timeout: 3))
        for _ in 0..<5 { if app.buttons["Sign in to Dony"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["Sign in to Dony"].isHittable)
        XCTAssertFalse(app.buttons["Connect desktop"].exists)
        capture("inbox-empty-large-text")
        app.buttons["Sign in to Dony"].tap()
        XCTAssertTrue(element("cloud-sign-in").waitForExistence(timeout: 3))
        XCTAssertFalse(element("use-connection-link").exists)
        app.buttons["Close"].tap()
    }

    func testSignedOutCloudEntryPointsAndComputerAtBottomOfSettings() {
        launch(extraArguments: ["--companion-testing"])
        XCTAssertTrue(app.buttons["Sign in to Dony"].exists)
        XCTAssertFalse(app.buttons["Connect desktop"].exists)
        capture("cloud-first-employees")
        app.buttons["Sign in to Dony"].tap()
        XCTAssertTrue(element("cloud-sign-in").waitForExistence(timeout: 3))
        app.buttons["Close"].tap()
        app.tabBars.buttons["To-do List"].tap()
        for mode in ["suggestion", "proactive"] {
            element("todo-mode-\(mode)").tap()
            XCTAssertTrue(element("paywall-close").waitForExistence(timeout: 5))
            element("paywall-close").tap()
            XCTAssertTrue(element("todo-mode-off").isSelected)
        }
        app.tabBars.buttons["Employees"].tap()
        element("new-chat").tap()
        XCTAssertTrue(element("paywall-close").waitForExistence(timeout: 5))
        element("paywall-close").tap()
        app.tabBars.buttons["Settings"].tap()
        capture("cloud-first-settings-top")
        for _ in 0..<6 { if app.buttons["Connect desktop"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["Connect desktop"].isHittable)
        XCTAssertFalse(app.staticTexts["Advanced"].exists)
        capture("cloud-first-settings-computer")
    }

    private func connectInboxFixture(extraArguments: [String] = []) async throws -> (server: URL, resultIDs: [String], questionID: String) {
        let server = URL(string: "http://127.0.0.1:18787")!
        let data: Data
        do { (data, _) = try await URLSession.shared.data(from: server.appending(path: "__test__/pair")) }
        catch { throw XCTSkip("Start tests/helpers/companionMobileServer.ts for the Inbox connection test.") }
        let pairing = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        let (inboxData, _) = try await URLSession.shared.data(from: server.appending(path: "__test__/inbox"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: inboxData) as? [String: Any])
        let resultIDs = try XCTUnwrap(fixture["resultIds"] as? [String])
        let questionID = try XCTUnwrap(fixture["questionId"] as? String)
        launch(extraArguments: ["--companion-testing"] + extraArguments)
        toggleInboxInSettings()
        app.tabBars.buttons["Inbox"].tap()
        app.open(try XCTUnwrap(URL(string: try XCTUnwrap(pairing["url"]))))
        XCTAssertTrue(element("connect-desktop").waitForExistence(timeout: 5))
        app.switches["bring-todos-to-desktop"].tap()
        element("connect-desktop").tap()
        app.tabBars.buttons["Inbox"].tap()
        let question = element("inbox-question-\(questionID)")
        XCTAssertTrue(question.waitForExistence(timeout: 15))
        return (server, resultIDs, questionID)
    }

    func testInboxFilePreview() async throws {
        let (_, resultIDs, _) = try await connectInboxFixture()
        element("inbox-filter-done").tap()
        let artifact = element("inbox-artifact-\(resultIDs[0])-0")
        for _ in 0..<5 { if artifact.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(artifact.isHittable)
        artifact.tap()
        XCTAssertTrue(element("QLOverlayDoneButtonAccessibilityIdentifier").waitForExistence(timeout: 15))
        capture("inbox-file-preview")
    }

    func testInboxRowsWithLargeText() async throws {
        let (_, resultIDs, questionID) = try await connectInboxFixture(extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        let done = element("inbox-filter-done")
        XCTAssertTrue(done.isHittable)
        XCTAssertLessThanOrEqual(done.frame.maxX, app.frame.maxX)
        XCTAssertTrue(element("inbox-question-\(questionID)").isHittable)
        capture("inbox-pending-large-text")
        done.tap()
        let read = element("inbox-read-\(resultIDs[0])")
        for _ in 0..<5 { if read.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(read.isHittable)
        capture("inbox-done-large-text")
        read.tap()
        XCTAssertTrue(app.navigationBars["Result"].waitForExistence(timeout: 3))
    }

    func testInboxSendsAllThreeAnswersOnlyAfterConfirmation() async throws {
        let (server, _, questionID) = try await connectInboxFixture()
        let question = element("inbox-question-\(questionID)")
        let custom = element("question-custom-answer")
        let next = element("question-continue")
        app.staticTexts["Which proposal should I review?"].tap()
        guard custom.waitForExistence(timeout: 3) else {
            XCTFail("Tapping question text must not decline the entire batch")
            return
        }
        custom.tap()
        custom.typeText("The proposal shared yesterday")
        for _ in 0..<5 { if next.isHittable { break }; app.swipeUp() }
        next.tap()
        XCTAssertTrue(element("question-option-focus-clarity").waitForExistence(timeout: 3))
        element("question-option-focus-clarity").tap()
        app.buttons["Previous question"].tap()
        XCTAssertEqual(custom.value as? String, "The proposal shared yesterday")
        next.tap()
        XCTAssertEqual(element("question-option-focus-clarity").value as? String, "Selected")
        next.tap()
        XCTAssertTrue(element("question-option-deadline-friday").waitForExistence(timeout: 3))
        element("question-option-deadline-friday").tap()
        let (beforeData, _) = try await URLSession.shared.data(from: server.appending(path: "__test__/answers"))
        let before = try XCTUnwrap(JSONSerialization.jsonObject(with: beforeData) as? [[String: Any]])
        XCTAssertFalse(before.contains { $0["questionId"] as? String == questionID })
        XCTAssertEqual(next.label, "Send answers")
        capture("inbox-three-questions-before-send")
        next.tap()
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: question)], timeout: 15)
        let (data, _) = try await URLSession.shared.data(from: server.appending(path: "__test__/answers"))
        let received = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let matching = received.filter { $0["questionId"] as? String == questionID }
        XCTAssertEqual(matching.count, 1)
        let response = try XCTUnwrap(matching.first?["response"] as? [String: Any])
        XCTAssertEqual(response["action"] as? String, "accept")
        let answers = try XCTUnwrap(response["answers"] as? [[String: Any]])
        XCTAssertEqual(answers.compactMap { $0["questionId"] as? String }, ["proposal", "focus", "deadline"])
        XCTAssertEqual(answers[0]["customText"] as? String, "The proposal shared yesterday")
        XCTAssertEqual(answers[1]["selectedOptionIds"] as? [String], ["clarity"])
        XCTAssertEqual(answers[2]["selectedOptionId"] as? String, "friday")
    }

    func testInboxDeclinesOnlyWhenDeclineIsTapped() async throws {
        let (server, _, questionID) = try await connectInboxFixture()
        let decline = app.buttons["Decline"]
        for _ in 0..<5 { if decline.isHittable { break }; app.swipeUp() }
        decline.tap()
        let question = element("inbox-question-\(questionID)")
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: question)], timeout: 15)
        let (data, _) = try await URLSession.shared.data(from: server.appending(path: "__test__/answers"))
        let received = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let matching = received.filter { $0["questionId"] as? String == questionID }
        XCTAssertEqual(matching.count, 1)
        let response = try XCTUnwrap(matching.first?["response"] as? [String: Any])
        XCTAssertEqual(response["action"] as? String, "decline")
    }

    func testInboxQuestionsResultsAndSyncedDismissal() async throws {
        let (server, resultIDs, questionID) = try await connectInboxFixture()
        let question = element("inbox-question-\(questionID)")
        XCTAssertTrue(element("inbox-filter-pending").isSelected)
        XCTAssertTrue(element("question-option-proposal-latest").exists)
        XCTAssertFalse(element("inbox-read-\(resultIDs[0])").isHittable)
        capture("inbox-pending-light")
        element("question-option-proposal-latest").tap()
        element("inbox-filter-done").tap()
        XCTAssertTrue(element("inbox-filter-done").isSelected)
        XCTAssertFalse(question.isHittable)
        XCTAssertTrue(element("inbox-result-\(resultIDs[0])").exists)
        capture("inbox-done-light")
        app.tabBars.buttons["Settings"].tap()
        element("appearance-picker").tap()
        app.buttons["Dark"].tap()
        app.tabBars.buttons["Inbox"].tap()
        capture("inbox-done-dark")
        element("inbox-filter-pending").tap()
        capture("inbox-pending-dark")
        XCTAssertTrue(element("question-option-proposal-latest").waitForExistence(timeout: 3))
        XCTAssertEqual(element("question-option-proposal-latest").value as? String, "Selected")
        for _ in 0..<5 { if element("question-continue").isHittable { break }; app.swipeUp() }
        element("question-continue").tap()
        for _ in 0..<5 { if element("question-option-focus-clarity").isHittable { break }; app.swipeDown() }
        element("question-option-focus-clarity").tap()
        for _ in 0..<5 { if element("question-continue").isHittable { break }; app.swipeUp() }
        element("question-continue").tap()
        element("question-option-deadline-friday").tap()
        element("question-continue").tap()
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: question)], timeout: 15)
        XCTAssertTrue(element("inbox-empty").exists)
        element("inbox-filter-done").tap()
        let read = element("inbox-read-\(resultIDs[0])")
        for _ in 0..<5 { if read.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(read.isHittable)
        read.tap()
        XCTAssertTrue(app.buttons["Open conversation"].waitForExistence(timeout: 3))
        capture("inbox-result-detail")
        app.buttons["Open conversation"].tap()
        XCTAssertTrue(element("chat-composer").waitForExistence(timeout: 3))
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        let dismiss = element("inbox-dismiss-\(resultIDs[0])")
        for _ in 0..<5 { if dismiss.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(dismiss.waitForExistence(timeout: 3))
        dismiss.tap()
        XCTAssertFalse(element("inbox-result-\(resultIDs[0])").exists)
        for _ in 0..<5 { if element("inbox-clear-done").isHittable { break }; app.swipeDown() }
        element("inbox-clear-done").tap()
        XCTAssertTrue(element("inbox-empty").waitForExistence(timeout: 5))
        capture("inbox-caught-up")
        var remaining = resultIDs
        for _ in 0..<15 {
            let (stateData, _) = try await URLSession.shared.data(from: server.appending(path: "__test__/snapshot"))
            let state = try XCTUnwrap(JSONSerialization.jsonObject(with: stateData) as? [String: Any])
            let results = try XCTUnwrap(state["results"] as? [[String: Any]])
            remaining = results.compactMap { $0["id"] as? String }.filter { resultIDs.contains($0) }
            if remaining.isEmpty { break }
            try await Task.sleep(for: .seconds(1))
        }
        XCTAssertTrue(remaining.isEmpty, "Dismiss and Clear must reach the desktop")
    }

    func testTodoActionsAndChatStayResponsiveWhileDesktopRequestsAreDelayed() async throws {
        let server = URL(string: "http://127.0.0.1:18788")!
        let data: Data
        do { (data, _) = try await URLSession.shared.data(from: server.appending(path: "__test__/pair")) }
        catch { throw XCTSkip("Start python3 tests/helpers/companionLatencyServer.py for the native latency test.") }
        let pairing = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        launch(extraArguments: ["--companion-testing"])
        app.tabBars.buttons["Settings"].tap()
        for _ in 0..<6 { if app.buttons["Connect desktop"].isHittable { break }; app.swipeUp() }
        app.buttons["Connect desktop"].tap()
        element("use-connection-link").tap()
        let link = element("companion-link")
        XCTAssertTrue(link.waitForExistence(timeout: 3))
        link.tap()
        link.typeText(try XCTUnwrap(pairing["url"]))
        element("connect-desktop").tap()
        XCTAssertTrue(app.buttons["Disconnect desktop"].waitForExistence(timeout: 15))
        app.tabBars.buttons["To-do List"].tap()
        let suggestion = element("accept-suggestion-00000000-0000-4000-8000-000000000010")
        let review = element("accept-output-latency-review")
        let openResponse = element("open-result-message-latency-review")
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        XCTAssertFalse(review.exists)
        XCTAssertFalse(element("change-output-latency-review").exists)
        XCTAssertTrue(openResponse.exists)
        app.buttons["Open chat for Prepare the launch brief"].tap()
        XCTAssertTrue(element("chat-composer").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Prepare the launch brief using the project notes."].exists)
        XCTAssertFalse(element("task-detail").exists)
        app.buttons["Close"].tap()
        app.buttons["Review Review the proposal"].tap()
        XCTAssertTrue(element("chat-composer").waitForExistence(timeout: 5))
        XCTAssertFalse(element("task-detail").exists)
        app.buttons["Close"].tap()
        _ = try await URLSession.shared.data(from: server.appending(path: "__test__/pause"))
        app.buttons["Complete Prepare the launch brief"].tap()
        app.buttons["Reopen Prepare the launch brief"].tap()
        XCTAssertTrue(suggestion.isEnabled)
        suggestion.tap()
        XCTAssertFalse(suggestion.exists)
        XCTAssertFalse(app.staticTexts["Queued for desktop"].exists)
        openResponse.tap()
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertTrue(element("change-output-latency-review").exists)
        review.tap()
        XCTAssertFalse(review.exists)
        if app.buttons["Close"].exists { app.buttons["Close"].tap() }
        let completed = app.buttons["Reopen Review the proposal"]
        XCTAssertTrue(completed.exists)
        capture("responsive-suggestion-and-review-with-delayed-desktop")
        app.buttons["Open chat for Review the proposal"].tap()
        XCTAssertTrue(element("chat-composer").waitForExistence(timeout: 5))
        XCTAssertFalse(element("task-detail").exists)
        app.buttons["Close"].tap()
        completed.tap()
        XCTAssertTrue(app.buttons["Complete Review the proposal"].exists)
        app.tabBars.buttons["Employees"].tap()
        openChat("00000000-0000-4000-8000-000000000020")
        element("chat-composer").tap()
        element("chat-composer").typeText("Send when my desktop reconnects")
        element("send-demo-message").tap()
        XCTAssertTrue(app.staticTexts["Send when my desktop reconnects"].exists)
        XCTAssertTrue(app.staticTexts["Sending…"].exists)
        capture("responsive-queued-chat-with-delayed-desktop")
        _ = try await URLSession.shared.data(from: server.appending(path: "__test__/resume"))
    }

    func testConnectedDesktopTasksChatsAndAgentStates() async throws {
        let server = URL(string: "http://127.0.0.1:18787")!
        let data: Data
        do { (data, _) = try await URLSession.shared.data(from: server.appending(path: "__test__/pair")) }
        catch { throw XCTSkip("Start tests/helpers/companionMobileServer.ts for the native connection test.") }
        let pairing = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        launch(extraArguments: ["--companion-testing"])
        app.tabBars.buttons["Settings"].tap()
        for _ in 0..<6 { if app.buttons["Connect desktop"].isHittable { break }; app.swipeUp() }
        app.buttons["Connect desktop"].tap()
        element("use-connection-link").tap()
        let link = element("companion-link")
        XCTAssertTrue(link.waitForExistence(timeout: 3))
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: link)], timeout: 5)
        link.tap()
        link.typeText(try XCTUnwrap(pairing["url"]))
        element("connect-desktop").tap()
        XCTAssertTrue(app.buttons["Disconnect desktop"].waitForExistence(timeout: 15))
        capture("companion-connected-settings")
        app.tabBars.buttons["Employees"].tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Preparing the launch brief")).firstMatch.waitForExistence(timeout: 10))
        capture("companion-working-agents-and-numbers")
        openChat(try XCTUnwrap(pairing["directThreadId"]))
        let composer = element("chat-composer")
        composer.tap()
        let prompt = "Continue from my iPhone \(UUID().uuidString.prefix(4))"
        composer.typeText(prompt)
        element("send-demo-message").tap()
        XCTAssertTrue(app.staticTexts["Received on desktop: \(prompt)"].waitForExistence(timeout: 15))
        capture("companion-real-chat-round-trip")
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["To-do List"].tap()
        XCTAssertTrue(app.staticTexts["Prepare the launch brief"].waitForExistence(timeout: 5))
        let runningTask = app.buttons["Expand Prepare the launch brief agent work"]
        XCTAssertTrue(runningTask.waitForExistence(timeout: 5))
        XCTAssertTrue((runningTask.value as? String)?.hasPrefix("Preparing the launch brief…, ") == true)
        let dueDate = runningTask.descendants(matching: .any).matching(identifier: "todo-due-date").firstMatch
        XCTAssertFalse(dueDate.exists)
        XCTAssertTrue(runningTask.staticTexts["Expand"].exists)
        XCTAssertFalse(app.buttons["Complete Prepare the launch brief"].exists)
        capture("companion-running-task-light")
        // Spinner, title, activity, and trailing Expand all open the same agent work.
        for point in [CGVector(dx: 0.06, dy: 0.25), CGVector(dx: 0.5, dy: 0.2), CGVector(dx: 0.4, dy: 0.8), CGVector(dx: 0.9, dy: 0.8)] {
            runningTask.coordinate(withNormalizedOffset: point).tap()
            XCTAssertTrue(app.buttons["Stop agent"].waitForExistence(timeout: 5))
            XCTAssertTrue(element("chat-composer").exists)
            app.buttons["Close"].tap()
            XCTAssertTrue(runningTask.waitForExistence(timeout: 5))
        }
        app.tabBars.buttons["Settings"].tap()
        element("appearance-picker").tap()
        app.buttons["Dark"].tap()
        app.tabBars.buttons["To-do List"].tap()
        capture("companion-running-task-dark")
        let questionTask = app.buttons["Answer questions for Review the proposal"]
        XCTAssertTrue(questionTask.exists)
        XCTAssertFalse(app.buttons["Complete Review the proposal"].exists)
        questionTask.tap()
        XCTAssertTrue(app.staticTexts["Which proposal should I review?"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("chat-composer").exists)
        capture("companion-question-single-dark")
        app.buttons["Close"].tap()
        app.tabBars.buttons["Settings"].tap()
        element("appearance-picker").tap()
        app.buttons["Light"].tap()
        app.tabBars.buttons["To-do List"].tap()
        capture("companion-question-task-light")
        questionTask.tap()
        let next = element("question-continue")
        XCTAssertFalse(next.isEnabled)
        let latest = element("question-option-proposal-latest")
        let original = element("question-option-proposal-original")
        latest.tap()
        original.tap()
        XCTAssertEqual(latest.value as? String, "Not selected")
        XCTAssertEqual(original.value as? String, "Selected")
        let custom = element("question-custom-answer")
        custom.tap()
        custom.typeText("The proposal shared yesterday")
        XCTAssertEqual(original.value as? String, "Not selected")
        latest.tap()
        XCTAssertEqual(latest.value as? String, "Selected")
        capture("companion-question-single-light")
        next.tap()
        XCTAssertTrue(app.staticTexts["What should I focus on?"].waitForExistence(timeout: 3))
        XCTAssertFalse(next.isEnabled)
        let clarity = element("question-option-focus-clarity")
        let scope = element("question-option-focus-scope")
        let risks = element("question-option-focus-risks")
        clarity.tap()
        scope.tap()
        risks.tap()
        risks.tap()
        XCTAssertEqual(clarity.value as? String, "Selected")
        XCTAssertEqual(scope.value as? String, "Selected")
        XCTAssertEqual(risks.value as? String, "Not selected")
        capture("companion-question-multiple-light")
        app.buttons["Previous question"].tap()
        XCTAssertEqual(latest.value as? String, "Selected")
        next.tap()
        XCTAssertEqual(clarity.value as? String, "Selected")
        XCTAssertEqual(scope.value as? String, "Selected")
        next.tap()
        XCTAssertTrue(element("chat-composer").waitForExistence(timeout: 15))
        let (answerData, _) = try await URLSession.shared.data(from: server.appending(path: "__test__/answers"))
        let delivered = try XCTUnwrap(JSONSerialization.jsonObject(with: answerData) as? [[String: Any]])
        let response = try XCTUnwrap(delivered.last?["response"] as? [String: Any])
        let answers = try XCTUnwrap(response["answers"] as? [[String: Any]])
        XCTAssertEqual(answers.count, 2)
        XCTAssertEqual(answers[0]["type"] as? String, "option")
        XCTAssertEqual(answers[0]["selectedOptionId"] as? String, "latest")
        XCTAssertEqual(answers[1]["type"] as? String, "options")
        XCTAssertEqual(answers[1]["selectedOptionIds"] as? [String], ["clarity", "scope"])
        let questionID = try XCTUnwrap(delivered.last?["questionId"] as? String)
        let card = element("answered-question-\(questionID)")
        XCTAssertTrue(card.exists)
        XCTAssertTrue(card.staticTexts["Which proposal should I review?"].exists)
        XCTAssertTrue(card.staticTexts["Latest proposal"].exists)
        XCTAssertTrue(card.staticTexts["Clarity, Scope"].exists)
        XCTAssertFalse(app.staticTexts["Latest proposal\nClarity, Scope"].exists)
        capture("companion-answered-question-card")
        app.buttons["Close"].tap()
        XCTAssertFalse(questionTask.exists)
        app.tabBars.buttons["Employees"].tap()
        let (stateData, _) = try await URLSession.shared.data(from: server.appending(path: "__test__/snapshot"))
        let state = try XCTUnwrap(JSONSerialization.jsonObject(with: stateData) as? [String: Any])
        let threads = try XCTUnwrap(state["threads"] as? [[String: Any]])
        let answeredThread = try XCTUnwrap(threads.first { $0["title"] as? String == "Review the proposal" })
        openChat(try XCTUnwrap(answeredThread["id"] as? String))
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["To-do List"].tap()
        runningTask.tap()
        let draft = element("chat-composer")
        draft.tap()
        draft.typeText("Keep this draft")
        XCTAssertTrue(element("stop-agent").isEnabled)
        capture("companion-red-stop-composer")
        element("stop-agent").tap()
        XCTAssertTrue(element("send-demo-message").waitForExistence(timeout: 15))
        XCTAssertEqual(draft.value as? String, "Keep this draft")
        capture("companion-blue-send-composer")
        app.buttons["Close"].tap()
        element("todo-mode-suggestion").tap()
        let sharedMode = expectation(description: "Mode reaches desktop")
        Task {
            for _ in 0..<15 {
                let (data, _) = try await URLSession.shared.data(from: server.appending(path: "__test__/snapshot"))
                if let value = try JSONSerialization.jsonObject(with: data) as? [String: Any], value["mode"] as? String == "suggest" { sharedMode.fulfill(); return }
                try await Task.sleep(for: .seconds(1))
            }
        }
        await fulfillment(of: [sharedMode], timeout: 18)
        capture("companion-shared-tasks-and-mode")
        element("add-todo").tap()
        let title = element("todo-title")
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        let taskTitle = "Prepare meeting notes \(UUID().uuidString.prefix(4))"
        title.typeText(taskTitle)
        app.buttons["Save"].tap()
        XCTAssertFalse(app.staticTexts["Syncing…"].exists)
        let created = expectation(description: "Phone task reaches desktop")
        Task {
            for _ in 0..<15 {
                let (data, _) = try await URLSession.shared.data(from: server.appending(path: "__test__/snapshot"))
                let value = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let tasks = value?["tasks"] as? [[String: Any]] ?? []
                if tasks.contains(where: { $0["title"] as? String == taskTitle }) { created.fulfill(); return }
                try await Task.sleep(for: .seconds(1))
            }
        }
        await fulfillment(of: [created], timeout: 18)
        XCTAssertTrue(app.buttons["Edit \(taskTitle)"].exists)
        capture("companion-task-created-on-phone")
        app.tabBars.buttons["Settings"].tap()
        // Allow the acknowledgement to return before testing explicit disconnection.
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Connected to")).firstMatch.waitForExistence(timeout: 10))
        app.buttons["Disconnect desktop"].tap()
        app.sheets.buttons["Disconnect desktop"].tap()
        XCTAssertTrue(app.buttons["Connect desktop"].waitForExistence(timeout: 10))
    }

    func testDesktopPairingScannerAndConnectionLink() {
        launch()
        app.tabBars.buttons["Settings"].tap()
        for _ in 0..<6 { if app.buttons["Connect desktop"].isHittable { break }; app.swipeUp() }
        app.buttons["Connect desktop"].tap()
        XCTAssertTrue(element("use-connection-link").waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Scan QR code"].exists)
        capture("pairing-scanner")

        element("use-connection-link").tap()
        let link = element("companion-link")
        XCTAssertTrue(link.waitForExistence(timeout: 3))
        XCTAssertFalse(element("connect-desktop").isEnabled)
        let bringTodos = app.switches["bring-todos-to-desktop"]
        XCTAssertEqual(bringTodos.value as? String, "1")
        bringTodos.tap()
        XCTAssertEqual(bringTodos.value as? String, "0")
        capture("pairing-connection-link")
        link.tap()
        link.typeText("invalid-link")
        element("connect-desktop").tap()
        XCTAssertTrue(element("pairing-error").waitForExistence(timeout: 3))
        XCTAssertTrue(element("pairing-error").isHittable)
        XCTAssertTrue(element("connect-desktop").isEnabled)
        capture("pairing-connection-error")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(element("use-connection-link").waitForExistence(timeout: 3))
        element("close-pairing").tap()
        XCTAssertTrue(app.buttons["Connect desktop"].waitForExistence(timeout: 3))

        app.terminate()
        launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.tabBars.buttons["Settings"].tap()
        for _ in 0..<6 { if app.buttons["Connect desktop"].isHittable { break }; app.swipeUp() }
        app.buttons["Connect desktop"].tap()
        for _ in 0..<4 {
            if element("use-connection-link").isHittable,
                element("use-connection-link").frame.maxY < app.frame.maxY - 30 { break }
            app.swipeUp()
        }
        XCTAssertTrue(element("use-connection-link").isHittable)
        capture("pairing-scanner-large-text")
        element("use-connection-link").tap()
        XCTAssertTrue(element("companion-link").waitForExistence(timeout: 3))
        XCTAssertTrue(element("connect-desktop").isHittable)
        capture("pairing-connection-link-large-text")
    }

    func testCreateAndEditAgentWithColor() async throws {
        var reset = URLRequest(url: URL(string: "http://127.0.0.1:18790/reset")!)
        reset.httpMethod = "POST"
        let data: Data
        do { (data, _) = try await URLSession.shared.data(for: reset) }
        catch { throw XCTSkip("Start packages/api/tests/helpers/mobileAgentServer.ts for agent UI tests.") }
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        app.launchEnvironment["DONY_UI_CLOUD_WORKSPACE"] = fixture["workspaceId"]
        defer { app.launchEnvironment.removeValue(forKey: "DONY_UI_CLOUD_WORKSPACE") }
        launch(extraArguments: ["--companion-testing", "--cloud-agent-testing", "-appearance", "dark"])
        let newChat = element("new-chat")
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: newChat)], timeout: 10)
        newChat.tap()
        element("create-agent").tap()
        XCTAssertFalse(app.navigationBars["New agent"].buttons["Create"].isEnabled)
        element("agent-name").tap()
        element("agent-name").typeText("Research")
        element("agent-color-purple").tap()
        XCTAssertTrue(element("agent-color-purple").isSelected)
        element("agent-instructions").tap()
        element("agent-instructions").typeText("Find and cite original sources.")
        capture("create-agent-purple")
        app.navigationBars["New agent"].buttons["Create"].tap()
        XCTAssertTrue(app.buttons["Edit Research"].waitForExistence(timeout: 10))
        app.buttons["Edit Research"].tap()
        XCTAssertEqual(element("agent-name").value as? String, "Research")
        XCTAssertTrue(element("agent-color-purple").isSelected)
        element("agent-color-green").tap()
        app.navigationBars["Edit agent"].buttons["Cancel"].tap()
        app.buttons["Edit Research"].tap()
        XCTAssertTrue(element("agent-color-purple").isSelected)
        element("agent-name").tap()
        element("agent-name").typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "Writer")
        element("agent-color-green").tap()
        capture("edit-agent-green")
        app.navigationBars["Edit agent"].buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Edit Writer"].waitForExistence(timeout: 10))
        app.navigationBars["Choose an agent"].buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Writer"].waitForExistence(timeout: 5))
        capture("employees-agent-edited")
        app.staticTexts["Writer"].press(forDuration: 1)
        app.buttons["Edit agent"].tap()
        XCTAssertEqual(element("agent-instructions").value as? String, "Find and cite original sources.")
        XCTAssertTrue(element("agent-color-green").isSelected)
        element("agent-color-charcoal").tap()
        capture("edit-agent-charcoal-preview")
        app.navigationBars["Edit agent"].buttons["Save"].tap()
        let (savedData, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:18790/snapshot")!)
        let snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: savedData) as? [String: Any])
        let agents = try XCTUnwrap(snapshot["agents"] as? [[String: Any]])
        let agent = try XCTUnwrap(agents.first { $0["name"] as? String == "Writer" })
        XCTAssertEqual(agent["color"] as? String, "#1C1C1C")
        XCTAssertEqual(agent["instructions"] as? String, "Find and cite original sources.")
        app.terminate()
        app.launchArguments = ["--ui-testing", "--companion-testing", "--cloud-agent-testing", "-appearance", "dark"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Writer"].waitForExistence(timeout: 10))
    }

    func testChatThinkingPickerPreservesDraftAndSelection() {
        launch(extraArguments: ["-appearance", "dark"])
        openChat("weekly-update")
        let composer = element("chat-composer")
        composer.tap()
        composer.typeText("Keep this draft")
        element("chat-thinking-picker").tap()
        let slider = element("chat-thinking-slider")
        XCTAssertTrue(slider.waitForExistence(timeout: 3))
        XCTAssertFalse(composer.exists)
        let first = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.085, dy: 0.5))
        let last = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.915, dy: 0.5))
        first.tap()
        XCTAssertTrue((slider.value as? String)?.contains("Quick") == true)
        first.press(forDuration: 0.1, thenDragTo: last)
        XCTAssertTrue((slider.value as? String)?.contains("Expert") == true)
        capture("chat-thinking-deep-dark")
        element("close-thinking-picker").tap()
        XCTAssertEqual(composer.value as? String, "Keep this draft")
        XCTAssertEqual(element("chat-thinking-picker").label, "Thinking: Expert")
        element("send-demo-message").tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "demo reply from Atlas")).firstMatch.waitForExistence(timeout: 3))
        capture("chat-composer-dark")

        app.terminate()
        app.launchArguments = ["--ui-testing", "-appearance", "light"]
        app.launch()
        openChat("weekly-update")
        XCTAssertEqual(element("chat-thinking-picker").label, "Thinking: Expert")
        capture("chat-composer-light")
        element("chat-thinking-picker").tap()
        capture("chat-thinking-deep-light")
    }

    func testDefaultTabsNewChatSendArchiveAndReset() {
        launch()
        XCTAssertEqual(app.tabBars.buttons.count, 3)
        XCTAssertFalse(app.tabBars.buttons["Inbox"].exists)
        XCTAssertTrue(app.tabBars.buttons["To-do List"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
        capture("01-agent-chats-light")

        element("new-chat").tap()
        XCTAssertTrue(element("agent-mira").waitForExistence(timeout: 3))
        element("agent-mira").tap()
        let composer = element("chat-composer")
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertFalse(element("send-demo-message").isEnabled)
        composer.tap()
        composer.typeText("Review the project brief")
        capture("23-chat-composer")
        element("send-demo-message").tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "demo reply from Mira")).firstMatch.waitForExistence(timeout: 3))
        capture("02-local-demo-reply")

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.tabBars.buttons["Employees"].waitForExistence(timeout: 3))
        let newChat = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "chat-", "Review the project brief")).firstMatch
        XCTAssertTrue(newChat.waitForExistence(timeout: 3))
        newChat.swipeLeft()
        app.buttons["Archive"].tap()
        XCTAssertFalse(newChat.exists)

        app.tabBars.buttons["Settings"].tap()
        app.buttons["Reset demo chats"].tap()
        app.alerts.buttons["OK"].tap()
        app.tabBars.buttons["Employees"].tap()
        XCTAssertTrue(element("chat-weekly-update").exists)
    }

    func testOpeningChatKeyboardScrollsToLatestMessage() {
        launch(extraArguments: ["-appearance", "dark"])
        openChat("launch-plan")
        let composer = element("chat-composer")
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        composer.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        let lastParagraph = app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS %@", "Finish with one next step"
        )).firstMatch
        let latestMessageIsVisible = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                lastParagraph.exists && lastParagraph.frame.height > 0
                    && lastParagraph.frame.maxY <= composer.frame.minY
                    && lastParagraph.frame.minY > self.app.navigationBars.firstMatch.frame.maxY
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [latestMessageIsVisible], timeout: 5), .completed)
        XCTAssertLessThan(composer.frame.maxY, app.keyboards.firstMatch.frame.minY)
        capture("chat-keyboard-latest-message-dark")
    }

    func testArchiveMiddleChatAndFullSwipeNextChat() {
        launch()
        let archived = element("chat-launch-plan")
        let following = element("chat-code-example")
        let next = element("chat-running")
        let rowTop = archived.frame.minY
        let firstRowTop = element("chat-weekly-update").frame.minY

        archived.swipeLeft()
        app.buttons["Archive"].tap()
        XCTAssertTrue(archived.waitForNonExistence(timeout: 3))
        XCTAssertTrue(following.isHittable)
        XCTAssertEqual(following.frame.minY, rowTop, accuracy: 1)
        XCTAssertEqual(element("chat-weekly-update").frame.minY, firstRowTop, accuracy: 1)
        capture("archive-middle-chat")

        following.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: following.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)))
        XCTAssertTrue(following.waitForNonExistence(timeout: 3))
        XCTAssertTrue(next.isHittable)
        XCTAssertEqual(next.frame.minY, rowTop, accuracy: 1)
        XCTAssertEqual(element("chat-weekly-update").frame.minY, firstRowTop, accuracy: 1)
        capture("archive-full-swipe-chat")
    }

    func testArchivingLinkedChatConfirmsBeforeDeletingTodo() async throws {
        let (server, _, _) = try await connectInboxFixture()
        let (fixtureData, _) = try await URLSession.shared.data(from: server.appending(path: "__test__/archive"))
        let thread = try JSONDecoder().decode(ArchiveSnapshot.Thread.self, from: fixtureData)
        let snapshotURL = server.appending(path: "__test__/snapshot")
        let (data, _) = try await URLSession.shared.data(from: snapshotURL)
        let snapshot = try JSONDecoder().decode(ArchiveSnapshot.self, from: data)
        let task = try XCTUnwrap(snapshot.tasks.first { $0.id == thread.taskId })
        app.tabBars.buttons["Employees"].tap()
        let row = element("chat-\(thread.id)")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        for _ in 0..<6 { if row.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(row.isHittable)

        row.swipeLeft()
        app.buttons["Archive"].tap()
        let alert = app.alerts["Archive chat and delete to-do?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        XCTAssertTrue(alert.staticTexts["Archiving this chat will delete “\(task.title)” and its subtasks from your To-do List."].exists)
        XCTAssertTrue(row.exists)
        capture("archive-linked-chat-confirmation")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(row.isHittable)
        app.tabBars.buttons["To-do List"].tap()
        let todo = app.buttons["Reopen \(task.title)"]
        for _ in 0..<6 { if todo.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(todo.isHittable)

        app.tabBars.buttons["Employees"].tap()
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)))
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        XCTAssertTrue(row.exists)
        alert.buttons["Archive and delete"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 3))
        app.tabBars.buttons["To-do List"].tap()
        XCTAssertFalse(todo.exists)
        capture("archive-linked-todo-deleted")

        var synced = false
        for _ in 0..<20 {
            let (updatedData, _) = try await URLSession.shared.data(from: snapshotURL)
            let updated = try JSONDecoder().decode(ArchiveSnapshot.self, from: updatedData)
            if !updated.tasks.contains(where: { $0.id == task.id }) && !updated.threads.contains(where: { $0.id == thread.id }) {
                synced = true
                break
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTAssertTrue(synced, "The linked to-do and chat must also be removed from the desktop snapshot")
    }

    private struct ArchiveSnapshot: Decodable {
        struct Task: Decodable { let id: String; let title: String }
        struct Thread: Decodable { let id: String; let taskId: String? }
        let tasks: [Task]
        let threads: [Thread]
    }

    func testChatSearch() {
        launch()
        capture("20-agent-list")
        element("search-chats").tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("atlas")
        XCTAssertTrue(element("search-result-weekly-update").exists)
        XCTAssertFalse(element("search-result-code-example").exists)
        capture("21-chat-search")
        search.tap()
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "zzzz-no-match")
        XCTAssertTrue(app.staticTexts["No matching chats"].exists)
        let closeSearch = app.buttons["Close"].exists ? app.buttons["Close"] : app.buttons["Cancel"]
        closeSearch.tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(element("chat-code-example").exists)
        element("search-chats").tap()
        XCTAssertEqual(search.value as? String, "Search chats")
        search.tap()
        search.typeText("small code")
        XCTAssertTrue(element("search-result-code-example").exists)
        XCTAssertFalse(element("search-result-weekly-update").exists)
        element("search-result-code-example").tap()
        XCTAssertTrue(element("chat-composer").waitForExistence(timeout: 3))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.tabBars.buttons["Employees"].waitForExistence(timeout: 3))
    }

    func testTodoModesAreVisualOnly() {
        launch()
        app.tabBars.buttons["To-do List"].tap()
        let tasks = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Edit "))
        let titles = tasks.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(element("todo-mode-off").isSelected)
        capture("27-todo-mode-off")
        for mode in ["suggestion", "proactive", "off"] {
            element("todo-mode-\(mode)").tap()
            XCTAssertTrue(element("todo-mode-\(mode)").isSelected)
            XCTAssertEqual(tasks.allElementsBoundByIndex.map(\.label), titles)
            capture("28-todo-mode-\(mode)")
        }
        app.tabBars.buttons["Settings"].tap()
        element("appearance-picker").tap()
        app.buttons["Light"].tap()
        app.tabBars.buttons["To-do List"].tap()
        element("todo-mode-proactive").tap()
        capture("29-todo-mode-light")
        XCTAssertEqual(tasks.allElementsBoundByIndex.map(\.label), titles)
    }

    func testTodoModePickerStaysAboveScrollingTasks() {
        launch(extraArguments: ["-appearance", "light"])
        app.tabBars.buttons["To-do List"].tap()
        for index in 1...12 {
            element("add-todo").tap()
            let title = element("todo-title")
            XCTAssertTrue(title.waitForExistence(timeout: 3))
            title.typeText("Scroll task \(index)")
            app.buttons["Save"].tap()
        }

        for (name, arguments) in [
            ("light", ["-appearance", "light"]),
            ("dark", ["-appearance", "dark"]),
            ("large-text", ["-appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        ] {
            app.terminate()
            app.launchArguments = ["--ui-testing"] + arguments
            app.launch()
            app.tabBars.buttons["To-do List"].tap()

            let mode = element("todo-mode-proactive")
            XCTAssertTrue(mode.waitForExistence(timeout: 3))
            let modeFrame = mode.frame
            let list = app.collectionViews.firstMatch
            XCTAssertGreaterThan(list.frame.minY, modeFrame.maxY)
            let firstTask = app.buttons["Edit Prepare the weekly update"]
            XCTAssertTrue(firstTask.isHittable)
            capture("todo-header-\(name)-top")

            list.swipeUp()
            XCTAssertFalse(firstTask.isHittable)
            XCTAssertTrue(mode.isHittable)
            XCTAssertEqual(mode.frame.minY, modeFrame.minY, accuracy: 1)
            XCTAssertEqual(mode.frame.maxY, modeFrame.maxY, accuracy: 1)
            capture("todo-header-\(name)-scrolled")
            mode.tap()
            XCTAssertTrue(mode.isSelected)
        }
    }

    func testSearchWithinChatAndOpenFilePicker() {
        launch()
        openChat("code-example")
        capture("24-chat-search-and-files")
        element("search-chat-messages").tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("TodoItem")
        XCTAssertTrue(element("message-search-result").waitForExistence(timeout: 3))
        capture("25-message-search")
        element("message-search-result").tap()
        XCTAssertTrue(element("chat-composer").waitForExistence(timeout: 3))
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        element("search-chat-messages").tap()
        search.tap()
        search.typeText("zzzz-no-match")
        XCTAssertTrue(app.staticTexts["No matching messages"].exists)
        let closeSearch = app.buttons["Close"].exists ? app.buttons["Close"] : app.buttons["Cancel"]
        closeSearch.tap()
        app.buttons["Done"].tap()

        element("chat-composer").tap()
        element("chat-composer").typeText("Keep my draft")
        element("add-chat-files").tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        capture("26-chat-file-picker")
        app.buttons["Cancel"].tap()
        XCTAssertEqual(element("chat-composer").value as? String, "Keep my draft")
        XCTAssertTrue(element("send-demo-message").isEnabled)
    }

    func testTodoCreateEditCompleteRelaunchReopenAndSwipeDelete() {
        launch()
        app.tabBars.buttons["To-do List"].tap()
        element("add-todo").tap()
        let title = element("todo-title")
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        title.typeText("Draft")
        app.buttons["Save"].tap()
        app.buttons["Edit Draft"].tap()
        element("task-detail").buttons["Edit Draft"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "Review the brief")
        XCTAssertEqual(title.value as? String, "Review the brief")
        app.buttons["Save"].tap()
        app.buttons["Close"].tap()
        app.buttons["Complete Review the brief"].tap()
        XCTAssertTrue(app.buttons["Reopen Review the brief"].exists)
        capture("03-todos-completed")

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.tabBars.buttons["To-do List"].tap()
        XCTAssertTrue(app.buttons["Reopen Review the brief"].waitForExistence(timeout: 3))
        app.buttons["Reopen Review the brief"].tap()
        app.buttons["Edit Review the brief"].swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertFalse(app.buttons["Edit Review the brief"].exists)
    }

    func testTodoAgentMentionsCreateEditAndRelaunch() {
        launch()
        app.tabBars.buttons["To-do List"].tap()
        element("add-todo").tap()
        let title = element("todo-title")
        title.typeText("Review ")
        let inputY = title.frame.minY
        title.typeText("@")
        XCTAssertTrue(element("todo-mention-atlas").waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(element("todo-mention-mira").exists)
        XCTAssertTrue(element("todo-mention-atlas").isHittable)
        XCTAssertTrue(element("todo-mention-mira").isHittable)
        XCTAssertEqual(title.frame.minY, inputY, accuracy: 1)
        capture("todo-agent-picker")
        title.typeText("mi")
        XCTAssertEqual(title.frame.minY, inputY, accuracy: 1)
        XCTAssertTrue(element("todo-mention-mira").exists)
        XCTAssertFalse(element("todo-mention-atlas").exists)
        element("todo-mention-mira").tap()
        XCTAssertEqual(title.value as? String, "Review @mira ")
        XCTAssertFalse(element("todo-agent-suggestions").exists)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        title.typeText("proposal")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Edit Review @mira proposal"].waitForExistence(timeout: 3))
        capture("todo-agent-tag-saved")

        app.buttons["Edit Review @mira proposal"].tap()
        element("task-detail").buttons["Edit Review @mira proposal"].tap()
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        title.typeText(" @at")
        element("todo-mention-atlas").tap()
        XCTAssertEqual(title.value as? String, "Review @mira proposal @atlas ")
        app.buttons["Save"].tap()
        app.buttons["Close"].tap()
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.tabBars.buttons["To-do List"].tap()
        XCTAssertTrue(app.buttons["Edit Review @mira proposal @atlas"].waitForExistence(timeout: 3))
    }

    func testSubtaskAgentMentionsAndNoMatches() {
        launch(extraArguments: ["-appearance", "dark"])
        app.tabBars.buttons["To-do List"].tap()
        element("add-todo").tap()
        let title = element("todo-title")
        title.typeText("Email hello@example.com")
        XCTAssertFalse(element("todo-agent-suggestions").exists)
        app.buttons["Add subtask"].tap()
        let subtask = element("Subtask title")
        subtask.typeText("Research @zz")
        XCTAssertTrue(app.staticTexts["No matching agents"].waitForExistence(timeout: 3))
        subtask.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "pi")
        XCTAssertTrue(element("todo-mention-pixel").waitForExistence(timeout: 3))
        capture("todo-subtask-agent-picker-dark")
        element("todo-mention-pixel").tap()
        XCTAssertEqual(subtask.value as? String, "Research @pixel ")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Edit Research @pixel"].waitForExistence(timeout: 3))
    }

    func testTodoAgentPickerWithLargeText() {
        launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.tabBars.buttons["To-do List"].tap()
        element("add-todo").tap()
        element("todo-title").typeText("Plan @at")
        let agent = element("todo-mention-atlas")
        XCTAssertTrue(agent.waitForExistence(timeout: 3))
        for _ in 0..<4 { if agent.isHittable { break }; element("task-composer").swipeUp() }
        XCTAssertTrue(agent.isHittable)
        XCTAssertGreaterThanOrEqual(agent.frame.minY, 0)
        XCTAssertLessThanOrEqual(agent.frame.maxY, app.keyboards.firstMatch.frame.minY)
        XCTAssertLessThanOrEqual(agent.frame.maxX, app.frame.maxX)
        capture("todo-agent-picker-large-text")
        agent.tap()
        XCTAssertEqual(element("todo-title").value as? String, "Plan @atlas ")
        app.buttons["Save"].tap()
        for _ in 0..<5 { if app.buttons["Edit Plan @atlas"].exists { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["Edit Plan @atlas"].waitForExistence(timeout: 3))
    }

    func testCompactTaskComposerAppearanceAndDate() {
        for appearance in ["light", "dark", "large-text"] {
            var arguments = ["-appearance", appearance == "light" ? "light" : "dark"]
            if appearance == "large-text" {
                arguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
            launch(extraArguments: arguments)
            app.tabBars.buttons["To-do List"].tap()
            element("add-todo").tap()
            let title = element("todo-title")
            XCTAssertTrue(title.waitForExistence(timeout: 3))
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["Cancel"].isHittable)
            XCTAssertFalse(app.buttons["Save"].isEnabled)
            XCTAssertLessThanOrEqual(element("task-composer").frame.maxY, app.keyboards.firstMatch.frame.minY)
            if appearance != "large-text" {
                XCTAssertLessThan(element("task-composer").frame.height, 220)
            }
            capture("compact-task-empty-\(appearance)")
            title.typeText("Plan the next release")
            element("edit-due-date").tap()
            XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 3))
            app.buttons["Today"].tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
            XCTAssertEqual(title.value as? String, "Plan the next release")
            XCTAssertTrue(element("edit-due-date").label.contains("Today"))
            XCTAssertTrue(app.buttons["Save"].isHittable)
            capture("compact-task-ready-\(appearance)")
            app.buttons["Save"].tap()
            for _ in 0..<5 {
                if app.buttons["Edit Plan the next release"].exists { break }
                app.swipeUp()
            }
            XCTAssertTrue(app.buttons["Edit Plan the next release"].waitForExistence(timeout: 3))
        }
    }

    func testCreateTaskWithSubtaskDrafts() {
        launch()
        app.tabBars.buttons["To-do List"].tap()
        XCTAssertFalse(app.buttons["Add subtask"].exists)
        element("add-todo").tap()
        element("todo-title").typeText("Prepare launch")
        app.buttons["Add subtask"].tap()
        let subtaskTitles = app.descendants(matching: .any).matching(identifier: "Subtask title")
        subtaskTitles.element(boundBy: 0).typeText("Review copy")
        app.buttons["Add subtask"].tap()
        subtaskTitles.element(boundBy: 1).typeText("Remove this draft")
        app.buttons.matching(identifier: "Remove subtask").element(boundBy: 1).tap()
        app.buttons["Add subtask"].tap()
        subtaskTitles.element(boundBy: 1).typeText("Check links")
        app.buttons["Add subtask"].tap()
        capture("new-task-with-subtask-drafts")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Edit Prepare launch"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Edit Review copy"].exists)
        XCTAssertTrue(app.buttons["Edit Check links"].exists)
        XCTAssertFalse(app.buttons["Edit Remove this draft"].exists)
        XCTAssertFalse(app.buttons["Add subtask"].exists)

        element("add-todo").tap()
        element("todo-title").typeText("Cancelled task")
        app.buttons["Add subtask"].tap()
        subtaskTitles.element(boundBy: 0).typeText("Cancelled subtask")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["Edit Cancelled task"].exists)
        XCTAssertFalse(app.buttons["Edit Cancelled subtask"].exists)

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.tabBars.buttons["To-do List"].tap()
        app.buttons["Edit Prepare launch"].tap()
        XCTAssertTrue(app.buttons["Add subtask"].exists)
        XCTAssertTrue(element("task-detail").buttons["Edit Review copy"].exists)
        XCTAssertTrue(element("task-detail").buttons["Edit Check links"].exists)
    }

    func testSubtasksAndDueDatesSurviveRelaunch() {
        launch()
        app.tabBars.buttons["To-do List"].tap()
        app.buttons["Edit Prepare the weekly update"].tap()
        element("edit-due-date").tap()
        XCTAssertTrue(app.buttons["Tomorrow"].waitForExistence(timeout: 3))
        capture("18-due-date-editor")
        app.buttons["Next week"].tap()
        element("edit-due-date").tap()
        let savedDay = element("due-date-picker").buttons.matching(NSPredicate(format: "label CONTAINS %@", ", 15 ")).firstMatch
        XCTAssertTrue(savedDay.exists)
        savedDay.tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(element("edit-due-date").label.contains("15"))
        element("edit-due-date").tap()
        app.buttons["Tomorrow"].tap()
        element("edit-due-date").tap()
        let calendarDay = element("due-date-picker").buttons.matching(NSPredicate(format: "label CONTAINS %@", ", 15 ")).firstMatch
        XCTAssertTrue(calendarDay.exists)
        calendarDay.tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(element("edit-due-date").label.contains("Tomorrow"))

        app.buttons["Add subtask"].tap()
        element("todo-title").typeText("Collect team updates")
        element("task-composer").buttons["edit-due-date"].tap()
        app.buttons["Today"].tap()
        app.buttons["Save"].tap()
        element("task-detail").buttons["Complete Collect team updates"].tap()
        capture("19-task-detail")
        app.buttons["Close"].tap()
        capture("17-subtasks-and-due-dates")

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.tabBars.buttons["To-do List"].tap()
        XCTAssertTrue(app.buttons["Reopen Collect team updates"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons["Edit Collect team updates"].value as? String, "Due Today")
        XCTAssertEqual(app.buttons["Edit Prepare the weekly update"].value as? String, "Due Tomorrow")
        app.buttons["Edit Collect team updates"].tap()
        element("edit-due-date").tap()
        app.buttons["No date"].tap()
        app.buttons["Close"].tap()
        XCTAssertEqual(app.buttons["Edit Collect team updates"].value as? String ?? "", "")
        app.buttons["Edit Prepare the weekly update"].swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertFalse(app.buttons["Edit Collect team updates"].exists)
    }

    func testEraseConfirmationSurvivesRelaunch() {
        launch()
        app.tabBars.buttons["To-do List"].tap()
        XCTAssertFalse(app.navigationBars.buttons["Edit"].exists)
        let rows = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Edit "))
        XCTAssertEqual(rows.count, 3)
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Erase all to-dos"].tap()
        app.alerts.buttons["Cancel"].tap()
        app.tabBars.buttons["To-do List"].tap()
        XCTAssertEqual(rows.count, 3)
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Erase all to-dos"].tap()
        app.alerts.buttons["Erase all to-dos"].tap()

        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.tabBars.buttons["To-do List"].tap()
        XCTAssertTrue(app.staticTexts["A little room to focus"].exists)
        XCTAssertEqual(rows.count, 0)
        element("todo-mode-proactive").tap()
        XCTAssertTrue(element("todo-mode-proactive").isSelected)
        capture("04-todos-empty-after-relaunch")
    }

    func testAppearanceAndDemoStates() {
        launch()
        openChat("weekly-update")
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        capture("05-demo-result")
        app.navigationBars.buttons.firstMatch.tap()
        openChat("launch-plan")
        capture("30-chat-gradient-dark")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Finish with one next step")).firstMatch.exists)
        capture("05b-long-response")
        app.navigationBars.buttons.firstMatch.tap()
        openChat("code-example")
        capture("06-code-and-lists")
        app.navigationBars.buttons.firstMatch.tap()
        openChat("running")
        XCTAssertTrue(element("demo-running").exists)
        capture("07-running-demo")
        app.navigationBars.buttons.firstMatch.tap()
        openChat("error")
        XCTAssertTrue(element("demo-error").exists)
        capture("08-error-demo")
        app.navigationBars.buttons.firstMatch.tap()
        openChat("empty")
        XCTAssertTrue(app.staticTexts["A fresh start"].exists)
        capture("09-empty-chat")
        app.navigationBars.buttons.firstMatch.tap()

        app.tabBars.buttons["Settings"].tap()
        element("appearance-picker").tap()
        app.buttons["Dark"].tap()
        capture("10-settings-dark")
        app.tabBars.buttons["To-do List"].tap()
        capture("11-todos-dark")
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        app.tabBars.buttons["Settings"].tap()
        let picker = element("appearance-picker")
        XCTAssertTrue("\(picker.label) \(picker.value ?? "")".contains("Dark"))
        element("appearance-picker").tap()
        app.buttons["Light"].tap()
        capture("12-settings-light")
        app.tabBars.buttons["Employees"].tap()
        openChat("weekly-update")
        capture("22-chat-light")
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        app.navigationBars.buttons.firstMatch.tap()
        openChat("launch-plan")
        capture("31-chat-gradient-light")
    }

    func testAccessibilityAndLargeText() throws {
        launch(extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        capture("13-chats-accessibility-text")
        openChat("weekly-update")
        capture("13b-chat-accessibility-text")
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["To-do List"].tap()
        XCTAssertTrue(app.buttons["Complete Prepare the weekly update"].exists)
        let largeTitleHeight = app.buttons["Edit Prepare the weekly update"].frame.height
        capture("14-todos-accessibility-text")
        app.buttons["Edit Prepare the weekly update"].tap()
        element("task-detail").buttons["Edit Prepare the weekly update"].tap()
        XCTAssertTrue(element("todo-title").waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Save"].isHittable)
        app.buttons["Cancel"].tap()
        app.buttons["Close"].tap()
        app.tabBars.buttons["Settings"].tap()
        capture("15-settings-accessibility-text")

        app.terminate()
        launch()
        app.tabBars.buttons["To-do List"].tap()
        XCTAssertGreaterThan(largeTitleHeight, app.buttons["Edit Prepare the weekly update"].frame.height * 2)
        // Inspect text scaling and color in the retained screenshots. The whole-screen
        // contrast audit also reports native content beneath iOS's translucent tab bar.
        let auditTypes: XCUIAccessibilityAuditType = [.elementDetection, .hitRegion, .sufficientElementDescription, .trait]
        toggleInboxInSettings()
        for tab in ["Employees", "To-do List", "Inbox", "Settings"] {
            app.tabBars.buttons[tab].tap()
            try app.performAccessibilityAudit(for: auditTypes) { issue in
                print("Accessibility issue in \(tab): \(issue.detailedDescription)\n\(issue.element?.debugDescription ?? "No element")")
                return false
            }
        }
    }

}

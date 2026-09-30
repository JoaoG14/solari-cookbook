import XCTest

@MainActor
final class OnboardingUITests: XCTestCase {
    private let app = XCUIApplication()

    private func launch(reset: Bool = true, extra: [String] = []) {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing", "--onboarding-testing"] + (reset ? ["--reset-todos"] : []) + extra
        app.launch()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func signIn() {
        XCTAssertTrue(app.buttons["welcome-sign-in"].waitForExistence(timeout: 10))
        app.buttons["welcome-sign-in"].tap()
    }

    func testSignOutReturnsToWelcome() {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing", "--companion-testing", "--cloud-agent-testing", "--reset-todos"]
        app.launchEnvironment["DONY_UI_CLOUD_WORKSPACE"] = "sign-out-test"
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 5))
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.buttons["welcome-sign-in"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        capture("welcome-after-sign-out")
    }

    func testCompletedOnboardingWithoutAnAccountShowsSignInAfterRelaunch() {
        continueAfterFailure = false
        // Companion testing starts without credentials; normal UI testing marks onboarding complete.
        app.launchArguments = ["--ui-testing", "--companion-testing", "--reset-todos"]
        app.launch()
        XCTAssertTrue(app.buttons["welcome-sign-in"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        capture("signed-out-welcome")

        app.terminate()
        app.launchArguments = ["--ui-testing", "--companion-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["welcome-sign-in"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }

    func testPaywallShowsPlansAndYearlyOptionsThenReturnsToTheFreeList() {
        launch()
        signIn()
        app.buttons["onboarding-skip"].tap()
        app.buttons["onboarding-secondary"].tap()
        app.buttons["onboarding-secondary"].tap()
        XCTAssertTrue(app.buttons["paywall-close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["view-all-plans"].isHittable)
        XCTAssertTrue(app.buttons["billing-yearly"].isSelected)
        capture("paywall-yearly")
        app.buttons["view-all-plans"].tap()
        XCTAssertTrue(app.staticTexts["Choose your plan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Max"].exists)
        XCTAssertTrue(app.staticTexts["Pro"].exists)
        XCTAssertFalse(app.staticTexts["Pro+"].exists)
        capture("all-plans-yearly")
        app.swipeUp()
        XCTAssertTrue(app.buttons["Connect to Mac"].waitForExistence(timeout: 5))
        capture("all-plans-mac-option")
        app.buttons["paywall-close"].tap()
        XCTAssertTrue(app.tabBars.buttons["To-do List"].waitForExistence(timeout: 10))
    }

    func testOnboardingFollowsLightAppearance() {
        launch(extra: ["-appearance", "light"])
        XCTAssertTrue(element("onboarding-welcome").waitForExistence(timeout: 10))
        capture("welcome-light")
        signIn()
        for index in 0..<4 {
            XCTAssertTrue(element("onboarding-benefit-\(index)").waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["onboarding-continue"].isHittable)
            capture("onboarding-benefit-\(index + 1)-light")
            app.buttons["onboarding-continue"].tap()
        }
        XCTAssertTrue(app.staticTexts["List recurring paid subscriptions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Unsubscribe from promotional emails"].isHittable)
        capture("onboarding-tasks-light")
        app.buttons["onboarding-secondary"].tap()
        XCTAssertTrue(app.staticTexts["Let's connect your email"].waitForExistence(timeout: 5))
        capture("onboarding-tools-light")
    }

    func testGmailConnectsAfterDefaultTasks() {
        verifyEmailOnboarding(toolkit: "gmail", name: "Gmail")
    }

    func testOutlookConnectsAfterDefaultTasks() {
        verifyEmailOnboarding(toolkit: "outlook", name: "Outlook")
    }

    private func verifyEmailOnboarding(toolkit: String, name: String) {
        launch()
        signIn()
        app.buttons["onboarding-skip"].tap()
        XCTAssertTrue(app.staticTexts["List recurring paid subscriptions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Find upcoming renewals and deadlines"].exists)
        XCTAssertTrue(app.staticTexts["Prep for next external meeting"].exists)
        XCTAssertTrue(app.staticTexts["Unsubscribe from promotional emails"].exists)
        XCTAssertFalse(app.buttons["onboarding-continue"].isEnabled)
        capture("onboarding-default-tasks")
        app.staticTexts["List recurring paid subscriptions"].tap()
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(element("connector-gmail").waitForExistence(timeout: 10))
        XCTAssertTrue(element("connector-outlook").exists)
        for slug in ["googledrive", "googlecalendar", "notion"] {
            XCTAssertFalse(element("connector-\(slug)").exists)
        }
        XCTAssertEqual(app.buttons["onboarding-connect-\(toolkit)"].label, "Connect \(name)")
        XCTAssertTrue(app.buttons["onboarding-connect-\(toolkit)"].isHittable)
        capture("onboarding-\(toolkit)")
        app.buttons["Connect \(name)"].tap()
        XCTAssertTrue(app.buttons["Manage \(name)"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["onboarding-continue"].label, "Continue")
        capture("onboarding-\(toolkit)-connected")
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.buttons["paywall-close"].waitForExistence(timeout: 5))
        app.buttons["onboarding-back"].tap()
        app.buttons["onboarding-back"].tap()
        XCTAssertTrue(app.staticTexts["List recurring paid subscriptions"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["onboarding-continue"].label, "Add selected tasks")
        XCTAssertTrue(app.buttons["onboarding-continue"].isEnabled)
        app.buttons["onboarding-continue"].tap()
        app.buttons["onboarding-secondary"].tap()
        app.buttons["paywall-close"].tap()
        XCTAssertTrue(app.buttons["Edit List recurring paid subscriptions"].waitForExistence(timeout: 10))
    }

    func testWelcomeDemoAndSignIn() {
        launch()
        let example = element("welcome-task-example")
        XCTAssertTrue(example.waitForExistence(timeout: 10))
        XCTAssertTrue(example.label.contains("Plan a weekend in Lisbon"))
        XCTAssertTrue(app.buttons["welcome-sign-in"].isHittable)
        XCTAssertTrue(app.buttons["welcome-apple-sign-in"].isHittable)
        XCTAssertFalse(app.buttons["welcome-pause-demo"].exists)
        XCTAssertFalse(app.buttons["welcome-next-example"].exists)
        XCTAssertFalse(app.staticTexts["A little Dony demo"].exists)
        XCTAssertFalse(app.staticTexts["Big plans. Small errands.\nA little help with all of it."].exists)
        capture("welcome-initial")
        app.buttons["welcome-apple-sign-in"].tap()
        XCTAssertTrue(element("onboarding-benefit-0").waitForExistence(timeout: 10))
        app.terminate()
        launch(reset: false)
        XCTAssertTrue(element("onboarding-benefit-0").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["welcome-sign-in"].exists)
    }

    func testWelcomeCompletesAndAutomaticallySwapsExamples() {
        launch()
        let example = element("welcome-task-example")
        XCTAssertTrue(example.waitForExistence(timeout: 10))
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Completed'"), object: example)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 15), .completed)
        capture("welcome-completed-real-row")
        let swapped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'Sort out next week'"), object: example)
        XCTAssertEqual(XCTWaiter.wait(for: [swapped], timeout: 8), .completed)
        capture("welcome-swapped-real-row")
        XCTAssertTrue(app.buttons["welcome-sign-in"].isHittable)
    }

    func testBenefitScreensResumeAndFinishWithSelectedTasks() {
        launch()
        signIn()
        for index in 0..<4 {
            XCTAssertTrue(element("onboarding-benefit-\(index)").waitForExistence(timeout: 10))
            capture("onboarding-benefit-\(index + 1)")
            if index == 1 {
                app.terminate()
                launch(reset: false)
                XCTAssertTrue(element("onboarding-benefit-1").waitForExistence(timeout: 10))
            }
            app.buttons["onboarding-continue"].tap()
        }
        XCTAssertTrue(app.staticTexts["List recurring paid subscriptions"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding-continue"].isEnabled)
        app.staticTexts["List recurring paid subscriptions"].tap()
        XCTAssertFalse(element("onboarding-task-input").exists)
        XCTAssertFalse(app.buttons["Add your task"].exists)
        app.staticTexts["Find upcoming renewals and deadlines"].tap()
        XCTAssertFalse(app.staticTexts["Go through my email to find recurring subscriptions. List each service, amount, renewal date, and anything that looks unused."].exists)
        capture("onboarding-first-tasks")
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.staticTexts["Let's connect your email"].waitForExistence(timeout: 5))
        app.buttons["onboarding-secondary"].tap()
        XCTAssertTrue(app.buttons["paywall-close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["paywall-close"].isHittable)
        XCTAssertFalse(app.buttons["Continue with Google"].exists)
        capture("onboarding-cloud")
        app.buttons["paywall-close"].tap()
        XCTAssertTrue(app.tabBars.buttons["To-do List"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["To-do List"].isSelected)
        XCTAssertTrue(app.buttons["Edit Find upcoming renewals and deadlines"].exists)
        XCTAssertFalse(app.buttons["Edit Review the landing page"].exists)
        capture("onboarding-arrival")
        app.terminate()
        launch(reset: false)
        XCTAssertTrue(app.tabBars.buttons["To-do List"].waitForExistence(timeout: 10))
        app.tabBars.buttons["To-do List"].tap()
        XCTAssertTrue(app.buttons["Edit Find upcoming renewals and deadlines"].exists)
    }

    func testSkipAndEmptyList() {
        launch()
        signIn()
        app.buttons["onboarding-skip"].tap()
        XCTAssertTrue(app.staticTexts["List recurring paid subscriptions"].waitForExistence(timeout: 5))
        app.buttons["onboarding-secondary"].tap()
        XCTAssertTrue(app.staticTexts["Let's connect your email"].waitForExistence(timeout: 5))
        app.buttons["onboarding-secondary"].tap()
        XCTAssertTrue(app.buttons["paywall-close"].waitForExistence(timeout: 5))
        app.buttons["paywall-close"].tap()
        XCTAssertTrue(app.tabBars.buttons["To-do List"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Edit List recurring paid subscriptions"].exists)
    }

    func testToolsAuthorizeAfterOptionalPairing() async throws {
        let server = URL(string: "http://127.0.0.1:18788")!
        let data: Data
        do { (data, _) = try await URLSession.shared.data(from: server.appending(path: "pair")) }
        catch { throw XCTSkip("Start tests/helpers/connectorMobileServer.ts for connector UI tests.") }
        let pairing = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        launch(extra: ["--companion-testing"])
        app.launchArguments.removeAll { $0 == "--reset-todos" }
        app.open(try XCTUnwrap(URL(string: try XCTUnwrap(pairing["url"]))))
        XCTAssertTrue(element("connect-desktop").waitForExistence(timeout: 5))
        element("connect-desktop").tap()
        XCTAssertTrue(app.staticTexts["List recurring paid subscriptions"].waitForExistence(timeout: 20))
        app.staticTexts["List recurring paid subscriptions"].tap()
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(element("connector-gmail").waitForExistence(timeout: 20))
        for slug in ["googledrive", "googlecalendar", "notion"] {
            XCTAssertFalse(element("connector-\(slug)").exists)
        }
        XCTAssertFalse(element("connector-figma").exists)
        capture("onboarding-tools")
        app.buttons["Connect Gmail"].tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))
        var complete = URLRequest(url: server.appending(path: "complete"))
        complete.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: complete)
        XCTAssertTrue(app.buttons["Manage Gmail"].waitForExistence(timeout: 20))
        capture("onboarding-tools-connected")
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.buttons["paywall-close"].waitForExistence(timeout: 10))
    }

    func testLargeTextKeepsNavigationAndContentReachable() {
        launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        for _ in 0..<6 {
            if app.buttons["welcome-sign-in"].isHittable { break }
            app.swipeUp()
        }
        capture("welcome-large-text")
        signIn()
        XCTAssertTrue(app.buttons["onboarding-continue"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["onboarding-continue"].isHittable)
        app.swipeUp()
        capture("onboarding-large-text")
        app.buttons["onboarding-skip"].tap()
        XCTAssertTrue(app.staticTexts["List recurring paid subscriptions"].waitForExistence(timeout: 5))
        for _ in 0..<8 {
            app.scrollViews.firstMatch.swipeUp()
            if app.staticTexts["List recurring paid subscriptions"].isHittable { break }
        }
        XCTAssertTrue(app.staticTexts["List recurring paid subscriptions"].isHittable)
        capture("onboarding-first-tasks-large-text")
        for _ in 0..<10 {
            if app.buttons["onboarding-secondary"].isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(app.buttons["onboarding-secondary"].isHittable)
        app.buttons["onboarding-secondary"].tap()
        capture("onboarding-email-large-text")
        for _ in 0..<8 {
            if app.buttons["onboarding-connect-gmail"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["onboarding-connect-gmail"].isHittable)
        capture("onboarding-email-large-text-connect")
        for _ in 0..<8 {
            if app.buttons["onboarding-secondary"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["onboarding-secondary"].isHittable)
        capture("onboarding-email-large-text-actions")
        app.buttons["onboarding-secondary"].tap()
        XCTAssertTrue(app.buttons["paywall-close"].waitForExistence(timeout: 5))
    }
}

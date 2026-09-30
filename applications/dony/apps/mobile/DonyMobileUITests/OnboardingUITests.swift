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
        XCTAssertTrue(app.staticTexts["Research solar energy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Explore the history of the web"].isHittable)
        capture("onboarding-tasks-light")
        app.buttons["onboarding-secondary"].tap()
        XCTAssertTrue(app.tabBars.buttons["To-do List"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["paywall-close"].exists)
        XCTAssertFalse(element("connector-gmail").exists)
        capture("onboarding-arrival-light")
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
        XCTAssertTrue(app.staticTexts["Research solar energy"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding-continue"].isEnabled)
        app.staticTexts["Research solar energy"].tap()
        XCTAssertFalse(element("onboarding-task-input").exists)
        XCTAssertFalse(app.buttons["Add your task"].exists)
        app.staticTexts["Compare browser automation tools"].tap()
        capture("onboarding-first-tasks")
        app.buttons["onboarding-continue"].tap()
        XCTAssertTrue(app.tabBars.buttons["To-do List"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["To-do List"].isSelected)
        XCTAssertTrue(app.buttons["Edit Compare browser automation tools"].exists)
        XCTAssertFalse(app.buttons["Edit Review the landing page"].exists)
        capture("onboarding-arrival")
        app.terminate()
        launch(reset: false)
        XCTAssertTrue(app.tabBars.buttons["To-do List"].waitForExistence(timeout: 10))
        app.tabBars.buttons["To-do List"].tap()
        XCTAssertTrue(app.buttons["Edit Compare browser automation tools"].exists)
    }

    func testSkipAndEmptyList() {
        launch()
        signIn()
        app.buttons["onboarding-skip"].tap()
        XCTAssertTrue(app.staticTexts["Research solar energy"].waitForExistence(timeout: 5))
        app.buttons["onboarding-secondary"].tap()
        XCTAssertFalse(app.buttons["paywall-close"].exists)
        XCTAssertFalse(element("connector-gmail").exists)
        XCTAssertTrue(app.tabBars.buttons["To-do List"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Edit Research solar energy"].exists)
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
        XCTAssertTrue(app.staticTexts["Research solar energy"].waitForExistence(timeout: 5))
        for _ in 0..<8 {
            if app.staticTexts["Research solar energy"].isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["Research solar energy"].isHittable)
        capture("onboarding-first-tasks-large-text")
        for _ in 0..<10 {
            if app.buttons["onboarding-secondary"].isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(app.buttons["onboarding-secondary"].isHittable)
        app.buttons["onboarding-secondary"].tap()
        XCTAssertTrue(app.tabBars.buttons["To-do List"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["paywall-close"].exists)
        capture("onboarding-arrival-large-text")
    }
}

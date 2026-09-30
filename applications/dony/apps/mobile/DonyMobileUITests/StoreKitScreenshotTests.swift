import StoreKitTest
import XCTest

@MainActor
final class StoreKitScreenshotTests: XCTestCase {
    private let app = XCUIApplication()
    private var storeKit: SKTestSession!

    override func setUpWithError() throws {
        continueAfterFailure = false
        storeKit = try SKTestSession(configurationFileNamed: "DonyProducts")
        storeKit.resetToDefaultState()
        storeKit.clearTransactions()
        storeKit.disableDialogs = true
    }

    private func launch(extras: Bool = false) {
        app.launchArguments = ["--ui-testing", "--storekit-screenshots", "-appearance", "light"]
        if extras { app.launchArguments.append("--usage-packs") }
        app.launch()
        XCTAssertTrue(app.buttons["paywall-close"].waitForExistence(timeout: 15))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSubscriptionReviewScreenshots() {
        launch()
        XCTAssertTrue(app.staticTexts["$199.00 billed yearly"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["billing-yearly"].isSelected)
        XCTAssertEqual(app.buttons["billing-yearly"].value as? String, "2 months free")
        XCTAssertTrue(app.buttons["Subscribe"].isEnabled)
        capture("pro-yearly")
        app.buttons["billing-monthly"].tap()
        XCTAssertTrue(app.staticTexts["$19.99 billed monthly"].exists)
        XCTAssertTrue(app.buttons["billing-monthly"].isSelected)
        capture("pro-monthly")
        app.buttons["billing-yearly"].tap()
        app.buttons["view-all-plans"].tap()
        XCTAssertFalse(app.staticTexts["$1,990.00/year"].exists)
        XCTAssertTrue(app.staticTexts["Max"].exists)
        XCTAssertFalse(app.staticTexts["Pro+"].exists)
        XCTAssertTrue(app.staticTexts["$999.00/year"].exists)
        capture("max-yearly")
        app.segmentedControls["billing-period"].buttons["Monthly"].tap()
        XCTAssertFalse(app.staticTexts["$199.00/month"].exists)
        XCTAssertTrue(app.staticTexts["$99.99/month"].exists)
        capture("max-monthly")
    }

    func testConnectPlanAppearsAboveFreeMacAndShowsBothPrices() {
        launch()
        XCTAssertTrue(app.buttons["Subscribe"].waitForExistence(timeout: 20))
        app.buttons["view-all-plans"].tap()
        for _ in 0..<5 where !app.buttons["Connect to Mac"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["$49.99/year"].exists)
        XCTAssertTrue(app.buttons["Subscribe to Connect"].isEnabled)
        XCTAssertLessThan(app.buttons["Subscribe to Connect"].frame.minY, app.buttons["Connect to Mac"].frame.minY)
        capture("connect-yearly-and-free-mac")
        for _ in 0..<5 where !app.segmentedControls["billing-period"].isHittable { app.swipeDown() }
        app.segmentedControls["billing-period"].buttons["Monthly"].tap()
        for _ in 0..<5 where !app.buttons["Connect to Mac"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["$4.99/month"].exists)
        capture("connect-monthly-and-free-mac")
    }

    func testDisconnectedMacBannerOpensConnectAndCanBeDismissed() {
        app.launchArguments = ["--ui-testing", "--storekit-screenshots", "--connect-banner-testing", "-appearance", "light"]
        app.launch()
        XCTAssertTrue(app.buttons["Explore Connect"].waitForExistence(timeout: 15))
        capture("connect-disconnected-mac-banner")
        app.buttons["Explore Connect"].tap()
        XCTAssertTrue(app.buttons["Subscribe to Connect"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Subscribe to Connect"].isHittable)
        capture("connect-banner-plan-destination")
        app.buttons["paywall-close"].tap()
        app.buttons["Dismiss Connect suggestion"].tap()
        XCTAssertFalse(app.buttons["Explore Connect"].exists)
    }

    func testExtraUsageReviewScreenshots() {
        launch(extras: true)
        XCTAssertTrue(app.staticTexts["$19.99"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["$49.99"].exists)
        XCTAssertTrue(app.staticTexts["$99.99"].exists)
        XCTAssertTrue(app.buttons["Add extra usage"].firstMatch.isEnabled)
        capture("extra-usage-small-medium")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(app.staticTexts["$99.99"].isHittable)
        capture("extra-usage-large")
    }
}

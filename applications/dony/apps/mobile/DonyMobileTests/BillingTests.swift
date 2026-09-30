import XCTest
@testable import DonyMobile

final class BillingTests: XCTestCase {
    func testAddOnLabelsCompareWithTheCurrentPlan() {
        let expected = [BillingPlan.pro: [100, 250, 500], .plus: [20, 50, 100]]
        for (plan, percentages) in expected {
            XCTAssertEqual(UsagePack.all.map { $0.percent(for: plan) }, percentages)
        }
        XCTAssertEqual(UsagePack(size: 20).title(for: .pro), "Double your limit")
        XCTAssertEqual(UsagePack(size: 20).title(for: .plus), "Add 20% more usage")
        XCTAssertEqual(UsagePack(size: 100).title(for: .plus), "Double your limit")
    }
    func testEachPlanHasBothBillingPeriods() {
        XCTAssertEqual(BillingPlan.allCases.flatMap { plan in BillingPeriod.allCases.map { plan.productID($0) } }.count, 6)
        XCTAssertEqual(BillingPlan.connect.next, .pro)
        XCTAssertEqual(BillingPlan.connect.productID(.yearly), "com.dony.solari.mobile.connect.yearly")
        XCTAssertEqual(BillingPlan.pro.next, .plus)
        XCTAssertNil(BillingPlan.plus.next)
        XCTAssertEqual(BillingPlan.plus.title, "Max")
        XCTAssertEqual(BillingPlan.plus.productID(.monthly), "com.dony.solari.mobile.plus.monthly")
    }
}

import Foundation

enum BillingPlan: String, Codable, CaseIterable, Identifiable {
    // Keep plus as the stored/API value and App Store product ID for Max.
    case connect, pro, plus
    var id: String { rawValue }
    var title: String { switch self { case .connect: "Connect"; case .pro: "Pro"; case .plus: "Max" } }
    var multiplier: Int { switch self { case .connect: 0; case .pro: 1; case .plus: 5 } }
    var next: BillingPlan? { switch self { case .connect: .pro; case .pro: .plus; case .plus: nil } }
    func productID(_ period: BillingPeriod) -> String { "com.dony.solari.mobile.\(rawValue).\(period.rawValue)" }
}
enum BillingPeriod: String, Codable, CaseIterable {
    case monthly, yearly
    var title: String { self == .monthly ? "Monthly" : "Yearly" }
    var unit: String { self == .monthly ? "month" : "year" }
}
struct BillingStatus: Codable {
    let accountToken: String
    let configured: Bool
    let plan: BillingPlan?
    let period: BillingPeriod?
    let monthlyUsedPercent: Double
    let extraRemainingPercent: Double
    let resetsAt: String?
    let expiresAt: String?
    let canRunCloud: Bool
    let limitReached: Bool
    var canUseRemoteDesktop: Bool? = nil
    var hasRemoteDesktop: Bool { canUseRemoteDesktop == true }
}
struct UsagePack: Identifiable {
    let size: Int
    var id: String { "com.dony.solari.mobile.extra.\(size)" }
    static let all = [UsagePack(size: 20), UsagePack(size: 50), UsagePack(size: 100)]
    func percent(for plan: BillingPlan) -> Int { size * 5 / max(1, plan.multiplier) }
    func title(for plan: BillingPlan) -> String {
        let percent = percent(for: plan)
        return percent == 100 ? "Double your limit" : "Add \(percent)% more usage"
    }
}

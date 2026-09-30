import Foundation
import Observation
import StoreKit
import SuperwallKit

@MainActor
@Observable
final class BillingStore {
    private(set) var products: [String: StoreProduct] = [:]
    private(set) var busy = false
    private(set) var loading = false
    var message: String?
    var error: String?
    private var companion: CompanionStore?
    private var updates: Task<Void, Never>?
    private var identity: String?
    private var synchronizing = false
    private var needsSync = false
    private var acknowledged = Set<String>()
    private let configured: Bool

    init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "DonySuperwallPublicKey") as? String ?? ""
        configured = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil && !DonyMobileApp.isUITesting && !key.isEmpty && !key.hasPrefix("$(")
        if configured && !Superwall.isInitialized { Superwall.configure(apiKey: key) }
    }
    var ready: Bool {
        if DonyMobileApp.isStoreKitScreenshots { return products.count == 9 }
        return configured && companion?.cloudStatus?.billing?.configured == true
    }
    func price(_ id: String) -> String? { products[id]?.localizedPrice }
    func monthlyPrice(_ id: String) -> String? { products[id]?.monthlyPrice }
    func yearlySavings(_ plan: BillingPlan) -> Int? {
        guard let monthly = products[plan.productID(.monthly)],
              let yearly = products[plan.productID(.yearly)],
              monthly.currencyCode == yearly.currencyCode, monthly.price > 0 else { return nil }
        let savings = (1 - yearly.price / (monthly.price * 12)) * 100
        let percent = Int(NSDecimalNumber(decimal: savings).doubleValue.rounded(.down))
        return percent > 0 ? percent : nil
    }

    func attach(_ companion: CompanionStore) async {
        self.companion = companion
        if DonyMobileApp.isStoreKitScreenshots { await refresh(); return }
        if updates == nil {
            updates = Task { [weak self] in
                for await _ in StoreKit.Transaction.updates {
                    guard let self, !Task.isCancelled else { return }
                    await self.synchronize()
                }
            }
        }
        await refresh()
    }
    func refresh() async {
        #if DEBUG && targetEnvironment(simulator)
        if DonyMobileApp.isStoreKitScreenshots {
            loading = true
            defer { loading = false }
            do {
                let ids = BillingPlan.allCases.flatMap { plan in BillingPeriod.allCases.map { plan.productID($0) } } + UsagePack.all.map(\.id)
                let loaded = try await Product.products(for: ids)
                products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, StoreProduct(sk2Product: $0)) })
            } catch { self.error = error.localizedDescription }
            return
        }
        #endif
        guard let companion, companion.isCloud else {
            if configured, identity != nil { Superwall.shared.reset() }
            identity = nil; acknowledged.removeAll(); products = [:]
            return
        }
        do {
            try await companion.refreshCloudAccount()
            guard let status = companion.cloudStatus?.billing else { return }
            if status.accountToken != identity {
                identity = status.accountToken
                acknowledged.removeAll()
                if configured { Superwall.shared.identify(userId: status.accountToken) }
            }
            guard ready else { return }
            await loadProducts()
            await synchronize()
        } catch { self.error = error.localizedDescription }
    }
    private func loadProducts() async {
        let ids = BillingPlan.allCases.flatMap { plan in BillingPeriod.allCases.map { plan.productID($0) } } + UsagePack.all.map(\.id)
        guard products.count < ids.count, !loading else { return }
        loading = true
        defer { loading = false }
        let loaded = await Superwall.shared.products(for: Set(ids))
        products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.productIdentifier, $0) })
    }
    func purchase(_ id: String) async {
        if DonyMobileApp.isStoreKitScreenshots {
            message = "Local StoreKit preview. Use an Apple sandbox purchase on your iPhone to test activation."
            return
        }
        guard !busy, let companion else { return }
        busy = true; error = nil; message = nil
        defer { busy = false }
        await refresh()
        guard ready, let product = products[id], let account = identity else {
            error = "Purchases aren’t available yet. You can keep using your to-do list or connect your Mac."
            return
        }
        // Superwall sets Apple's appAccountToken to this server-issued UUID.
        Superwall.shared.identify(userId: account)
        switch await Superwall.shared.purchase(product) {
        case .purchased:
            guard companion.cloudStatus?.billing?.accountToken == account else { return }
            do {
                guard let result = await StoreKit.Transaction.latest(for: id),
                      case .verified(let transaction) = result else {
                    throw CompanionFailure("Apple’s purchase confirmation is still arriving. Please retry activation.")
                }
                guard transaction.appAccountToken?.uuidString.lowercased() == account.lowercased() else {
                    error = "This purchase belongs to another Dony account. Sign in to that account to restore it."
                    return
                }
                _ = try await companion.syncBilling(transactions: [result.jwsRepresentation], accountToken: account)
                acknowledged.insert(result.jwsRepresentation)
                error = nil
                message = "Your purchase is ready."
            } catch { self.error = "Your purchase is saved by Apple. Retry activation without another charge. \(error.localizedDescription)" }
        case .pending: message = "Your purchase is waiting for approval. Your access will update when Apple confirms it."
        case .cancelled: break
        case .failed(let failure): error = failure.localizedDescription
        }
    }
    func restore() async {
        if DonyMobileApp.isStoreKitScreenshots { return }
        guard !busy, ready else { return }
        busy = true; error = nil; message = nil
        defer { busy = false }
        switch await Superwall.shared.restorePurchases() {
        case .restored:
            acknowledged.removeAll()
            await synchronize(reportOtherAccount: true)
            if error == nil { message = (companion?.cloudStatus?.billing?.canRunCloud == true || companion?.cloudStatus?.billing?.hasRemoteDesktop == true) ? "Your purchases are restored." : "No active purchases were found for this Dony account." }
        case .failed(let failure): error = failure?.localizedDescription ?? "Couldn’t restore purchases. Please try again."
        }
    }
    // History includes finished consumables on iOS 18. Server receipts make every retry idempotent.
    func synchronize(reportOtherAccount: Bool = false) async {
        if DonyMobileApp.isStoreKitScreenshots { return }
        guard ready, let companion, let identity else { return }
        if synchronizing { needsSync = true; return }
        synchronizing = true
        defer {
            synchronizing = false
            if needsSync { needsSync = false; Task { await self.synchronize() } }
        }
        do {
            var otherAccount = false
            for await result in StoreKit.Transaction.all {
                guard self.identity == identity else { return }
                guard case .verified(let transaction) = result,
                      transaction.productID.hasPrefix("com.dony.solari.mobile.") else { continue }
                guard transaction.appAccountToken?.uuidString.lowercased() == identity.lowercased() else {
                    otherAccount = true; continue
                }
                let signed = result.jwsRepresentation
                if acknowledged.contains(signed) { continue }
                _ = try await companion.syncBilling(transactions: [signed], accountToken: identity)
                acknowledged.insert(signed)
            }
            try await companion.refreshCloudAccount()
            if reportOtherAccount && otherAccount && companion.cloudStatus?.billing?.canRunCloud != true && companion.cloudStatus?.billing?.hasRemoteDesktop != true {
                error = "Purchases were found for another Dony account. Sign in to that account to restore them."
            }
        } catch { self.error = "Your purchase hasn’t been confirmed yet. Tap Retry activation; you won’t be charged again. \(error.localizedDescription)" }
    }
}

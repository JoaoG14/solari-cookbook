import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(CompanionStore.self) private var companion
    @Environment(BillingStore.self) private var billing
    @State private var period = BillingPeriod.yearly
    @State private var allPlans = false
    var exhausted = false
    var focusConnect = false
    var back: (() -> Void)? = nil
    var close: () -> Void
    private var status: BillingStatus? { companion.cloudStatus?.billing }
    private var current: BillingPlan { status?.plan == .plus ? .plus : .pro }
    private var ink: Color { Color("TodoInk") }
    private var surface: Color { Color("TodoSurface") }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(spacing: 28) {
                        if exhausted { extraUsage }
                        else if allPlans { plans }
                        else { introduction }
                        purchaseFeedback
                        legal
                    }
                    .padding(.horizontal, 24).padding(.bottom, 24)
                    .frame(maxWidth: 520).frame(maxWidth: .infinity)
                }
                .onChange(of: allPlans) { _, showing in
                    if showing && focusConnect {
                        Task { @MainActor in
                            await Task.yield()
                            scroll.scrollTo("plan-connect", anchor: .top)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !allPlans && !exhausted { subscribeFooter }
                }
                .background(surface.ignoresSafeArea())
                .foregroundStyle(ink)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if let back, !allPlans && !exhausted {
                            Button(action: back) { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                                .accessibilityLabel("Previous screen").accessibilityIdentifier("onboarding-back")
                        } else if allPlans && !exhausted {
                            Button { allPlans = false } label: { Image(systemName: "chevron.left") }
                                .accessibilityLabel("Back to subscription")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close", systemImage: "xmark", action: close)
                            .labelStyle(.iconOnly)
                            .accessibilityLabel(status?.plan == nil ? "Continue with basic to-do list" : "Close plans")
                            .accessibilityIdentifier("paywall-close")
                    }
                }
            }
        }
        .tint(ink)
        .task {
            await billing.refresh()
            if let period = status?.period { self.period = period }
            if (status?.plan != nil || focusConnect) && !exhausted { allPlans = true }
        }
        .onChange(of: billing.message) { _, message in
            guard message == "Your purchase is ready." else { return }
            if status?.plan == .connect {
                if companion.connection?.pairedDesktop == nil { companion.showingPairing = true }
                else {
                    Task {
                        do { try await companion.setCloudSettings(executionTarget: "computer"); close() }
                        catch { billing.error = error.localizedDescription }
                    }
                }
            } else if status?.canRunCloud == true || status?.hasRemoteDesktop == true { close() }
        }
        .onChange(of: companion.showingPairing) { _, showing in
            if !showing && companion.connection?.pairedDesktop != nil {
                Task {
                    do { try await companion.setCloudSettings(executionTarget: "computer"); close() }
                    catch { billing.error = error.localizedDescription }
                }
            }
        }
        .fullScreenCover(isPresented: Binding(get: { companion.showingPairing }, set: { companion.showingPairing = $0 })) {
            PairingView()
        }
    }

    private var periodPicker: some View {
        VStack(spacing: 8) {
            Picker("Billing period", selection: $period) {
                ForEach(BillingPeriod.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("billing-period")
            Text(period == .yearly ? "Save with yearly billing. Cloud AI usage refreshes monthly." : "Connect your Mac, or choose a plan with cloud AI.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
    private var introduction: some View {
        VStack(spacing: 24) {
            OnboardingFace(size: 72).padding(.top, 4).accessibilityHidden(true)
            Text("A todo list that will do itself")
                .font(.largeTitle.bold()).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 26) {
                benefit("Turn to-dos into progress", detail: "Get help planning, researching, and drafting.", icon: "checkmark.circle")
                benefit("Help wherever you are", detail: "Your agents work even when your Mac is off.", icon: "cloud")
                benefit("Keep everything together", detail: "Your tasks, chats, and work across devices.", icon: "rectangle.on.rectangle")
                benefit("You stay in control", detail: "Review the work before marking it complete.", icon: "hand.raised")
            }

        }
    }
    private var subscribeFooter: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                billingPeriodCard(.monthly)
                billingPeriodCard(.yearly)
            }
            .padding(.top, 8)
            Text(billing.price(BillingPlan.pro.productID(period)).map {
                period == .yearly ? "\($0) billed yearly" : "\($0) billed monthly"
            } ?? "Price unavailable")
                .font(.subheadline.weight(.semibold))
            purchaseButton("Subscribe", id: BillingPlan.pro.productID(period))
            Button("View all plans") { allPlans = true }
                .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("view-all-plans")
        }
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 4)
        .frame(maxWidth: 520).frame(maxWidth: .infinity)
        .background(surface)
    }
    private func billingPeriodCard(_ option: BillingPeriod) -> some View {
        let selected = period == option
        return Button { period = option } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title).font(.subheadline)
                    Text(billing.monthlyPrice(BillingPlan.pro.productID(option)).map { "\($0)/mo" } ?? "Unavailable")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? ink : ink.opacity(0.15))
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(selected ? ink.opacity(0.04) : surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selected ? ink : ink.opacity(0.08), lineWidth: selected ? 2 : 1)
            }
            .overlay(alignment: .top) {
                if option == .yearly, (billing.yearlySavings(.pro) ?? 0) >= 17 {
                    Text("2 months free")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(surface)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(ink, in: Capsule())
                        .offset(y: -10)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("billing-\(option.rawValue)")
        .accessibilityLabel("\(option.title), \(billing.monthlyPrice(BillingPlan.pro.productID(option)) ?? "Price unavailable") per month")
        .accessibilityValue(option == .yearly && (billing.yearlySavings(.pro) ?? 0) >= 17 ? "2 months free" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var plans: some View {
        VStack(spacing: 20) {
            Text("Choose your plan").font(.largeTitle.bold())
            periodPicker
            ForEach([BillingPlan.plus, .pro]) { plan in planCard(plan) }
            planCard(.connect)
            macCard
        }
    }
    private var extraUsage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(status?.limitReached == true ? "Keep going" : "More room to get things done")
                .font(.largeTitle.bold())
            if let reset = status?.resetsAt {
                Text("Your \(current.title) allowance refreshes \(syncDate(reset).formatted(date: .abbreviated, time: .omitted)).")
                    .foregroundStyle(.secondary)
            }
            ForEach(UsagePack.all) { pack in
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(pack.title(for: current)).font(.title3.bold())
                        Spacer()
                        Text(billing.price(pack.id) ?? "Unavailable").font(.subheadline.weight(.semibold))
                    }
                    Text("An extra \(pack.percent(for: current))% of your normal \(current.title) monthly allowance. One-time purchase. Unused extras never expire.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    purchaseButton("Add extra usage", id: pack.id)
                }.card(ink: ink)
            }
            if let next = current.next {
                Text("Need more every month?").font(.title2.bold()).padding(.top, 8)
                periodPicker
                planCard(next)
                Button("View all plans") { allPlans = true }.frame(minHeight: 44)
                if allPlans { ForEach(BillingPlan.allCases.filter { $0 != next && $0 != .connect }) { plan in planCard(plan) } }
            }
            planCard(.connect)
            macCard
            Button("Wait for my next reset", action: close).frame(maxWidth: .infinity, minHeight: 44)
        }
    }
    private func planCard(_ plan: BillingPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(plan.title).font(.title2.bold())
                Spacer()
                priceLabel(plan)
            }
            Text(plan == .connect
                 ? "Control Dony on your Mac from anywhere. Send tasks, reply to your agents, and review their work from your iPhone."
                 : plan == .pro ? "Connect included, plus cloud AI for everyday help." : "Connect included, plus 5× the cloud AI usage of Pro.")
                .font(.subheadline).foregroundStyle(.secondary)
            if plan == .connect {
                Text("Uses your Mac’s AI connection. Keep your Mac awake, online, and Dony open. Cloud AI usage is sold separately.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if status?.plan == plan && status?.period == period {
                Text("Current plan").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
            } else {
                purchaseButton(status?.plan == nil ? "Subscribe to \(plan.title)" : "Choose \(plan.title)", id: plan.productID(period))
            }
        }.card(ink: ink).id("plan-\(plan.rawValue)").accessibilityIdentifier("plan-\(plan.rawValue)")
    }
    private var macCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Use your Mac", systemImage: "desktopcomputer").font(.title2.bold())
            Text("Use your ChatGPT subscription through Dony on your Mac. Keep your Mac awake with Dony open and both devices on the same Wi-Fi.")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("No Dony subscription needed.").font(.footnote.weight(.medium))
            Button("Connect to Mac") { companion.showingPairing = true }
                .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                .background(ink.opacity(0.09), in: Capsule())
        }.card(ink: ink)
    }
    private func priceLabel(_ plan: BillingPlan) -> some View {
        Text(billing.price(plan.productID(period)).map { "\($0)/\(period.unit)" } ?? "Price unavailable")
            .font(.subheadline.weight(.semibold))
    }
    private func purchaseButton(_ title: String, id: String) -> some View {
        Button { Task { await billing.purchase(id) } } label: {
            HStack {
                if billing.busy { ProgressView().tint(surface) }
                Text(title).font(.headline)
            }
            .foregroundStyle(surface).frame(maxWidth: .infinity, minHeight: 56)
            .background(ink, in: Capsule())
        }
        .disabled(billing.busy || billing.loading || !billing.ready || billing.price(id) == nil || privacyURL == nil)
        .opacity(billing.ready && billing.price(id) != nil && privacyURL != nil ? 1 : 0.45)
    }
    @ViewBuilder private var purchaseFeedback: some View {
        if billing.loading { ProgressView("Loading plans…") }
        if !billing.ready {
            Text("Subscriptions are not available yet. Your basic to-do list is ready to use.").font(.footnote).foregroundStyle(.secondary)
        }
        if let message = billing.message { Text(message).font(.subheadline).accessibilityAddTraits(.updatesFrequently) }
        if let error = billing.error {
            Text(error).font(.subheadline).foregroundStyle(.red)
            Button("Retry activation") { Task { billing.error = nil; await billing.refresh() } }.frame(minHeight: 44)
        }
    }
    private var privacyURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "DonyPrivacyURL") as? String,
              let url = URL(string: value), url.scheme == "https" else { return nil }
        return url
    }
    private var legal: some View {
        VStack(spacing: 8) {
            Text("Subscriptions renew automatically unless canceled in App Store settings. The price and billing period are shown above. Apple confirms the charge and any plan change before you purchase.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 20) {
                Button("Restore purchases") { Task { await billing.restore() } }.disabled(billing.busy || !billing.ready)
                if let privacyURL { Link("Privacy", destination: privacyURL) }
                Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            }.font(.caption).frame(minHeight: 44)
        }
    }
    private func benefit(_ title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon).font(.title2).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
private extension View {
    func card(ink: Color) -> some View {
        self.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(ink.opacity(0.055), in: RoundedRectangle(cornerRadius: 26))
    }
}

struct BillingSettingsView: View {
    @Environment(CompanionStore.self) private var companion
    @Environment(BillingStore.self) private var billing
    @State private var managing = false
    var body: some View {
        Section("Plan & usage") {
            if let status = companion.cloudStatus?.billing {
                LabeledContent("Plan", value: status.plan?.title ?? "Basic")
                if status.plan == .pro || status.plan == .plus {
                    ProgressView(value: status.monthlyUsedPercent, total: 100) {
                        Text("\(Int(status.monthlyUsedPercent))% of monthly allowance used")
                    }
                    if let reset = status.resetsAt {
                        Text("Refreshes \(syncDate(reset).formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if status.extraRemainingPercent > 0 {
                    Text("Extra usage remaining: \(status.extraRemainingPercent.formatted(.number.precision(.fractionLength(0...1))))% of a \(status.plan == .plus ? "Max" : "Pro") monthly allowance")
                        .font(.subheadline)
                }
                Button(status.plan == nil ? "View plans" : "Change plan") { companion.showingPaywall = true }
                if status.plan == .pro || status.plan == .plus || status.extraRemainingPercent > 0 {
                    Button("Add extra usage") { companion.showingUsagePacks = true; companion.showingPaywall = true }
                }
                Button("Manage subscription") { managing = true }
                    .manageSubscriptionsSheet(isPresented: $managing)
                Button("Restore purchases") { Task { await billing.restore() } }.disabled(billing.busy || !billing.ready)
                if let error = billing.error { Text(error).font(.caption).foregroundStyle(.red) }
                if let message = billing.message { Text(message).font(.caption) }
            } else {
                Text("Sign in to view your plan and usage.").foregroundStyle(.secondary)
            }
        }
        .task { await billing.refresh() }
        .listRowBackground(Color("TodoInk").opacity(0.045))
    }
}

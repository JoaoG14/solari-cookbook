import SwiftUI
import QuickLook

struct RootTabView: View {
    @Environment(TodoStore.self) private var todos
    @AppStorage("appearance") private var appearance = Appearance.system
    @AppStorage("inboxEnabled") private var inboxEnabled = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var chats = DemoChatStore(isDemo: DonyMobileApp.isUITesting && !DonyMobileApp.isCompanionTesting)
    @State private var companion = DonyMobileApp.makeCompanionStore()
    @State private var onboarding: MobileOnboarding
    @State private var billing = BillingStore()

    @State private var selectedTab = "todos"
    private let connectBlue = Color(red: 0.08, green: 0.32, blue: 0.78)

    private var showsWorkspace: Bool {
        onboarding.completed && (companion.isConnected || companion.isDemo)
    }

    init(defaults: UserDefaults = .standard) {
        _onboarding = State(initialValue: MobileOnboarding(defaults: defaults))
    }

    var body: some View {
        Group {
            if showsWorkspace {
                tabs
            } else {
                MobileOnboardingView(progress: onboarding) { selectedTab = "todos" }
            }
        }
        .environment(chats)
        .environment(companion)
        .environment(billing)
        .safeAreaInset(edge: .top, spacing: 0) {
            if showsWorkspace, companion.shouldShowConnectBanner {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "wifi.slash").accessibilityHidden(true)
                            Text("Away from your Mac?")
                        }
                        .font(.subheadline.weight(.semibold))
                        Text("Connect from anywhere with Dony Connect. Your Mac needs to be awake and online.")
                            .font(.footnote).foregroundStyle(.white.opacity(0.9))
                        Button("Explore Connect") { companion.showConnectPlan() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(connectBlue)
                            .padding(.horizontal, 16).frame(minHeight: 44)
                            .background(.white, in: Capsule())
                            .padding(.top, 8)
                            .accessibilityIdentifier("explore-connect")
                    }
                    Spacer(minLength: 0)
                    Button { companion.connectBannerDismissed = true } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }.accessibilityLabel("Dismiss Connect suggestion")
                }
                .padding(.leading, 20).padding(.trailing, 8).padding(.vertical, 12)
                .foregroundStyle(.white)
                .buttonStyle(.plain)
                .background(connectBlue, in: RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("connect-plan-banner")
            } else if showsWorkspace, let message = companion.connectionError {
                HStack(spacing: 12) {
                    Text(message).font(.subheadline)
                    Spacer(minLength: 0)
                    Button(companion.needsCloudSignIn ? "Sign in" : "Retry") {
                        if companion.needsCloudSignIn { companion.showingCloudSignIn = true }
                        else { Task { await companion.sync() } }
                    }
                    .frame(minHeight: 44)
                }
                .padding(.horizontal, 20)
                .background(Color("TodoSurface"))
                .accessibilityIdentifier("connection-error")
            }
        }
        .task {
            if DonyMobileApp.isStoreKitScreenshots && !ProcessInfo.processInfo.arguments.contains("--connect-banner-testing") {
                companion.showingUsagePacks = ProcessInfo.processInfo.arguments.contains("--usage-packs")
                companion.showingPaywall = true
            }
            companion.attach(todos: todos, chats: chats)
            companion.setActive(scenePhase == .active)
            await billing.attach(companion)
        }
        .onChange(of: companion.connection?.accountId) { _, _ in Task { await billing.refresh() } }
        .onChange(of: scenePhase) { _, phase in
            companion.setActive(phase == .active)
            if phase == .active { Task { await billing.refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: CloudNotifications.tokenChanged)) { _ in Task { try? await companion.registerCloudPush() } }
        .onReceive(NotificationCenter.default.publisher(for: CloudNotifications.opened)) { event in
            guard let threadID = event.userInfo?["threadId"] as? String else { return }
            Task { await companion.sync(); companion.notificationThreadID = threadID; selectedTab = "employees" }
        }
        .onOpenURL { url in
            if url.scheme == "dony-solari-mobile", url.host == "pair" { selectedTab = "settings"; companion.pairingURL = url; companion.showingPairing = true }
        }
        .sheet(isPresented: Binding(get: { companion.showingCloudSignIn }, set: { companion.showingCloudSignIn = $0 })) {
            NavigationStack {
                Form { CloudSettingsView() }
                    .navigationTitle("Sign in to Dony")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { companion.showingCloudSignIn = false }
                        }
                    }
            }
            .environment(companion)
        }
        .fullScreenCover(isPresented: Binding(get: { companion.showingPaywall }, set: { companion.showingPaywall = $0 })) {
            PaywallView(exhausted: companion.showingUsagePacks, focusConnect: companion.showingConnectPlan) {
                companion.showingPaywall = false; companion.showingUsagePacks = false; companion.showingConnectPlan = false
            }.environment(companion).environment(billing).environment(todos)
        }
        .fullScreenCover(isPresented: Binding(get: { companion.showingPairing && !companion.showingPaywall && onboarding.completed }, set: { companion.showingPairing = $0 })) { PairingView().environment(companion).environment(todos) }
        .quickLookPreview(Binding(get: { companion.previewURL }, set: { companion.previewURL = $0 }))
        .alert("Dony connection", isPresented: Binding(get: { companion.errorMessage != nil }, set: { if !$0 { companion.errorMessage = nil } })) {
            Button("OK", role: .cancel) { companion.errorMessage = nil }
        } message: { Text(companion.errorMessage ?? "") }
        .preferredColorScheme(appearance.colorScheme)
        .alert("Couldn’t save your to-dos", isPresented: Binding(
            get: { todos.errorMessage != nil },
            set: { if !$0 { todos.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { todos.errorMessage = nil }
        } message: {
            Text(todos.errorMessage ?? "")
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Employees", systemImage: "bubble.fill", value: "employees") {
                ChatListView()
            }
            Tab("To-do List", image: "TodoTabIcon", value: "todos") {
                NavigationStack { TodoListView() }
            }
            if inboxEnabled {
                Tab("Inbox", systemImage: "tray.fill", value: "inbox") {
                    NavigationStack { InboxView() }
                }
                .badge(companion.inboxPendingCount)
            }
            Tab("Settings", systemImage: "gearshape.fill", value: "settings") {
                NavigationStack { SettingsView() }
            }
        }
    }
}

import AuthenticationServices
import SwiftData
import SwiftUI

extension EnvironmentValues {
    @Entry var isOnboardingPreview = false
}

struct MobileOnboardingView: View {
    @Bindable var progress: MobileOnboarding
    let didFinish: () -> Void
    @Environment(CompanionStore.self) private var companion
    @Environment(TodoStore.self) private var todos
    @Environment(\.isOnboardingPreview) private var isPreview
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var firstTasksTitleSize = 42
    @State private var signingInProvider: CloudSignInProvider?
    private var busy: Bool { signingInProvider != nil }
    @State private var error: String?

    private var selectedCount: Int { progress.tasks.filter(\.selected).count }
    private var isDemoSession: Bool {
        (DonyMobileApp.isOnboardingTesting || isPreview) && companion.isDemo
    }
    private var canUseWorkspace: Bool {
        companion.isConnected && !companion.needsCloudSignIn || isDemoSession
    }

    var body: some View {
        Group {
            if progress.completed || progress.step == -1 {
                OnboardingWelcomeView(signingInProvider: signingInProvider, signInWithApple: signInWithApple, signIn: signIn)
            } else if progress.step == 6 {
                PaywallView(back: { progress.step = 5 }, close: finish)
            } else if progress.step < 4 {
                OnboardingBenefitsView(selection: $progress.step)
            } else {
                setup
            }
        }
        .background(OnboardingPalette.background.ignoresSafeArea())
        .foregroundStyle(OnboardingPalette.foreground)
        .tint(OnboardingPalette.foreground)
        .onAppear {
            if !canUseWorkspace { progress.step = -1 }
            else if progress.step == -1 && !isDemoSession { progress.step = 0 }
        }
        .onChange(of: companion.showingPairing) { _, showing in
            guard !showing && companion.isConnected && !companion.isCloud else { return }
            if progress.step == -1 { progress.step = 4 }
            else if progress.step == 6 { finish() }
        }
        .alert("Couldn’t finish setup", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private var setup: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    progress.step -= 1
                } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("Previous screen").accessibilityIdentifier("onboarding-back")
                Spacer()
            }.padding(.horizontal, 16).disabled(busy)

            if progress.step == 5 {
                ConnectorsView(onboarding: true, onOnboardingContinue: { progress.step = 6 })
                .environment(\.isOnboardingPreview, isDemoSession)
            } else if progress.step == 4 {
                firstTasks
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if progress.step != 5 && !(progress.step == 4 && typeSize.isAccessibilitySize) { footer }
        }
        .buttonStyle(OnboardingButtonStyle())
    }

    private var firstTasks: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 24)
                    Text("Let's start\nyour list")
                        .font(.system(size: firstTasksTitleSize, weight: .bold))
                        .tracking(-1.2).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityLabel("Let's start your list")
                    Text("Choose the tasks you’d like help with.")
                        .font(.subheadline).foregroundStyle(OnboardingPalette.muted)
                        .multilineTextAlignment(.center).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                    VStack(spacing: 0) {
                        ForEach($progress.tasks) { $task in
                            Button { task.selected.toggle() } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: task.selected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 23, weight: .regular))
                                        .foregroundStyle(task.selected ? Color(uiColor: .systemBlue) : OnboardingPalette.foreground.opacity(0.25))
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(task.title)
                                            .font(.body).multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                        if let sourceLabel = task.sourceLabel {
                                            Text(sourceLabel)
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(OnboardingPalette.muted)
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                                .padding(.horizontal, 9).padding(.vertical, 4)
                                                .background(OnboardingPalette.foreground.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 18)
                                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .accessibilityValue(task.selected ? "Selected" : "Not selected")
                            .accessibilityAddTraits(task.selected ? .isSelected : [])
                        }
                    }
                    .padding(.top, typeSize.isAccessibilitySize ? 28 : 48)
                    Text("Nothing starts until you ask.")
                        .font(.footnote).foregroundStyle(OnboardingPalette.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 22)
                    Spacer(minLength: 24)
                    if typeSize.isAccessibilitySize { footer.padding(.horizontal, -24) }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 440).frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Button { advance() } label: {
                HStack(spacing: 10) {
                    if busy { ProgressView().tint(OnboardingPalette.background) }
                    Text(busy ? "Loading…" : buttonTitle).font(.body.weight(.medium))
                }
                .foregroundStyle(OnboardingPalette.background)
                .padding(.horizontal, 18).padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 51)
                .background(OnboardingPalette.foreground, in: Capsule())
                .opacity(progress.step == 4 && selectedCount == 0 ? 0.4 : 1)
            }
            .disabled(busy || progress.step == 4 && selectedCount == 0)
            .accessibilityIdentifier("onboarding-continue")
            Button {
                if progress.step == 4 {
                    for index in progress.tasks.indices { progress.tasks[index].selected = false }
                    progress.step = 5
                }
                else if isPreview && companion.isDemo { finish() }
                else { companion.showingPairing = true }
            } label: {
                Text(progress.step == 4 ? "Start with an empty list" : "Use Dony on my Mac instead")
                    .font(.footnote).foregroundStyle(OnboardingPalette.muted)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(busy).accessibilityIdentifier("onboarding-secondary")
        }
        .padding(.horizontal, progress.step == 4 ? 24 : 22).padding(.top, 12).padding(.bottom, 4)
        .frame(maxWidth: progress.step == 4 ? 440 : .infinity).frame(maxWidth: .infinity)
        .background(OnboardingPalette.background)
        .buttonStyle(OnboardingButtonStyle())
    }

    private var buttonTitle: String {
        if progress.step == 4 { return "Add selected tasks" }
        guard progress.step == 6 else { return "Continue" }
        return "Continue"
    }

    private func advance() {
        if progress.step == 4 { progress.step = 5; return }
        finish()
    }

    private func signIn() {
        guard !busy else { return }
        signingInProvider = .google
        Task {
            defer { signingInProvider = nil }
            do {
                if !isDemoSession { try await companion.signInCloud(importTodos: !progress.completed) }
                progress.step = 0
            } catch let failure as ASWebAuthenticationSessionError where failure.code == .canceledLogin { }
            catch { self.error = error.localizedDescription }
        }
    }

    private func signInWithApple() {
        guard !busy else { return }
        signingInProvider = .apple
        Task {
            defer { signingInProvider = nil }
            do {
                if !isDemoSession { try await companion.signInCloudWithApple(importTodos: !progress.completed) }
                progress.step = 0
            } catch let failure as ASAuthorizationError where failure.code == .canceled { }
            catch { self.error = error.localizedDescription }
        }
    }

    private func finish() {
        guard canUseWorkspace else { progress.step = -1; return }
        companion.setMode("off")
        guard companion.mode == "off" else { return }
        if progress.finish(todos: todos) { didFinish() }
    }


}

#if DEBUG
@MainActor
private struct OnboardingPreview: View {
    @State private var progress: MobileOnboarding
    @State private var companion = CompanionStore(demo: true)
    @State private var chats = DemoChatStore()
    @State private var todos: TodoStore

    init() {
        let defaults = UserDefaults(suiteName: "DonyOnboardingPreview-\(UUID().uuidString)")!
        let progress = MobileOnboarding(defaults: defaults)
        _progress = State(initialValue: progress)
        let container = try! ModelContainer(for: TodoItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        _todos = State(initialValue: try! TodoStore(container: container, defaults: defaults, seedExamples: false))
    }

    var body: some View {
        Group {
            if progress.completed {
                NavigationStack {
                    TodoListView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Restart onboarding") {
                                    progress.step = -1
                                    progress.completed = false
                                }
                            }
                        }
                }
            } else {
                MobileOnboardingView(progress: progress, didFinish: {})
            }
        }
        .environment(companion)
        .environment(todos)
        .environment(chats)
        .environment(BillingStore())
        .environment(\.isOnboardingPreview, true)
    }
}

#Preview("Onboarding") {
    OnboardingPreview()
}
#endif

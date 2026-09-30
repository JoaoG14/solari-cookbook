import AuthenticationServices
import SwiftUI

struct CloudSettingsView: View {
    @Environment(CompanionStore.self) private var companion
    @State private var busy = false
    @State private var signingInProvider: CloudSignInProvider?
    @State private var bringTodos = true
    @State private var confirmingAccountDeletion = false
    var body: some View {
        Section {
            if companion.isCloud {
                if companion.needsCloudSignIn {
                    Button("Sign in again with Apple") { perform(provider: .apple) { try await companion.signInCloudWithApple(importTodos: false) } }
                    Button("Sign in again with Google") { perform(provider: .google) { try await companion.signInCloud(importTodos: false) } }
                }
                Button("Enable notifications") { perform { try await companion.enableCloudNotifications() } }
                Button("Sign out", role: .destructive) { perform { try await companion.signOutCloud() } }
                Button("Delete account", role: .destructive) {
                    confirmingAccountDeletion = true
                }
                .accessibilityIdentifier("delete-account")
            } else {
                Button { perform(provider: .apple) { try await companion.signInCloudWithApple(importTodos: bringTodos) } } label: {
                    HStack { Label("Sign in with Apple", systemImage: "apple.logo"); Spacer(); if signingInProvider == .apple { ProgressView() } }
                }
                .accessibilityIdentifier("cloud-apple-sign-in")
                Button { perform(provider: .google) { try await companion.signInCloud(importTodos: bringTodos) } } label: {
                    HStack { Label("Sign in with Google", systemImage: "person.crop.circle"); Spacer(); if signingInProvider == .google { ProgressView() } }
                }
                .accessibilityIdentifier("cloud-sign-in")
                Toggle("Bring my existing to-dos", isOn: $bringTodos)
            }
        } header: { Text("Dony Cloud") } footer: {
            Text(companion.isCloud
                 ? "Your to-do list syncs across devices. Choose a plan for cloud AI, or connect your Mac."
                 : "Your agents, tasks, and chats, available wherever you are.")
        }
        .disabled(busy)
        .listRowBackground(Color("TodoInk").opacity(0.045))
        .task { if companion.isCloud { try? await companion.refreshCloudAccount() } }
        .alert("Delete your Dony account?", isPresented: $confirmingAccountDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Delete account", role: .destructive) {
                perform { try await companion.deleteCloudAccount() }
            }
        } message: {
            Text("This permanently deletes your Dony account, cloud to-dos, chats, agents, and connected tools. This can’t be undone. Deleting your account doesn’t cancel an App Store subscription. Cancel it in Manage subscription first.")
        }
    }
    private func perform(provider: CloudSignInProvider? = nil, _ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        signingInProvider = provider
        Task {
            defer { busy = false; signingInProvider = nil }
            do { try await action() }
            catch let error as ASAuthorizationError where error.code == .canceled { }
            catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin { }
            catch { companion.errorMessage = error.localizedDescription }
        }
    }
}

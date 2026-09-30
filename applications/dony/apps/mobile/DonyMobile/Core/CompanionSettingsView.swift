import SwiftUI

struct CompanionSettingsView: View {
    @Environment(CompanionStore.self) private var companion
    @State private var confirmingDisconnect = false
    @State private var busy = false

    var body: some View {
        Section("My computer") {
            if companion.isCloud {
                Picker("Run agents on", selection: Binding(get: { companion.executionTarget }, set: { value in
                    perform { try await companion.setCloudSettings(executionTarget: value) }
                })) {
                    Text("Cloud").tag("cloud")
                    Text("My computer").tag("computer")
                }
                .disabled(busy)
                .accessibilityIdentifier("cloud-execution-picker")
                if let desktop = companion.connection?.pairedDesktop {
                    Label(desktop.desktopName, systemImage: "desktopcomputer")
                } else {
                    Button("Connect my computer", systemImage: "qrcode") { companion.showingPairing = true }
                }
                Text(companion.cloudStatus?.billing?.hasRemoteDesktop == true
                     ? "Connect from anywhere is included. Keep your Mac awake, online, and Dony open."
                     : "Run agents using your Mac’s ChatGPT connection on the same Wi-Fi. Connect, Pro, and Max add access from anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let connection = companion.connection {
                Label(connection.desktopName, systemImage: "desktopcomputer")
                Text(connection.isLocal ? "Same Wi-Fi · Free" : "Server connection")
                    .font(.caption).foregroundStyle(.secondary)
                CompanionStatusView()
                Button("Disconnect desktop", role: .destructive) { confirmingDisconnect = true }.disabled(
                    busy
                )
                .confirmationDialog(
                    "Disconnect this desktop?", isPresented: $confirmingDisconnect, titleVisibility: .visible
                ) {
                    Button("Disconnect desktop", role: .destructive) {
                        busy = true
                        Task {
                            do { try await companion.disconnect() } catch {
                                companion.errorMessage = error.localizedDescription
                            }
                            busy = false
                        }
                    }
                } message: {
                    Text(
                        "Shared tasks and chats stay on the desktop. This iPhone returns to its original local to-do list."
                    )
                }
            } else {
                Button("Connect desktop", systemImage: "qrcode") { companion.showingPairing = true }
                Text("Connect directly to your Mac on the same Wi-Fi. Free, with no Dony server.").font(
                    .caption
                ).foregroundStyle(.secondary)
            }
        }
        .listRowBackground(Color("TodoInk").opacity(0.045))

    }

    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do { try await action() } catch { companion.errorMessage = error.localizedDescription }
        }
    }
}

struct PendingChangesSettingsView: View {
    @Environment(CompanionStore.self) private var companion

    var body: some View {
        if !companion.failedChanges.isEmpty {
            Section("Changes needing attention") {
                ForEach(companion.failedChanges) { change in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(change.title).font(.headline)
                        if let message = change.command.action["message"]?.string {
                            Text(message).font(.subheadline).textSelection(.enabled)
                        }
                        if case .object(let patch) = change.command.action["patch"],
                            let title = patch["title"]?.string
                        {
                            Text("Your edit: \(title)").font(.subheadline).textSelection(.enabled)
                        }
                        Text(change.error ?? "").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            if change.command.action["type"] != "task.reorder" {
                                Button("Apply to latest version") { companion.retry(change.id) }
                            }
                            Button("Dismiss", role: .destructive) { companion.discard(change.id) }
                        }.font(.subheadline)
                    }.padding(.vertical, 6)
                }
            }
        }
    }
}

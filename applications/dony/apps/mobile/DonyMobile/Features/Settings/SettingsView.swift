import SwiftUI

struct SettingsView: View {
    @Environment(CompanionStore.self) private var companion
    @Environment(TodoStore.self) private var todos
    @Environment(DemoChatStore.self) private var chats
    @AppStorage("appearance") private var appearance = Appearance.system
    @AppStorage("inboxEnabled") private var inboxEnabled = false
    @State private var showingConnectors = false
    @State private var confirmingErase = false
    @State private var showingResetNotice = false

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image("AgentFace")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 22)
                        .opacity(0.8)
                        .frame(width: 56, height: 56)
                        .background(Color(red: 86 / 255, green: 1, blue: 97 / 255), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dony").font(.title2.weight(.semibold))
                        Text("Version \(version)")
                            .font(.subheadline)
                            .foregroundStyle(Color("TodoMuted"))
                    }
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
            }

            CloudSettingsView()
            BillingSettingsView()
            PendingChangesSettingsView()

            if let value = Bundle.main.object(forInfoDictionaryKey: "DonyPrivacyURL") as? String,
               let url = URL(string: value), url.scheme == "https" {
                Section {
                    Link("Privacy policy", destination: url)
                        .tint(Color("TodoInk"))
                }
                .listRowBackground(Color("TodoInk").opacity(0.045))
            }

            Section {
                Button { showingConnectors = true } label: {
                    HStack {
                        Label("Connect tools", systemImage: "puzzlepiece.extension")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color("TodoMuted"))
                    }
                }
                .tint(Color("TodoInk"))
                .accessibilityIdentifier("settings-connectors")
            } header: {
                Text("Tools")
            } footer: {
                Text("Connect the apps you want Dony to use.")
            }
            .listRowBackground(Color("TodoInk").opacity(0.045))


            Section("Appearance") {
                Picker(selection: $appearance) {
                    ForEach(Appearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                } label: {
                    Label("Theme", systemImage: "circle.lefthalf.filled")
                }
                .tint(Color("TodoMuted"))
                .accessibilityIdentifier("appearance-picker")
            }
            .listRowBackground(Color("TodoInk").opacity(0.045))

            Section {
                Toggle(isOn: $inboxEnabled) {
                    Label("Show Inbox tab", systemImage: "tray")
                }
                .accessibilityIdentifier("settings-inbox-enabled")
            } header: {
                Text("Inbox")
            } footer: {
                Text("See questions and finished work in a separate tab.")
            }
            .listRowBackground(Color("TodoInk").opacity(0.045))

            if !companion.isConnected {
            Section {
                if chats.isDemo { Button {
                    chats.reset()
                    showingResetNotice = true
                } label: {
                    Label("Reset demo chats", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .tint(Color("TodoInk")) }

                Button(role: .destructive) {
                    confirmingErase = true
                } label: {
                    Label("Erase all to-dos", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(todos.items.isEmpty ? Color("TodoMuted") : .red)
                .disabled(todos.items.isEmpty)
            } header: {
                Text("Local data")
            } footer: {
                Text("Your to-dos are saved on this iPhone.")
                    .foregroundStyle(Color("TodoMuted"))
            }
            .listRowBackground(Color("TodoInk").opacity(0.045))
            }

            if chats.isDemo {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Demo mode", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                    Text("Chats use example conversations and canned replies. No AI is connected or work performed. Messages stay on this device and demo chats reset when you reopen Dony.")
                        .font(.subheadline)
                        .foregroundStyle(Color("TodoMuted"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
            }
            }
            CompanionSettingsView()
        }
        .contentMargins(.top, 8, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color("TodoSurface"))
        .foregroundStyle(Color("TodoInk"))
        .tabTitle("Settings")
        .sheet(isPresented: $showingConnectors) {
            ConnectorsView()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(40)
        }
        .alert("Erase all to-dos?", isPresented: $confirmingErase) {
            Button("Cancel", role: .cancel) {}
            Button("Erase all to-dos", role: .destructive) { todos.eraseAll() }
        } message: {
            Text("This permanently deletes your active and completed to-dos from this iPhone. Sample tasks will not be added again.")
        }
        .alert("Demo chats reset", isPresented: $showingResetNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The six example conversations are back. Your to-dos haven’t changed.")
        }
    }
}

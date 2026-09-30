import SwiftUI

struct NewChatView: View {
    @Environment(DemoChatStore.self) private var store
    @Environment(CompanionStore.self) private var companion
    @Environment(\.dismiss) private var dismiss
    @State private var creatingAgent = false
    @State private var editingAgent: SyncedAgent?
    let select: (DemoAgent) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.agents) { agent in
                        HStack(spacing: 12) {
                            Button {
                                select(agent)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    AgentAvatar(agent: agent)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(agent.name).font(.headline).foregroundStyle(.primary)
                                        Text(agent.description).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                            }
                            .accessibilityIdentifier("agent-\(agent.id)")
                            if let editable = companion.editableAgent(agent.id) {
                                Button { editingAgent = editable } label: {
                                    Image(systemName: "pencil")
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Edit \(agent.name)")
                                .accessibilityIdentifier("edit-agent-\(agent.id)")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text(store.isDemo ? "These are example identities with canned replies. No real agent will run." : "These agents belong to your shared workspace.")
                }
                if companion.isCloud {
                    Button("Create an agent", systemImage: "plus") {
                        guard companion.requireAIAccess() else { dismiss(); return }
                        creatingAgent = true
                    }
                        .accessibilityIdentifier("create-agent")
                }
            }
            .navigationTitle(store.isDemo ? "Choose a demo agent" : "Choose an agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $creatingAgent) {
                AgentEditorView()
            }
            .sheet(item: $editingAgent) { agent in
                AgentEditorView(agent: agent)
            }
        }
    }
}

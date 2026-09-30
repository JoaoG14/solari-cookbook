import SwiftUI

struct ChatSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let chat: DemoConversation
    let select: (String) -> Void

    private var matches: [DemoMessage] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return chat.messages.filter { $0.searchableText.localizedStandardContains(text) }
    }

    var body: some View {
        NavigationStack {
            List(matches) { message in
                Button { select(message.id) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message.role == .user ? "You" : chat.agent.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color("TodoMuted"))
                        Group {
                            if message.role == .user {
                                Text(verbatim: message.searchableText)
                            } else {
                                Text(.init(message.searchableText))
                            }
                        }
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("message-search-result")
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color("TodoSurface"))
            .tint(Color("TodoInk"))
            .overlay {
                if matches.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty ? "Find a message" : "No matching messages",
                        systemImage: "magnifyingglass",
                        description: Text("Search messages and filenames in this chat.")
                    )
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search messages")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle("Search chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

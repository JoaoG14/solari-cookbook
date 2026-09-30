import SwiftUI
import QuickLook

struct MessageContent: View {
    let message: DemoMessage
    let agent: DemoAgent
    @State private var previewURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if message.role == .assistant {
                HStack(spacing: 8) {
                    AgentAvatar(agent: agent, size: 24)
                    Text(agent.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color("TodoMuted"))
                }
            }

            ForEach(message.blocks.indices, id: \.self) { index in
                block(message.blocks[index])
            }
        }
        .padding(message.role == .user ? 16 : 0)
        .background {
            if message.role == .user {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color("TodoInk").opacity(0.06))
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .padding(.leading, message.role == .user ? 36 : 0)
        .multilineTextAlignment(.leading)
        .lineSpacing(3)
        .textSelection(.enabled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message.role == .user ? "Your message" : "Message from \(agent.name)")
        .quickLookPreview($previewURL)
    }

    @ViewBuilder
    private func block(_ block: DemoMessage.Block) -> some View {
        switch block {
        case .text(let text):
            if message.role == .user {
                Text(verbatim: text)
            } else {
                Text(.init(text))
            }
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("•").accessibilityHidden(true)
                        Text(items[index])
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        case .code(let code):
            ScrollView(.horizontal) {
                Text(verbatim: code)
                    .font(.system(.footnote, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(14)
            }
            .background(Color("TodoInk").opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityLabel("Swift code example")
        case .result(let title, let detail):
            VStack(alignment: .leading, spacing: 10) {
                Label("Demo result", systemImage: "doc.text")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(title).font(.headline)
                Text(detail)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color("TodoInk").opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        case .file(let file):
            Button {
                previewURL = file.url
            } label: {
                Label(file.name, systemImage: "doc")
                    .font(.subheadline)
                    .padding(.vertical, 10)
            }
            .tint(Color("TodoInk"))
            .accessibilityLabel("Preview \(file.name)")
        }
    }
}

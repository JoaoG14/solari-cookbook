import SwiftUI

struct TodoTitleText: View {
    @Environment(DemoChatStore.self) private var chats
    let title: String

    private var highlightedTitle: AttributedString {
        var result = AttributedString(title)
        let pattern = /(?:^|\s)(@[a-zA-Z0-9_-]+)/
        for match in title.matches(of: pattern) {
            let tag = TodoAgentMention.normalize(String(match.1))
            guard let agent = chats.agents.first(where: { TodoAgentMention.normalize($0.name) == tag }),
                  let range = Range(match.1.startIndex..<match.1.endIndex, in: result) else { continue }
            result[range].backgroundColor = agent.color.opacity(0.16)
        }
        return result
    }

    var body: some View {
        Text(highlightedTitle)
    }
}

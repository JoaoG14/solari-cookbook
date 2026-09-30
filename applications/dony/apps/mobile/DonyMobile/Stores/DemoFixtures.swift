enum DemoFixtures {
    static let conversations: [DemoConversation] = [
        DemoConversation(id: "weekly-update", agent: .atlas, title: "A clearer weekly update", messages: [
            DemoMessage(id: "weekly-user", role: .user, blocks: [.text("Help me make the weekly update easier to scan.")]),
            DemoMessage(id: "weekly-reply", role: .assistant, blocks: [
                .text("Start with what changed, then share what needs a decision. Here’s an example you can adapt."),
                .result(title: "Weekly update · sample draft", detail: "The landing page review is complete. Next week, we’ll refine the signup flow and collect feedback from the team."),
                .text("This is a sample result. Nothing has been created, sent, or added to your to-dos.")
            ])
        ]),
        DemoConversation(id: "launch-plan", agent: .mira, title: "Room for a longer answer", messages: [
            DemoMessage(id: "launch-user", role: .user, blocks: [.text("What should we think about before sharing a first version with the team?")]),
            DemoMessage(id: "launch-reply", role: .assistant, blocks: [
                .text("**Start with a small, clear promise.** Pick one thing the first version should help someone do, and make that path easy to find. A focused first impression gives people something concrete to respond to."),
                .text("**Give the review a little context.** Explain who the experience is for, what is ready to try, and which parts are still examples. People can give more useful feedback when they know what they’re looking at."),
                .text("**Watch someone use it.** Invite a teammate to complete a normal task without coaching. Notice where they pause, what they expect to happen, and which words they use to describe the interface."),
                .text("**Make space for the rough edges.** A first version doesn’t need every feature. It does need clear empty states, useful error messages, and a way to recover when someone changes their mind."),
                .text("**Finish with one next step.** Gather the observations, choose the most useful improvement, and make another small pass. Keep the feedback close to the actual experience rather than turning every suggestion into a new feature.")
            ])
        ]),
        DemoConversation(id: "code-example", agent: .pixel, title: "A small code example", messages: [
            DemoMessage(id: "code-user", role: .user, blocks: [.text("Show a short checklist and a Swift example.")]),
            DemoMessage(id: "code-reply", role: .assistant, blocks: [
                .text("A small checklist for the `TodoItem` title:"),
                .bullets(["Trim spaces at the edges.", "Keep the person’s wording.", "Ignore an empty title."]),
                .code("let title = input.trimmingCharacters(in: .whitespacesAndNewlines)\nguard !title.isEmpty else { return }\n\nitem.title = title"),
                .text("This code is an example. It hasn’t been run against a project.")
            ])
        ]),
        DemoConversation(id: "running", agent: .atlas, title: "Putting ideas together", messages: [
            DemoMessage(id: "running-user", role: .user, blocks: [.text("Help me organize the ideas from our planning session.")])
        ], status: .running),
        DemoConversation(id: "error", agent: .mira, title: "When a response stops", messages: [
            DemoMessage(id: "error-user", role: .user, blocks: [.text("Summarize the feedback from the last design review.")])
        ], status: .failed),
        DemoConversation(id: "empty", agent: .pixel, title: "A fresh conversation", messages: [])
    ].enumerated().map { index, conversation in
        var conversation = conversation
        conversation.updatedAt = .now.addingTimeInterval(-Double(index) * 35 * 60)
        return conversation
    }
}

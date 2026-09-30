import SwiftUI

struct TaskOutputReviewView: View {
    @Environment(CompanionStore.self) private var companion
    @Environment(\.dynamicTypeSize) private var typeSize
    let result: SyncResult
    let outputs: [SyncResult]
    var isChat = false
    var allowsReview = true
    @State private var showingFeedback = false
    @State private var showingResponse = false
    @State private var feedback = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                if outputs.isEmpty && !isChat {
                    Button { showingResponse = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "text.bubble")
                                .accessibilityHidden(true)
                            Text("Open in chat")
                        }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .foregroundStyle(Color("TodoMuted"))
                            .background(Color("TodoInk").opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("open-result-message-\(result.id)")
                }
                ForEach(outputs) { output in
                    ForEach(Array(output.artifacts.enumerated()), id: \.offset) { index, artifact in
                        HStack(spacing: 12) {
                            if let link = artifact.url, let url = URL(string: link), url.scheme == "https" {
                                Link(destination: url) { fileLabel(artifact) }
                                    .accessibilityLabel("Open \(artifact.name)")
                                Link(destination: url) { openLabel(isOpening: false) }
                                    .accessibilityLabel("Open \(artifact.name)")
                            } else {
                                Button { companion.openArtifact(output, index: index) } label: { fileLabel(artifact) }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Open \(artifact.name)")
                                    .accessibilityIdentifier("output-file-\(output.id)-\(index)")
                                Button { companion.openArtifact(output, index: index) } label: {
                                    openLabel(isOpening: companion.isOpeningArtifact(output, index: index))
                                }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Open \(artifact.name)")
                                    .accessibilityIdentifier("open-output-\(output.id)-\(index)")
                            }
                        }
                        .foregroundStyle(Color("TodoMuted"))
                    }
                }
            }
            .padding(.leading, isChat ? 0 : 45)
            .overlay(alignment: .topLeading) {
                if !isChat {
                    Path { path in
                        path.move(to: CGPoint(x: 22, y: 0))
                        path.addLine(to: CGPoint(x: 22, y: 17))
                        path.addQuadCurve(to: CGPoint(x: 27, y: 22), control: CGPoint(x: 22, y: 22))
                        path.addLine(to: CGPoint(x: 35, y: 22))
                    }
                    .stroke(Color("TodoQuiet"), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }

            if allowsReview && (isChat || !outputs.isEmpty) && companion.isAwaitingReview(result) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    Button { companion.review(result) } label: {
                        HStack(spacing: 4) {
                            Image("ReviewCheck")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                                .accessibilityHidden(true)
                            Text("Looks good")
                        }
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 8)
                        .foregroundStyle(Color(red: 26 / 255, green: 77 / 255, blue: 29 / 255))
                        .background(Color(red: 154 / 255, green: 1, blue: 161 / 255), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .accessibilityIdentifier("accept-output-\(result.id)")

                    Button { showingFeedback = true } label: {
                        Text("Needs changes")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.horizontal, 8)
                            .foregroundStyle(Color("TodoMuted"))
                            .background(Color("TodoInk").opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    }
                    .accessibilityIdentifier("change-output-\(result.id)")
                }
                .buttonStyle(.borderless)
                .padding(.leading, isChat ? 0 : 11)
            }
        }
        .padding(.bottom, 12)
        .sheet(isPresented: $showingResponse) {
            NavigationStack {
                ChatDetailView(conversationID: result.threadId, initialMessageID: result.assistantMessageId)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", systemImage: "xmark") { showingResponse = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingFeedback) {
            NavigationStack {
                Form {
                    TextField("What should change?", text: $feedback, axis: .vertical)
                        .lineLimit(4...8)
                        .accessibilityIdentifier("output-feedback")
                }
                .navigationTitle("Needs changes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingFeedback = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send feedback") {
                            if companion.review(result, feedback: feedback.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                showingFeedback = false
                                feedback = ""
                            }
                        }
                        .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || companion.pendingReview(result.id) != nil)
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func fileLabel(_ artifact: SyncResult.Artifact) -> some View {
        Label(artifact.name, systemImage: artifact.type == "link" ? "link" : "doc.text")
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Color("TodoInk").opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private func openLabel(isOpening: Bool) -> some View {
        HStack(spacing: 6) {
            Text(isOpening ? "Opening…" : "Open")
            if isOpening {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.up.right.square")
            }
        }
        .font(.subheadline.weight(.semibold))
        .fixedSize()
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }
}

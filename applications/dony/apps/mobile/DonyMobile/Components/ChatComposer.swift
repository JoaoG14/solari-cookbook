import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ChatComposer: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var composerTransition
    @Binding var thinking: ChatThinking
    @Binding var showingThinking: Bool
    let agentColor: Color
    @State private var restoreKeyboard = false
    @FocusState private var isMessageFocused: Bool
    @State private var text = ""
    @State private var attachments: [DemoAttachment] = []
    @State private var showingFiles = false
    @State private var selectedURLs: [URL] = []
    @State private var importError: String?
    var isRunning = false
    var isStopping = false
    var stop: () -> Void = {}
    var onKeyboardShown: () -> Void = {}
    let send: (String, [DemoAttachment]) -> Bool

    private var cannotSend: Bool {
        !selectedURLs.isEmpty || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)
    }

    var body: some View {
        Group {
            if showingThinking {
                ChatThinkingPicker(selection: $thinking, agentColor: agentColor)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                    .frame(maxWidth: 320)
                    .background(alignment: .bottom) {
                        Capsule()
                            .fill(reduceTransparency ? AnyShapeStyle(Color("TodoSurface")) : AnyShapeStyle(.regularMaterial))
                            .overlay {
                                Capsule().strokeBorder(Color("TodoInk").opacity(0.08), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.06), radius: 16, y: 5)
                            .frame(height: 64)
                            .matchedGeometryEffect(id: "composer-surface", in: composerTransition)
                    }
                    .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
            } else {
                composer
                    .transition(reduceMotion ? .opacity : AnyTransition(.blurReplace))
            }
        }
        .frame(maxWidth: .infinity)
        .tint(Color("TodoInk"))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            if reduceTransparency {
                Color("TodoSurface").ignoresSafeArea(.container, edges: .bottom)
            } else {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Color("TodoSurface").opacity(0.6), location: 0.45),
                        .init(color: Color("TodoSurface").opacity(0.95), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .padding(.top, -40)
                .ignoresSafeArea(.container, edges: .bottom)
                .allowsHitTesting(false)
            }
        }
        .onChange(of: showingThinking) { _, presented in
            if !presented, restoreKeyboard { isMessageFocused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
            guard isMessageFocused, !showingFiles else { return }
            onKeyboardShown()
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): selectedURLs = urls
            case .failure(let error): importError = error.localizedDescription
            }
        }
        .task(id: selectedURLs) {
            guard !selectedURLs.isEmpty else { return }
            for url in selectedURLs {
                do {
                    let file = try await Task.detached { try DemoAttachment(importing: url) }.value
                    if Task.isCancelled {
                        file.removeLocalCopy()
                        return
                    }
                    attachments.append(file)
                } catch {
                    if Task.isCancelled { return }
                    importError = error.localizedDescription
                }
            }
            selectedURLs = []
        }
        .alert("Couldn’t add file", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
    }

    private var composerSurface: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(reduceTransparency ? AnyShapeStyle(Color("TodoSurface")) : AnyShapeStyle(.regularMaterial))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color("TodoInk").opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 16, y: 5)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { file in
                            HStack(spacing: 6) {
                                Label(file.name, systemImage: "doc")
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Button {
                                    attachments.removeAll { $0.id == file.id }
                                    file.removeLocalCopy()
                                } label: {
                                    Image(systemName: "xmark").frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Remove \(file.name)")
                            }
                            .padding(.leading, 12)
                            .background(Color("TodoInk").opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(6)
                }
            }
            TextField("Message", text: $text, axis: .vertical)
                .focused($isMessageFocused)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.top, 9)
                .padding(.bottom, 3)
                .frame(minHeight: 40)
                .foregroundStyle(Color("TodoInk"))
                .accessibilityLabel("Message agent")
                .accessibilityIdentifier("chat-composer")

            HStack(alignment: .center, spacing: 4) {
                Button { showingFiles = true } label: {
                    Group {
                        if selectedURLs.isEmpty {
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .regular))
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(width: 44, height: 44)
                }
                .disabled(!selectedURLs.isEmpty)
                .accessibilityLabel("Add files")
                .accessibilityIdentifier("add-chat-files")

                Spacer(minLength: 0)

                Button {
                    restoreKeyboard = isMessageFocused
                    isMessageFocused = false
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.9)) {
                        showingThinking = true
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(thinking.title).font(.subheadline)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Color("TodoMuted"))
                    .padding(.horizontal, 8)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Thinking: \(thinking.title)")
                .accessibilityHint("Choose how much thought goes into your reply")
                .accessibilityIdentifier("chat-thinking-picker")

                Button {
                    if isRunning {
                        stop()
                        return
                    }
                    guard !cannotSend else { return }
                    guard send(text, attachments) else { return }
                    text = ""
                    attachments = []
                } label: {
                    Image(systemName: isRunning ? "stop.fill" : "arrow.up")
                        .font(.system(size: isRunning ? 16 : 19, weight: .semibold))
                        .foregroundStyle(isRunning ? Color("TodoSurface") : .white)
                        .frame(width: 34, height: 34)
                        .background(isRunning ? Color("TodoInk") : Color.blue, in: Circle())
                        .frame(width: 44, height: 44)
                        .opacity((isRunning ? isStopping : cannotSend) ? 0.45 : 1)
                }
                .buttonStyle(.plain)
                .disabled(isRunning ? isStopping : cannotSend)
                .accessibilityLabel(isRunning ? (isStopping ? "Stopping agent" : "Stop agent") : "Send message")
                .accessibilityIdentifier(isRunning ? "stop-agent" : "send-demo-message")
            }
        }
        .padding(4)
        .background {
            composerSurface.matchedGeometryEffect(id: "composer-surface", in: composerTransition)
        }
    }
}

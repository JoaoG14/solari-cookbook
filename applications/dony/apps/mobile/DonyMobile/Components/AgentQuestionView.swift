import SwiftUI
import UniformTypeIdentifiers

struct AgentQuestionView: View {
    @Environment(CompanionStore.self) private var companion
    let question: SyncQuestion
    var taskId: String?
    var embedded = false
    @State private var choices: [String: Set<String>] = [:]
    @State private var answers: [String: String] = [:]
    @State private var files: [DemoAttachment] = []
    @State private var pickingFiles = false
    @State private var step = 0
    @FocusState private var answerFocused: Bool
    @State private var error: String?

    private var current: SyncQuestion.Item? {
        question.questions.indices.contains(step) ? question.questions[step] : nil
    }

    private func isAnswered(_ item: SyncQuestion.Item) -> Bool {
        (item.responseKind == "resource" && !files.isEmpty) || !(choices[item.id] ?? []).isEmpty
            || (item.allowCustomAnswer
                && !(answers[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        if let change = companion.answerChange(question.id), change.error == nil, companion.connectionError == nil,
           let response = change.command.action["response"],
           let summary = SyncAnsweredQuestion(question: question, response: response) {
            AnsweredQuestionView(summary: summary, sending: true)
        } else {
            questionForm
        }
    }

    private var questionForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Label(question.header, systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if question.questions.count > 1 {
                    Text("\(step + 1) of \(question.questions.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color("TodoMuted"))
                        .fixedSize()
                }
            }

            if let change = companion.answerChange(question.id) {
                if let failure = change.error ?? companion.connectionError {
                    Label("Couldn’t send answers", systemImage: "exclamationmark.circle")
                        .font(.headline)
                    Text(failure).font(.subheadline).foregroundStyle(Color("TodoMuted"))
                    Button("Try again") {
                        if change.error != nil { companion.retry(change.id) }
                        else { Task { await companion.sync() } }
                    }
                        .buttonStyle(.borderedProminent)
                    Button("Edit answers") { companion.discard(change.id) }
                } else {
                    ProgressView("Sending…")
                        .font(.subheadline)
                        .accessibilityIdentifier("question-answer-sending")
                }
            } else if let item = current {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.question)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if !item.options.isEmpty {
                        Text(item.multiple ? "Choose all that apply" : "Choose one")
                            .font(.subheadline).foregroundStyle(Color("TodoMuted"))
                    }
                }
                VStack(spacing: 8) {
                    ForEach(item.options) { option in
                        optionButton(option, for: item)
                    }
                }
                if item.allowCustomAnswer {
                    VStack(alignment: .leading, spacing: 8) {
                        if !item.options.isEmpty {
                            Text("Or write your own answer")
                                .font(.subheadline).foregroundStyle(Color("TodoMuted"))
                        }
                        TextField(
                            item.responseKind == "resource"
                                ? "Paste a link or describe where to find it" : "Your answer",
                            text: Binding(
                                get: { answers[item.id] ?? "" },
                                set: {
                                    answers[item.id] = $0
                                    if !$0.isEmpty { choices[item.id] = [] }
                                }), axis: .vertical
                        )
                        .lineLimit(2...5)
                        .padding(12)
                        .background(Color("TodoSurface"), in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color("TodoQuiet").opacity(0.3)) }
                        .focused($answerFocused)
                        .accessibilityLabel("Your answer")
                        .accessibilityIdentifier("question-custom-answer")
                    }
                }
                if item.responseKind == "resource" {
                    Button("Attach files", systemImage: "paperclip") { pickingFiles = true }
                        .frame(minHeight: 44)
                    ForEach(files) { file in
                        HStack {
                            Text(file.name).font(.caption)
                            Spacer()
                            Button("Remove \(file.name)", systemImage: "xmark.circle.fill") {
                                files.removeAll { $0.id == file.id }
                            }
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
                HStack(spacing: 12) {
                    if step > 0 {
                        Button {
                            answerFocused = false
                            step -= 1
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.semibold))
                                .frame(width: 44, height: 44)
                                .background(Color("TodoSurface"), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Previous question")
                    }
                    Button {
                        answerFocused = false
                        if step < question.questions.count - 1 { step += 1 } else { submit() }
                    } label: {
                        Text(step < question.questions.count - 1 ? "Next question" : "Send answers")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(Color("TodoInk"))
                    .foregroundStyle(Color("TodoSurface"))
                    .disabled(!isAnswered(item))
                    .accessibilityIdentifier("question-continue")
                }
                Button("Decline") {
                    _ = companion.answer(question, taskId: taskId, response: .object(["action": "decline"]))
                }
                .font(.subheadline)
                .foregroundStyle(Color("TodoMuted"))
                .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        // Keep List from turning an unstyled button (such as Decline) into a row action.
        .buttonStyle(.plain)
        .padding(embedded ? 0 : 20)
        .background(Color("TodoInk").opacity(embedded ? 0 : 0.045), in: RoundedRectangle(cornerRadius: 20))
        .fileImporter(isPresented: $pickingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            do { files += try result.get().map { try DemoAttachment(importing: $0) } }
            catch { self.error = error.localizedDescription }
        }
    }

    private func optionButton(_ option: SyncQuestion.Option, for item: SyncQuestion.Item) -> some View {
        let selected = (choices[item.id] ?? []).contains(option.id)
        return Button {
            answerFocused = false
            var selection = choices[item.id] ?? []
            if selected { selection.remove(option.id) }
            else if item.multiple { selection.insert(option.id) }
            else { selection = [option.id] }
            choices[item.id] = selection
            answers[item.id] = ""
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.multiple
                    ? (selected ? "checkmark.square.fill" : "square")
                    : (selected ? "largecircle.fill.circle" : "circle"))
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? .blue : Color("TodoQuiet"))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.label).font(.body.weight(.medium))
                    if let description = option.description, !description.isEmpty {
                        Text(description).font(.subheadline).foregroundStyle(Color("TodoMuted"))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.leading)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(selected ? Color.blue.opacity(0.08) : Color("TodoSurface"), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selected ? .blue : Color("TodoQuiet").opacity(0.25), lineWidth: selected ? 1.5 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityIdentifier("question-option-\(item.id)-\(option.id)")
    }

    private func submit() {
        guard question.questions.allSatisfy(isAnswered) else { return }
        error = nil
        do {
            guard files.count <= 5 else { throw CompanionFailure("Send up to five files at a time.") }
            let uploads = try files.map { try SyncFile($0) }
            guard uploads.reduce(0, { $0 + $1.base64.utf8.count }) <= 28_000_000 else {
                throw CompanionFailure("Attachments must total 20 MB or less.")
            }
            let payload: [SyncValue] = question.questions.map { item in
                let selected = choices[item.id] ?? []
                if !selected.isEmpty {
                    if item.multiple {
                        return .object([
                            "type": "options", "questionId": .string(item.id),
                            "selectedOptionIds": .array(selected.sorted().map(SyncValue.string)),
                        ])
                    }
                    return .object([
                        "type": "option", "questionId": .string(item.id),
                        "selectedOptionId": .string(selected.sorted()[0]),
                    ])
                }
                let answer = (answers[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return .object([
                    "type": "custom", "questionId": .string(item.id),
                    "customText": .string(
                        answer.isEmpty && item.responseKind == "resource" ? "Use the attached files." : answer
                    ),
                ])
            }
            _ = companion.answer(
                question, taskId: taskId,
                response: .object([
                    "action": "accept", "answers": .array(payload), "files": .array(uploads.map(\.payload)),
                ]))
        } catch { self.error = error.localizedDescription }
    }
}

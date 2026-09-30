import AVFoundation
import Observation
import Speech
import SwiftUI

@MainActor
@Observable
final class TodoSpeechRecorder {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var previousText = ""
    private var currentText = ""
    private(set) var isRecording = false
    var transcript = ""
    var error: String?

    func start() async {
        guard !isRecording else { return }
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        let microphoneAllowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard speechAllowed && microphoneAllowed else {
            error = "Allow microphone and speech recognition in Settings to speak your tasks."
            return
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            error = "Speech recognition isn’t available right now. You can type your tasks below."
            return
        }
        error = nil
        previousText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        currentText = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            task = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                Task { @MainActor in
                    guard let self, self.isRecording else { return }
                    if let result {
                        self.currentText = result.bestTranscription.formattedString
                        self.transcript = [self.previousText, self.currentText]
                            .filter { !$0.isEmpty }.joined(separator: "\n")
                    }
                    if result?.isFinal == true || failure != nil {
                        self.stop()
                        if failure != nil && self.currentText.isEmpty {
                            self.error = "Recording stopped. Tap the microphone to continue."
                        }
                    }
                }
            }
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            stop()
            self.error = "Couldn’t start recording. You can type your tasks below."
        }
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

struct TodoVoiceView: View {
    private struct Draft: Identifiable {
        let id = UUID()
        var title: String
    }
    @Environment(\.dismiss) private var dismiss
    @Environment(CompanionStore.self) private var companion
    @State private var recorder = TodoSpeechRecorder()
    @State private var drafts: [Draft] = []
    @State private var organizing = false
    @State private var message: String?
    let save: ([String]) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Speak naturally. Mention several tasks in any order, then review what Dony finds.")
                        .foregroundStyle(.secondary)
                    TextEditor(text: $recorder.transcript)
                        .frame(minHeight: 150)
                        .accessibilityLabel("Spoken tasks")
                        .accessibilityIdentifier("voice-task-transcript")
                    Button {
                        if recorder.isRecording { recorder.stop() }
                        else { Task { await recorder.start() } }
                    } label: {
                        Label(recorder.isRecording ? "Stop recording" : "Speak tasks", systemImage: recorder.isRecording ? "stop.circle.fill" : "mic.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityIdentifier("voice-task-record")
                    if let error = recorder.error { Text(error).foregroundStyle(.red) }
                    Button {
                        recorder.stop()
                        Task { await organize() }
                    } label: {
                        if organizing { ProgressView("Organizing…") }
                        else { Text("Organize tasks") }
                    }
                    .disabled(organizing || recorder.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("voice-task-organize")
                }
                if !drafts.isEmpty {
                    Section("Review tasks") {
                        ForEach($drafts) { $draft in
                            HStack {
                                TextField("Task title", text: $draft.title)
                                Button("Remove", systemImage: "xmark", role: .destructive) {
                                    drafts.removeAll { $0.id == draft.id }
                                }.labelStyle(.iconOnly)
                            }
                        }
                        Button("Add \(drafts.count) to-dos") {
                            save(drafts.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
                            dismiss()
                        }
                        .disabled(drafts.allSatisfy { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                        .accessibilityIdentifier("voice-task-save")
                    }
                }
                if let message { Section { Text(message).foregroundStyle(.red) } }
            }
            .navigationTitle("Voice to-dos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .onDisappear { recorder.stop() }
    }

    private func organize() async {
        organizing = true
        message = nil
        defer { organizing = false }
        do {
            let titles = try await companion.organizeTasks(recorder.transcript)
            drafts = titles.map { Draft(title: $0) }
            if drafts.isEmpty { message = "No clear tasks found. Add more detail and try again." }
        } catch {
            message = error.localizedDescription
        }
    }
}

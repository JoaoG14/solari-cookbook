import SwiftUI
import UIKit

struct AgentEditorView: View {
    @Environment(CompanionStore.self) private var companion
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var instructions: String
    @State private var colorHex: String
    @State private var saving = false
    @State private var error: String?
    let agent: SyncedAgent?

    private let colors = [
        ("Green", "#56FF61"), ("Blue", "#2080FB"),
        ("Orange", "#FF9F2E"), ("Red", "#FF3B30"),
        ("Purple", "#A96BFF"), ("Coral", "#FF5C26"),
        ("Charcoal", "#1C1C1C"), ("Paper", "#ECECEC"),
        ("Yellow", "#FFCC00"), ("Pink", "#FF6FAE"),
        ("Teal", "#30C8B4"), ("Indigo", "#5856D6")
    ]

    init(agent: SyncedAgent? = nil) {
        self.agent = agent
        _name = State(initialValue: agent?.name ?? "")
        _instructions = State(initialValue: agent?.instructions ?? "")
        _colorHex = State(initialValue: agent?.color ?? "#2080FB")
    }

    private var preview: DemoAgent {
        DemoAgent(id: agent?.id ?? "preview", name: name, colorHex: colorHex, description: instructions)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        AgentAvatar(agent: preview, size: 56)
                        TextField("Name", text: $name)
                            .font(.headline)
                            .accessibilityLabel("Agent name")
                            .accessibilityIdentifier("agent-name")
                    }
                    .padding(.vertical, 8)
                }
                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                        ForEach(colors, id: \.1) { label, hex in
                            Button { colorHex = hex } label: {
                                ZStack {
                                    Circle().fill(DemoAgent(id: "color", name: "", colorHex: hex, description: "").color)
                                        .frame(width: 30, height: 30)
                                    if colorHex.caseInsensitiveCompare(hex) == .orderedSame {
                                        Circle().strokeBorder(Color("TodoInk"), lineWidth: 2)
                                            .frame(width: 40, height: 40)
                                    }
                                }
                                .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(label)
                            .accessibilityIdentifier("agent-color-\(label.lowercased())")
                            .accessibilityAddTraits(colorHex.caseInsensitiveCompare(hex) == .orderedSame ? [.isSelected] : [])
                        }
                    }
                    ColorPicker("Custom color", selection: Binding(
                        get: { preview.color },
                        set: { color in
                            var red: CGFloat = 0
                            var green: CGFloat = 0
                            var blue: CGFloat = 0
                            guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: nil) else { return }
                            colorHex = String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
                        }
                    ), supportsOpacity: false)
                    .accessibilityIdentifier("agent-custom-color")
                }
                Section("Instructions") {
                    TextField("What should this agent help with?", text: $instructions, axis: .vertical)
                        .lineLimit(4...10)
                        .accessibilityLabel("Agent instructions")
                        .accessibilityIdentifier("agent-instructions")
                }
            }
            .disabled(saving)
            .scrollContentBackground(.hidden)
            .background(Color("TodoSurface"))
            .foregroundStyle(Color("TodoInk"))
            .tint(.blue)
            .navigationTitle(agent == nil ? "New agent" : "Edit agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(agent == nil ? "Create" : "Save") {
                        saving = true
                        Task {
                            defer { saving = false }
                            do {
                                try await companion.saveCloudAgent(
                                    id: agent?.id,
                                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                    instructions: instructions,
                                    color: colorHex
                                )
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                    .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("save-agent")
                }
            }
            .alert("Couldn’t save agent", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
        .interactiveDismissDisabled(saving)
    }
}

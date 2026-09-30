import SwiftUI

struct CloudBrowserPreview: Decodable {
    let status: String
    let url: String?
    let title: String?
    let image: String?
    let capturedAt: String?
}

struct CloudBrowserButton: View {
    let threadID: String
    @State private var showingBrowser = false

    var body: some View {
        Button("View browser", image: .browserGlobe) { showingBrowser = true }
            .font(.subheadline.weight(.medium))
            .accessibilityIdentifier("view-cloud-browser")
            .sheet(isPresented: $showingBrowser) {
                CloudBrowserView(threadID: threadID)
            }
    }
}

struct CloudBrowserView: View {
    @Environment(CompanionStore.self) private var companion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let threadID: String
    @State private var preview: CloudBrowserPreview?
    @State private var image: UIImage?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let image, let preview {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Cloud browser screenshot")
                        .accessibilityValue(preview.title ?? "Browser")
                        .accessibilityIdentifier("cloud-browser-image")
                    if let capturedAt = preview.capturedAt {
                        Text("Live · \(syncDate(capturedAt).formatted(date: .omitted, time: .standard))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if preview?.status == "inactive" {
                    ContentUnavailableView("No browser running", systemImage: "globe",
                        description: Text("A preview appears when Dony opens a website. Browser sessions close when work finishes, stops, or needs your input."))
                        .accessibilityIdentifier("cloud-browser-inactive")
                } else if error == nil {
                    ProgressView("Loading browser…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let error {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("cloud-browser-error")
                    Text("Retrying automatically…").font(.caption).foregroundStyle(.secondary)
                }
                if scenePhase != .active {
                    Text("Preview paused").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color("TodoSurface"))
            .navigationTitle("Browser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task(id: [String(describing: scenePhase), companion.connection?.accountId ?? "", companion.connection?.token ?? ""]) {
                image = nil
                preview = nil
                error = nil
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    do {
                        try await companion.streamBrowserPreview(threadID: threadID) { next in
                            preview = next
                            image = next.image.flatMap { Data(base64Encoded: $0) }.flatMap { UIImage(data: $0) }
                            error = nil
                        }
                    } catch {
                        if Task.isCancelled { return }
                        // Do not leave a previous account's screenshot on screen after sign-out.
                        image = nil
                        preview = nil
                        self.error = "Couldn’t connect to the live browser. Check your connection."
                    }
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                }
            }
        }
    }
}

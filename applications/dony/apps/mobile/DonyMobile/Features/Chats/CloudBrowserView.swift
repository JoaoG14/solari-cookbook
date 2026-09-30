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
    @State private var enlarged = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Label("Read-only · Updates about every 2 seconds", systemImage: "eye")
                    .font(.caption).foregroundStyle(.secondary)
                if let image, let preview {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preview.title ?? "Browser").font(.headline).lineLimit(2)
                        Text(preview.url ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    GeometryReader { geometry in
                        ScrollView([.horizontal, .vertical]) {
                            Image(uiImage: image)
                                .resizable().scaledToFit()
                                .frame(width: geometry.size.width * (enlarged ? 2.5 : 1),
                                       height: geometry.size.width * (enlarged ? 2.5 : 1) * image.size.height / image.size.width)
                                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                                .accessibilityLabel("Cloud browser screenshot")
                                .accessibilityIdentifier("cloud-browser-image")
                        }
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    HStack {
                        if let capturedAt = preview.capturedAt {
                            Text("Updated \(syncDate(capturedAt).formatted(date: .omitted, time: .standard))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(enlarged ? "Zoom out" : "Zoom in", systemImage: enlarged ? "minus.magnifyingglass" : "plus.magnifyingglass") {
                            enlarged.toggle()
                        }
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
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    do {
                        let next = try await companion.browserPreview(threadID: threadID)
                        try Task.checkCancellation()
                        preview = next
                        image = next.image.flatMap { Data(base64Encoded: $0) }.flatMap { UIImage(data: $0) }
                        error = nil
                    } catch {
                        if Task.isCancelled { return }
                        // Do not leave a previous account's screenshot on screen after sign-out.
                        image = nil
                        preview = nil
                        self.error = "Couldn’t refresh the browser. Check your connection."
                    }
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                }
            }
        }
    }
}

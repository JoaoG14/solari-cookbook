import AVFoundation
import SwiftUI
import VisionKit

struct PairingView: View {
    @Environment(CompanionStore.self) private var companion
    @Environment(TodoStore.self) private var todos
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var link = ""
    @State private var bringTodos = true
    @State private var showingConnection = false
    @State private var scannedLink = false
    @State private var cameraAvailable = false
    @State private var cameraMessage: String?
    @State private var busy = false
    @State private var error: String?
    @FocusState private var enteringLink: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if cameraAvailable && !showingConnection {
                PairingScanner(
                    scanned: { value in
                        link = value
                        scannedLink = true
                        error = nil
                        showingConnection = true
                    },
                    failed: { message in
                        cameraAvailable = false
                        cameraMessage = message
                    }
                )
                .ignoresSafeArea()
                .accessibilityHidden(true)
            }
            LinearGradient(
                colors: [.black.opacity(0.65), .clear, .black.opacity(0.9)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 36)
                        ZStack {
                            PairingScanFrame()
                                .stroke(.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                                .accessibilityHidden(true)
                            Text("Scan QR code")
                                .font(.title3.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .padding(32)
                        }
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                        .frame(width: min(geometry.size.width - 88, 280), height: min(geometry.size.width - 88, 280))
                        .accessibilityIdentifier("pairing-viewfinder")

                        VStack(spacing: 12) {
                            Text("Connect to desktop")
                                .font(.title2.weight(.semibold))
                            Text("On your Mac, open Dony Settings → General → Connect phone.")
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .multilineTextAlignment(.center)
                        .padding(.top, 44)
                        .padding(.horizontal, 32)

                        Spacer(minLength: 40)
                        VStack(spacing: 20) {
                            Text(cameraMessage ?? "Keep your Mac awake and on the same Wi-Fi.")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                            Button {
                                scannedLink = false
                                error = nil
                                showingConnection = true
                            } label: {
                                Text("Use connection link")
                                    .font(.body.weight(.semibold))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 14)
                                    .frame(maxWidth: .infinity, minHeight: 54)
                                    .background(.white.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("use-connection-link")
                        }
                        .padding(.horizontal, 28)
                        .padding(.bottom, 24)
                    }
                    .frame(maxWidth: 440)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .scrollIndicators(.hidden)
            }
            .clipped()
        }
        .foregroundStyle(.white)
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 48, height: 48)
                        .background(.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("close-pairing")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingConnection) { connectionSheet }
        .onAppear {
            if let url = companion.pairingURL {
                link = url.absoluteString
                scannedLink = true
                showingConnection = true
            }
        }
        .task(id: showingConnection) {
            guard !showingConnection else { return }
            await prepareCamera()
        }
    }

    private var connectionSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(scannedLink ? "Ready to connect" : "Connect with a link")
                            .font(.title2.weight(.semibold))
                        Text(scannedLink
                             ? "Your tasks and chats will sync with Dony on your Mac."
                             : "Copy the connection link from Dony on your Mac, then paste it below.")
                            .foregroundStyle(.secondary)
                    }
                    if let error {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("pairing-error")
                    }
                    if !scannedLink {
                        TextField("Paste connection link", text: $link, axis: .vertical)
                            .lineLimit(2...4)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .focused($enteringLink)
                            .padding(18)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                            .contentShape(Rectangle())
                            .onTapGesture { enteringLink = true }
                            .disabled(busy)
                            .accessibilityIdentifier("companion-link")
                    }
                    if !todos.items.isEmpty {
                        Toggle(isOn: $bringTodos) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Bring all to-dos to desktop")
                                    .font(.body.weight(.medium))
                                Text("Includes your local tasks and subtasks.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(Color("TodoAccent"))
                        .padding(18)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                        .disabled(busy)
                        .accessibilityIdentifier("bring-todos-to-desktop")
                    }
                    Text("Keep both devices on the same Wi-Fi with Dony open on your Mac. Allow local network access when asked.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                Button { connect() } label: {
                    HStack(spacing: 10) {
                        if busy { ProgressView().tint(.black) }
                        Text(busy ? "Connecting…" : "Connect desktop")
                            .font(.body.weight(.semibold))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(.white, in: Capsule())
                    .opacity(busy || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                }
                .buttonStyle(.plain)
                .disabled(busy || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("connect-desktop")
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color(.systemBackground))
            }
            .navigationTitle(scannedLink ? "Desktop found" : "Connection link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingConnection = false }
                        .disabled(busy)
                }
            }
            .tint(.white)
        }
        .preferredColorScheme(.dark)
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(scannedLink ? 440 : 540), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .interactiveDismissDisabled(busy)
    }

    private func prepareCamera() async {
        guard DataScannerViewController.isSupported else {
            cameraMessage = "Camera scanning is unavailable. Use a connection link below."
            return
        }
        let access = await AVCaptureDevice.requestAccess(for: .video)
        guard !Task.isCancelled else { return }
        cameraAvailable = access && DataScannerViewController.isAvailable
        cameraMessage = cameraAvailable ? nil : "Allow camera access in iPhone Settings, or use a connection link below."
    }

    private func connect() {
        enteringLink = false
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            error = "Paste the full connection link from your desktop."
            return
        }
        let importIDs: Set<UUID> = bringTodos ? Set(todos.items.map(\.id)) : []
        busy = true
        error = nil
        Task {
            do {
                try await companion.pair(url: url, importIDs: importIDs)
                companion.pairingURL = nil
                dismiss()
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

private struct PairingScanFrame: Shape {
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 30
        let arm = rect.width * 0.25
        var path = Path()
        path.move(to: CGPoint(x: 0, y: arm))
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: .zero)
        path.addLine(to: CGPoint(x: arm, y: 0))
        path.move(to: CGPoint(x: rect.maxX - arm, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: radius), control: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: arm))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
        path.move(to: CGPoint(x: arm, y: rect.maxY))
        path.addLine(to: CGPoint(x: radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: 0, y: rect.maxY - radius), control: CGPoint(x: 0, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY - arm))
        return path
    }
}

private struct PairingScanner: UIViewControllerRepresentable {
    let scanned: (String) -> Void
    let failed: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(scanned: scanned, failed: failed) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
            recognizesMultipleItems: false, isGuidanceEnabled: false, isHighlightingEnabled: false)
        controller.delegate = context.coordinator
        do { try controller.startScanning() } catch {
            Task { @MainActor in
                failed(
                    "The camera is unavailable. Allow camera access in iPhone Settings or paste the connection link."
                )
            }
        }
        return controller
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let scanned: (String) -> Void
        var finished = false
        let failed: (String) -> Void
        init(scanned: @escaping (String) -> Void, failed: @escaping (String) -> Void) {
            self.scanned = scanned
            self.failed = failed
        }
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            failed("The camera is unavailable. Paste the connection link to continue.")
        }
        func dataScanner(
            _ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !finished else { return }
            for item in addedItems {
                if case .barcode(let code) = item, let value = code.payloadStringValue,
                    value.hasPrefix("dony-solari-mobile://pair")
                {
                    finished = true
                    dataScanner.stopScanning()
                    scanned(value)
                    return
                }
            }
        }
    }
}

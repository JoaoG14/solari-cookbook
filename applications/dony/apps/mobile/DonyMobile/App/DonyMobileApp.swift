import SwiftData
import SwiftUI

@main
struct DonyMobileApp: App {
    static var isStoreKitScreenshots: Bool {
        #if DEBUG && targetEnvironment(simulator)
        isUITesting && ProcessInfo.processInfo.arguments.contains("--storekit-screenshots")
        #else
        false
        #endif
    }
    @UIApplicationDelegateAdaptor(CloudNotifications.self) private var notificationDelegate
    static var isUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        false
        #endif
    }

    static var isCompanionTesting: Bool {
        #if DEBUG
        isUITesting && ProcessInfo.processInfo.arguments.contains("--companion-testing")
        #else
        false
        #endif
    }

    static var isOnboardingTesting: Bool {
        #if DEBUG
        isUITesting && ProcessInfo.processInfo.arguments.contains("--onboarding-testing")
        #else
        false
        #endif
    }

    static func makeCompanionStore() -> CompanionStore {
        #if DEBUG
        if isUITesting && ProcessInfo.processInfo.arguments.contains("--connect-banner-testing") {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [ConnectBannerPreviewProtocol.self]
            let desktop = CompanionConnection(server: URL(string: "https://mac.connect-preview.test")!, token: "preview-phone",
                deviceId: "preview-phone", desktopId: "preview-mac", desktopName: "My Mac", accountId: "preview",
                certificateFingerprint: String(repeating: "a", count: 64))
            let connection = CompanionConnection(server: URL(string: "https://connect-preview.test")!, token: "preview-account",
                deviceId: "preview-phone", desktopId: "preview-workspace", desktopName: "Dony", accountId: "preview",
                transport: "cloud", pairedDesktop: PairedDesktop(desktop))
            return CompanionStore(session: URLSession(configuration: configuration),
                cacheURL: URL.temporaryDirectory.appending(path: "connect-preview-\(UUID().uuidString).json"),
                credentials: CompanionCredentials(read: { connection }, save: { _ in }, remove: {}))
        }
        if isCompanionTesting {
            if ProcessInfo.processInfo.arguments.contains("--cloud-agent-testing"),
               let workspaceID = ProcessInfo.processInfo.environment["DONY_UI_CLOUD_WORKSPACE"] {
                UserDefaults.standard.removeObject(forKey: "cloudPushToken")
                let connection = CompanionConnection(
                    server: URL(string: "http://127.0.0.1:18790")!, token: "agent-ui-test",
                    deviceId: "agent-ui-test-phone", desktopId: workspaceID,
                    desktopName: "Dony Cloud", accountId: "agent-ui-test", transport: "cloud"
                )
                return CompanionStore(cacheURL: URL.temporaryDirectory.appending(path: "cloud-agent-ui-\(UUID().uuidString).json"),
                    credentials: CompanionCredentials(read: { connection }, save: { _ in }, remove: {}))
            }
            return CompanionStore(cacheURL: URL.temporaryDirectory.appending(path: "companion-ui-\(UUID().uuidString).json"), credentials: CompanionCredentials(read: { nil }, save: { _ in }, remove: {}))
        }
        if isUITesting { return CompanionStore(demo: true) }
        #endif
        return CompanionStore()
    }

    private let store: Result<TodoStore, Error>
    private let defaults: UserDefaults

    init() {
        var defaults = UserDefaults.standard
        var configuration = ModelConfiguration(cloudKitDatabase: .none)

        #if DEBUG
        // UI tests use their own on-disk store, including when testing relaunches.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            defaults = UserDefaults(suiteName: "DonyMobileUITests")!
            let url = URL.applicationSupportDirectory.appending(path: "DonyMobileUITests.store")
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if ProcessInfo.processInfo.arguments.contains("--reset-todos") {
                    defaults.removePersistentDomain(forName: "DonyMobileUITests")
                    for suffix in ["", "-shm", "-wal"] {
                        let file = URL(fileURLWithPath: url.path + suffix)
                        if FileManager.default.fileExists(atPath: file.path) {
                            try FileManager.default.removeItem(at: file)
                        }
                    }
                }
                configuration = ModelConfiguration(url: url, cloudKitDatabase: .none)
            } catch {
                self.defaults = defaults
                self.store = .failure(error)
                return
            }
        }
        #endif

        self.defaults = defaults
        MobileOnboarding.prepare(defaults: defaults, bypass: Self.isUITesting && !Self.isOnboardingTesting)
        self.store = Result {
            try FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
            let container = try ModelContainer(for: TodoItem.self, configurations: configuration)
            return try TodoStore(container: container, defaults: defaults,
                                 seedExamples: Self.isUITesting && !Self.isOnboardingTesting)
        }
    }

    var body: some Scene {
        WindowGroup {
            switch store {
            case .success(let todoStore):
                RootTabView(defaults: defaults)
                    .environment(todoStore)
                    .defaultAppStorage(defaults)
            case .failure(let error):
                ContentUnavailableView {
                    Label("Couldn’t open your to-dos", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Your data has not been erased. Close Dony and try again.\n\(error.localizedDescription)")
                }
            }
        }
    }
}

#if DEBUG
// Isolated UI-test transport: no account, workspace, or purchase reaches a real server.
private final class ConnectBannerPreviewProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.url?.host == "connect-preview.test" else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)); return
        }
        let body: [String: Any]
        if request.url?.lastPathComponent == "account" {
            body = ["workspaceId": "preview-workspace", "pro": false, "executionTarget": "computer",
                    "dailyLimitUsd": 0, "dailySpentUsd": 0, "resetsAt": "", "configured": true,
                    "billing": ["accountToken": "preview", "configured": false, "monthlyUsedPercent": 0,
                                "extraRemainingPercent": 0, "canRunCloud": false, "limitReached": false, "canUseRemoteDesktop": false]]
        } else {
            body = ["revision": 1, "desktopOnline": false, "receipts": [], "executionTarget": "computer",
                    "snapshot": ["version": 1, "mode": "off", "tasks": [], "agents": [], "threads": [], "results": []]]
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif

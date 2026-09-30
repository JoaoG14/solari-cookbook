import SafariServices
import SwiftUI

struct ConnectorsView: View {
    var onboarding = false
    var onEmailConnectionChanged: ((String?) -> Void)? = nil
    var onOnboardingContinue: (() -> Void)? = nil
    @ScaledMetric(relativeTo: .largeTitle) private var onboardingTitleSize = 42
    @Environment(CompanionStore.self) private var companion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isOnboardingPreview) private var onboardingPreview
    @State private var preferredEmailToolkit = "gmail"
    @State private var previewStates: [String: String] = [:]
    @State private var status: MobileConnectorsStatus?
    @State private var search = ""
    @State private var connectedOnly = false
    @State private var loading = false
    @State private var busySlug: String?
    @State private var pendingSlug: String?
    @State private var pendingSince: Date?
    @State private var error: String?
    @State private var actionError: String?
    @State private var authorization: ConnectorAuthorization?
    @State private var disconnecting: MobileConnector?

    private var isPreview: Bool { onboardingPreview && companion.isDemo }

    private var visibleConnectors: [MobileConnector] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let connectors = (status?.toolkits ?? []).filter {
            (!onboarding || ["gmail", "outlook"].contains($0.slug)) && (!connectedOnly || $0.isConnected) && (query.isEmpty ||
                "\($0.name) \($0.description) \($0.group)".localizedCaseInsensitiveContains(query))
        }
        return connectors
    }

    var body: some View {
        Group {
            if onboarding { onboardingPage }
            else { catalog }
        }
        .background(onboarding ? OnboardingPalette.background : Color("TodoSurface"))
        .foregroundStyle(Color("TodoInk"))
        .onChange(of: connectedEmailToolkit) { _, toolkit in
            onEmailConnectionChanged?(toolkit)
        }
        .task(id: "\(scenePhase == .active)-\(companion.connection?.deviceId ?? "")") {
            if isPreview { status = previewStatus; return }
            guard scenePhase == .active, companion.isConnected else { return }
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(for: .seconds(pendingSlug == nil ? 5 : 2)) }
                catch { return }
            }
        }
        .sheet(item: $authorization, onDismiss: {
            pendingSlug = nil
            Task { await refresh() }
        }) { authorization in
            if let url = authorization.url { ConnectorBrowser(url: url).ignoresSafeArea() }
        }
        .confirmationDialog("Disconnect \(disconnecting?.name ?? "tool")?", isPresented: Binding(
            get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } }
        ), titleVisibility: .visible) {
            if let connector = disconnecting {
                Button("Disconnect", role: .destructive) { Task { await act("disconnect", on: connector) } }
            }
        } message: {
            Text("This removes the tool connection from your Dony account.")
        }
    }

    private var catalog: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 9) {
                    if !companion.isConnected && !isPreview {
                        ContentUnavailableView("Sign in to Dony", systemImage: "person.crop.circle",
                            description: Text("Sign in to connect the apps you want Dony to use."))
                    } else {
                        if let error = error ?? actionError {
                            VStack(spacing: 10) {
                                Text(error).font(.subheadline).multilineTextAlignment(.center)
                                Button("Try again") { actionError = nil; Task { await refresh() } }
                                    .disabled(loading)
                            }
                            .padding(20)
                            .accessibilityIdentifier("connectors-error")
                        }
                        if status == nil && error == nil {
                            ProgressView("Loading connectors…").padding(40)
                        } else if let status, !status.enabled {
                            ContentUnavailableView("Connectors unavailable", systemImage: "puzzlepiece.extension",
                                description: Text(status.disabledReason ?? "Tools are temporarily unavailable. Try again later."))
                        } else if visibleConnectors.isEmpty && error == nil {
                            ContentUnavailableView(connectedOnly ? "No connected tools" : "No connectors found",
                                systemImage: "magnifyingglass", description: Text("Try another search or choose All connectors."))
                        } else {
                            ForEach(visibleConnectors) { connector in
                                card(connector)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 20)
            }
            .refreshable { await refresh() }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { searchField }
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 23, weight: .light))
                    .frame(width: 46, height: 46).background(.background, in: Circle())
            }
            .accessibilityLabel("Close connectors")
            Spacer()
            Text("Connectors").font(.title3.weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.5).accessibilityAddTraits(.isHeader)
            Spacer()
            Menu {
                Picker("Show connectors", selection: $connectedOnly) {
                    Text("All connectors").tag(false)
                    Text("Connected").tag(true)
                }
            } label: {
                Image(systemName: connectedOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                    .font(.system(size: 21)).frame(width: 46, height: 46)
                    .background(.background, in: Circle())
            }
            .accessibilityLabel("Filter connectors")
        }
        .buttonStyle(.plain)
        .padding(16)
    }

    private var connectedEmailToolkit: String? {
        let connected = (status?.toolkits ?? []).filter {
            ["gmail", "outlook"].contains($0.slug) && $0.isConnected
        }
        return connected.first(where: { $0.slug == preferredEmailToolkit })?.slug ?? connected.first?.slug
    }

    private var onboardingPage: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 24)
                    Text("Let's connect\nyour email")
                        .font(.system(size: onboardingTitleSize, weight: .bold))
                        .tracking(-1.2).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityLabel("Let's connect your email")
                    Text("Connect your email so Dony can help with your tasks when you ask.")
                        .font(.subheadline).foregroundStyle(OnboardingPalette.muted)
                        .multilineTextAlignment(.center).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 16)
                    VStack(spacing: 12) {
                        onboardingEmailCard("gmail", name: "Gmail")
                        onboardingEmailCard("outlook", name: "Outlook")
                    }
                    .padding(.top, textSize.isAccessibilitySize ? 28 : 84)
                    Text("Add other tools later in Settings.")
                        .font(.footnote).foregroundStyle(OnboardingPalette.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 22)
                    if let message = error ?? actionError ?? status?.disabledReason {
                        Text(message).font(.footnote).foregroundStyle(OnboardingPalette.muted)
                            .multilineTextAlignment(.center).padding(.top, 16)
                            .accessibilityIdentifier("connectors-error")
                    }
                    Spacer(minLength: 24)
                    if textSize.isAccessibilitySize { onboardingFooter }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 440).frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !textSize.isAccessibilitySize { onboardingFooter }
        }
    }

    private func onboardingEmailCard(_ toolkit: String, name: String) -> some View {
        let connector = status?.toolkits.first { $0.slug == toolkit }
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            HStack(spacing: 11) {
                Image(toolkit == "gmail" ? "ConnectorGmail" : "ConnectorOutlook")
                    .resizable().scaledToFit()
                    .padding(4).frame(width: 34, height: 34)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.12)))
                    .accessibilityHidden(true)
                Text(name).font(.title3.weight(.semibold))
                    .accessibilityIdentifier("connector-\(toolkit)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let connector, connector.isConnected || connector.isPaused {
                connectorAction(connector)
                    .background(OnboardingPalette.foreground.opacity(0.06), in: Capsule())
            } else {
                onboardingPrimaryAction(toolkit: toolkit, name: name)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OnboardingPalette.foreground.opacity(0.035), in: RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .topTrailing) {
            if toolkit == "gmail" && !textSize.isAccessibilitySize && connectedEmailToolkit == nil {
                OnboardingEmailArrow()
                    .stroke(OnboardingPalette.muted.opacity(0.7), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .frame(width: 116, height: 75)
                    .padding(.trailing, 41).offset(y: -83)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }

    private var onboardingFooter: some View {
        VStack(spacing: 10) {
            if connectedEmailToolkit != nil {
                onboardingPrimaryAction()
            } else {
                Button("Maybe later") { onOnboardingContinue?() }
                    .font(.subheadline).foregroundStyle(OnboardingPalette.muted)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("onboarding-secondary")
            }
        }
        .padding(.horizontal, textSize.isAccessibilitySize ? 0 : 24).padding(.top, 16).padding(.bottom, 4)
        .frame(maxWidth: 440).frame(maxWidth: .infinity)
        .background(OnboardingPalette.background)
    }

    private func onboardingPrimaryAction(toolkit: String? = nil, name: String = "") -> some View {
        let connected = toolkit == nil
        let connector = status?.toolkits.first { $0.slug == toolkit }
        let pending = toolkit != nil && (busySlug == toolkit || pendingSlug == toolkit)
        let retry = error != nil || status?.enabled == false || (status != nil && connector == nil)
        let title = connected ? "Continue" : pending ? "Connecting…" : retry ? "Try again" : "Connect"
        let foreground = connected ? OnboardingPalette.background : Color.white
        return Button {
            if connected { onOnboardingContinue?() }
            else if retry { Task { await refresh() } }
            else if let connector {
                preferredEmailToolkit = connector.slug
                Task { await act(connector.connectedAccountId == nil ? "connect" : "refresh", on: connector) }
            }
        } label: {
            ZStack {
                Text(pending ? "Connect" : title)
                    .font(.body.weight(.semibold)).multilineTextAlignment(.center)
                    .opacity(pending ? 0 : 1)
                if pending {
                    ProgressView().tint(foreground)
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 18).padding(.vertical, connected ? 15 : 10)
            .frame(maxWidth: connected ? .infinity : nil, minHeight: connected ? 56 : 44)
            .background(connected ? OnboardingPalette.foreground : Color(uiColor: .systemBlue), in: Capsule())
        }
        .disabled(busySlug != nil || pendingSlug != nil || (status == nil && error == nil))
        .accessibilityLabel(title == "Connect" ? "Connect \(name)" : title)
        .accessibilityIdentifier(toolkit.map { "onboarding-connect-\($0)" } ?? "onboarding-continue")
        .buttonStyle(OnboardingButtonStyle())
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.title3)
            TextField("Search", text: $search)
                .font(.title3).autocorrectionDisabled().textInputAutocapitalization(.never)
                .accessibilityIdentifier("connectors-search")
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        .frame(minWidth: 32, minHeight: 44)
                }.accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 54)
        .background {
            if reduceTransparency { Capsule().fill(Color("TodoSurface")) }
            else { Capsule().fill(.regularMaterial) }
        }
        .overlay(Capsule().strokeBorder(.white.opacity(0.4)))
        .shadow(color: .black.opacity(0.06), radius: 18, y: 6)
        .padding(.horizontal, 28).padding(.vertical, 12)
        .background {
            if reduceTransparency {
                Color("TodoSurface")
                    .ignoresSafeArea(edges: .bottom)
            } else {
                LinearGradient(stops: [
                    .init(color: Color("TodoSurface").opacity(0), location: 0),
                    .init(color: Color("TodoSurface").opacity(0.9), location: 0.45),
                    .init(color: Color("TodoSurface"), location: 1)
                ], startPoint: .top, endPoint: .bottom)
                .padding(.top, -24)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
            }
        }
    }

    private func card(_ connector: MobileConnector) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(spacing: 10))
            layout {
                HStack(spacing: 9) {
                    ConnectorLogo(connector: connector)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(connector.name).font(.headline)
                        Text(pendingSlug == connector.slug ? "Connecting…" : connector.statusLabel)
                            .font(.caption).foregroundStyle(Color("TodoMuted"))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                connectorAction(connector)
            }
            Text(connector.description).font(.subheadline)
                .foregroundStyle(Color("TodoInk").opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color("TodoInk").opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("connector-\(connector.slug)")
    }

    @ViewBuilder private func connectorAction(_ connector: MobileConnector) -> some View {
        if busySlug == connector.slug {
            ProgressView().frame(width: 90, height: 44).accessibilityLabel("Updating \(connector.name)")
        } else if connector.isConnected || connector.isPaused {
            Menu {
                Button(connector.isPaused ? "Resume" : "Pause") {
                    Task { await act("setEnabled", on: connector) }
                }
                Button("Reconnect") { Task { await act("refresh", on: connector) } }
                Button("Disconnect", role: .destructive) { disconnecting = connector }
            } label: { pill(connector.isConnected ? "Connected" : "Paused") }
                .disabled(busySlug != nil || status?.enabled != true)
                .accessibilityLabel("Manage \(connector.name)")
        } else {
            Button {
                Task { await act(connector.connectedAccountId == nil ? "connect" : "refresh", on: connector) }
            } label: { pill(pendingSlug == connector.slug ? "Connecting" : "Connect") }
                .disabled(busySlug != nil || pendingSlug == connector.slug || status?.enabled != true)
                .accessibilityLabel("Connect \(connector.name)")
        }
    }

    private func pill(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).fixedSize()
            .padding(.horizontal, 15).frame(minHeight: 44)
            .foregroundStyle(onboarding ? Color("TodoInk") : Color("TodoSurface"))
            .background(onboarding ? Color.clear : Color("TodoInk"), in: Capsule())
    }

    private func refresh() async {
        if isPreview { status = previewStatus; return }
        guard companion.isConnected, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let latest: MobileConnectorsStatus = try await companion.connectorRequest(["action": "list"])
            try Task.checkCancellation()
            status = latest
            error = nil
            if let pendingSlug {
                let connector = latest.toolkits.first { $0.slug == pendingSlug }
                if connector?.isConnected == true {
                    self.pendingSlug = nil
                    authorization = nil
                } else if let connector, ["FAILED", "EXPIRED", "REVOKED"].contains(connector.status.uppercased()) {
                    self.pendingSlug = nil
                    actionError = "The connection wasn’t completed. Tap Connect to try again."
                } else if Date.now.timeIntervalSince(pendingSince ?? .now) > 120 {
                    self.pendingSlug = nil
                    actionError = "Authorization is still waiting. Finish signing in, or tap Connect to try again."
                }
            }
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }

    private func act(_ action: String, on connector: MobileConnector) async {
        if isPreview {
            previewStates[connector.slug] = action == "disconnect" ? "DISCONNECTED"
                : action == "setEnabled" && !connector.isPaused ? "INACTIVE" : "ACTIVE"
            status = previewStatus
            return
        }
        guard busySlug == nil else { return }
        busySlug = connector.slug
        actionError = nil
        defer { busySlug = nil }
        var body: [String: SyncValue] = ["action": .string(action)]
        if action == "connect" { body["toolkit"] = .string(connector.slug) }
        else { body["connectedAccountId"] = .optional(connector.connectedAccountId) }
        if action == "setEnabled" { body["enabled"] = .bool(connector.isPaused) }
        do {
            if action == "connect" || action == "refresh" {
                let result: ConnectorAuthorization = try await companion.connectorRequest(body)
                if action == "connect" && result.url == nil {
                    throw CompanionFailure("Dony did not return an authorization link. Try again.")
                }
                if let url = result.url {
                    guard url.scheme == "https", url.host != nil else {
                        throw CompanionFailure("Dony returned an invalid authorization link.")
                    }
                    pendingSlug = connector.slug
                    pendingSince = .now
                    authorization = result
                }
            } else {
                status = try await companion.connectorRequest(body)
            }
            await refresh()
        } catch is CancellationError { }
        catch { self.actionError = error.localizedDescription }
    }

    private var previewStatus: MobileConnectorsStatus {
        let tools = [("googledrive", "Google Drive"), ("gmail", "Gmail"), ("outlook", "Outlook"),
                     ("googlecalendar", "Google Calendar"), ("notion", "Notion")]
        return MobileConnectorsStatus(enabled: true, disabledReason: nil, toolkits: tools.map { slug, name in
            let state = previewStates[slug] ?? "DISCONNECTED"
            return MobileConnector(slug: slug, name: name, description: "", group: "", logoUrl: nil,
                isConnected: state == "ACTIVE", status: state,
                connectedAccountId: state == "DISCONNECTED" ? nil : "preview-\(slug)")
        })
    }
}

private struct ConnectorBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

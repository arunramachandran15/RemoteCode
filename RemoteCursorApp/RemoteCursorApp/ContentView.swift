import SwiftUI

struct ThemePickerMenu: View {
    @AppStorage("appTheme") private var appTheme: String = AppTheme.system.rawValue

    private var current: AppTheme { AppTheme(rawValue: appTheme) ?? .system }

    var body: some View {
        Menu {
            ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                Button {
                    appTheme = theme.rawValue
                } label: {
                    Label(theme.label, systemImage: theme.icon)
                }
                .disabled(theme == current)
            }
        } label: {
            Image(systemName: current.icon)
        }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var peer = PeerClient()
    @AppStorage("wifiURL") private var wifiURL = ""
    @AppStorage("savedConnectionMode") private var savedConnectionMode = ""
    @AppStorage("lastPeerDisplayName") private var lastPeerDisplayName = ""
    @State private var connectionMode: ConnectionMode?
    @State private var isConnected = false
    @State private var isReconnecting = false
    @State private var wifiReconnectTask: Task<Void, Never>?
    @State private var terminalToAgentMessage = ""
    @State private var selectedTab = 0
    @State private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    var body: some View {
        Group {
            if isConnected {
                if horizontalSizeClass == .regular {
                    iPadLayout
                } else {
                    iPhoneLayout
                }
            } else {
                ConnectionView(
                    peer: peer,
                    wifiURL: $wifiURL,
                    connectionMode: $connectionMode,
                    isConnected: $isConnected,
                    savedConnectionMode: $savedConnectionMode,
                    lastPeerDisplayName: $lastPeerDisplayName
                )
            }
        }
        .onAppear {
            tryAutoConnect()
        }
        .onChange(of: peer.connectedPeer) { new in
            if new != nil {
                isReconnecting = false
                isConnected = true
                if connectionMode == .peer { lastPeerDisplayName = new?.displayName ?? "" }
            } else if connectionMode == .peer, isConnected {
                isReconnecting = true
                startPeerReconnect()
            }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                endBackgroundTask()
                if isReconnecting { return }
                if !isConnected, !savedConnectionMode.isEmpty { tryAutoConnect() }
            case .background:
                beginBackgroundTask()
            default:
                break
            }
        }
    }

    // MARK: - iPhone Tab Layout

    private var iPhoneLayout: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                AgentView(
                    peer: peer,
                    wifiURL: wifiURL,
                    connectionMode: connectionMode ?? .wifi,
                    onConnectionLost: { triggerReconnect() },
                    externalMessage: $terminalToAgentMessage
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Disconnect") { disconnect() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ThemePickerMenu()
                    }
                }
            }
            .tabItem {
                Label("Agent", systemImage: "brain")
            }
            .tag(0)

            NavigationStack {
                TerminalView(
                    peer: peer,
                    wifiURL: wifiURL,
                    connectionMode: connectionMode ?? .wifi,
                    sendToAgent: Binding(
                        get: { terminalToAgentMessage },
                        set: { newValue in
                            terminalToAgentMessage = newValue
                            if !newValue.isEmpty { selectedTab = 0 }
                        }
                    )
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Disconnect") { disconnect() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ThemePickerMenu()
                    }
                }
            }
            .tabItem {
                Label("Terminal", systemImage: "terminal")
            }
            .tag(1)

            NavigationStack {
                FileBrowserView(
                    peer: peer,
                    wifiURL: wifiURL,
                    connectionMode: connectionMode ?? .wifi
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Disconnect") { disconnect() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ThemePickerMenu()
                    }
                }
            }
            .tabItem {
                Label("Files", systemImage: "folder")
            }
            .tag(2)

            NavigationStack {
                DownloadsView(
                    peer: peer,
                    wifiURL: wifiURL,
                    connectionMode: connectionMode ?? .wifi
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Disconnect") { disconnect() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ThemePickerMenu()
                    }
                }
            }
            .tabItem {
                Label("Downloads", systemImage: "arrow.down.circle")
            }
            .tag(3)
        }
        .overlay {
            if isReconnecting { reconnectingOverlay }
        }
    }

    // MARK: - iPad Split Layout

    private var iPadLayout: some View {
        NavigationSplitView {
            List {
                sidebarButton(label: "Agent", icon: "brain", tag: 0)
                sidebarButton(label: "Terminal", icon: "terminal", tag: 1)
                sidebarButton(label: "Files", icon: "folder", tag: 2)
                sidebarButton(label: "Downloads", icon: "arrow.down.circle", tag: 3)
            }
            .navigationTitle("Remote Cursor")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ThemePickerMenu()
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Disconnect") { disconnect() }
                        .foregroundStyle(.red)
                }
            }
        } detail: {
            NavigationStack {
                switch selectedTab {
                case 1:
                    TerminalView(
                        peer: peer,
                        wifiURL: wifiURL,
                        connectionMode: connectionMode ?? .wifi,
                        sendToAgent: Binding(
                            get: { terminalToAgentMessage },
                            set: { newValue in
                                terminalToAgentMessage = newValue
                                if !newValue.isEmpty { selectedTab = 0 }
                            }
                        )
                    )
                case 2:
                    FileBrowserView(
                        peer: peer,
                        wifiURL: wifiURL,
                        connectionMode: connectionMode ?? .wifi
                    )
                case 3:
                    DownloadsView(
                        peer: peer,
                        wifiURL: wifiURL,
                        connectionMode: connectionMode ?? .wifi
                    )
                default:
                    AgentView(
                        peer: peer,
                        wifiURL: wifiURL,
                        connectionMode: connectionMode ?? .wifi,
                        onConnectionLost: { triggerReconnect() },
                        externalMessage: $terminalToAgentMessage
                    )
                }
            }
        }
        .overlay {
            if isReconnecting { reconnectingOverlay }
        }
    }

    private func sidebarButton(label: String, icon: String, tag: Int) -> some View {
        Button {
            selectedTab = tag
        } label: {
            Label(label, systemImage: icon)
                .foregroundStyle(selectedTab == tag ? Color.accentColor : Color.primary)
        }
    }

    // MARK: - Shared Views

    private var reconnectingOverlay: some View {
        VStack {
            ProgressView("Reconnecting…")
                .padding()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }

    // MARK: - Background Task Management

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask {
            endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - Connection

    private func tryAutoConnect() {
        guard !isConnected else { return }
        if savedConnectionMode == "wifi", !wifiURL.trimmingCharacters(in: .whitespaces).isEmpty {
            Task {
                let ok = await HTTPClient(baseURL: wifiURL.trimmingCharacters(in: .whitespaces)).healthCheck()
                await MainActor.run {
                    if ok {
                        connectionMode = .wifi
                        isConnected = true
                    }
                }
            }
            return
        }
        if savedConnectionMode == "peer", !lastPeerDisplayName.isEmpty {
            connectionMode = .peer
            peer.preferredPeerDisplayName = lastPeerDisplayName
            peer.startBrowsing()
        }
    }

    private func triggerReconnect() {
        guard isConnected else { return }
        if connectionMode == .wifi {
            isConnected = false
            startWifiReconnect()
        } else {
            isReconnecting = true
            startPeerReconnect()
        }
    }

    private func startWifiReconnect() {
        isReconnecting = true
        wifiReconnectTask?.cancel()
        let url = wifiURL.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { isReconnecting = false; return }
        wifiReconnectTask = Task {
            for _ in 0..<60 {
                if Task.isCancelled { break }
                let ok = await HTTPClient(baseURL: url).healthCheck()
                if ok {
                    await MainActor.run {
                        isConnected = true
                        isReconnecting = false
                        wifiReconnectTask = nil
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
            await MainActor.run { isReconnecting = false }
        }
    }

    private func startPeerReconnect() {
        isReconnecting = true
        peer.preferredPeerDisplayName = lastPeerDisplayName
        peer.startBrowsing()
    }

    private func disconnect() {
        wifiReconnectTask?.cancel()
        wifiReconnectTask = nil
        if connectionMode == .peer { peer.stopBrowsing() }
        isConnected = false
        isReconnecting = false
        connectionMode = nil
    }
}

#Preview {
    ContentView()
}

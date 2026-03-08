import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
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

    var body: some View {
        Group {
            if isConnected {
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
                        }
                    }
                    .tabItem {
                        Label("Terminal", systemImage: "terminal")
                    }
                    .tag(1)
                }
                .overlay {
                    if isReconnecting {
                        VStack {
                            ProgressView("Reconnecting…")
                                .padding()
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                    }
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
            if phase == .active {
                if isReconnecting { return }
                if !isConnected, !savedConnectionMode.isEmpty { tryAutoConnect() }
            } else if phase == .background {
                wifiReconnectTask?.cancel()
                wifiReconnectTask = nil
            }
        }
    }

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

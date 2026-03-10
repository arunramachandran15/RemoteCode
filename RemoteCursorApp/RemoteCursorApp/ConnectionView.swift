import SwiftUI

struct ConnectionView: View {
    @ObservedObject var peer: PeerClient
    @StateObject private var bonjour = BonjourBrowser()
    @Binding var wifiURL: String
    @Binding var connectionMode: ConnectionMode?
    @Binding var isConnected: Bool
    @Binding var savedConnectionMode: String
    @Binding var lastPeerDisplayName: String
    @State private var connecting = false
    @State private var wifiError: String?
    @State private var autoConnecting = false

    @State private var oct1 = "10"
    @State private var oct2 = "0"
    @State private var oct3 = "0"
    @State private var oct4 = "247"
    @State private var port = "3847"
    @State private var fullURL = ""
    @State private var ipPortInitialized = false
    @State private var isSyncingURL = false

    var body: some View {
        NavigationStack {
            List {
                if !savedConnectionMode.isEmpty {
                    Section {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Last connection")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if savedConnectionMode == "wifi" {
                                    Label(wifiURL, systemImage: "wifi")
                                } else {
                                    Label(lastPeerDisplayName.isEmpty ? "Bluetooth Mac" : lastPeerDisplayName, systemImage: "desktopcomputer")
                                }
                            }
                            Spacer()
                            if autoConnecting {
                                ProgressView()
                            } else {
                                Button("Reconnect") {
                                    reconnectLast()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    } header: {
                        Text("Quick Reconnect")
                    }
                }

                Section("Connect via Bluetooth / Wi-Fi") {
                    Button {
                        connectionMode = .peer
                        peer.startBrowsing()
                    } label: {
                        Label("Find Mac", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .disabled(connectionMode == .peer && !peer.discoveredPeers.isEmpty)

                    if connectionMode == .peer && !peer.discoveredPeers.isEmpty {
                        ForEach(peer.discoveredPeers, id: \.displayName) { p in
                            Button {
                                connecting = true
                                peer.connect(to: p)
                            } label: {
                                Label(p.displayName, systemImage: "desktopcomputer")
                            }
                        }
                    }

                    if let err = peer.connectionError {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }

                Section("Or discover via Bonjour (Node bridge)") {
                    Button {
                        bonjour.start()
                    } label: {
                        Label("Find Mac (Bonjour)", systemImage: "network")
                    }
                    .disabled(bonjour.isSearching)
                    if bonjour.isSearching {
                        HStack {
                            ProgressView()
                            Text("Searching…").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(bonjour.discoveredServices) { svc in
                        Button {
                            connectToBonjourService(svc)
                        } label: {
                            Label(svc.name, systemImage: "desktopcomputer")
                        }
                    }
                    if let e = bonjour.errorMessage {
                        Text(e).foregroundStyle(.red).font(.caption)
                    }
                }

                Section {
                    VStack(spacing: 12) {
                        HStack(spacing: 0) {
                            Text("IP")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 32, alignment: .leading)
                            octetField($oct1)
                            dot
                            octetField($oct2)
                            dot
                            octetField($oct3)
                            dot
                            octetField($oct4)
                            Spacer().frame(width: 12)
                            Text(":")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            portField
                        }

                        HStack {
                            Text("URL")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 32, alignment: .leading)
                            TextField("http://ip:port", text: $fullURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(.subheadline, design: .monospaced))
                                .onChange(of: fullURL) { newValue in
                                    guard !isSyncingURL else { return }
                                    isSyncingURL = true
                                    parseFullURL(newValue)
                                    isSyncingURL = false
                                }
                        }
                    }
                    .padding(.vertical, 4)

                    Button {
                        syncURLFromParts()
                        connectionMode = .wifi
                        checkWifiAndConnect()
                    } label: {
                        HStack {
                            Image(systemName: "wifi")
                            Text("Connect via Wi-Fi")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(oct1.isEmpty || oct4.isEmpty)

                    if let e = wifiError { Text(e).foregroundStyle(.red).font(.caption) }
                } header: {
                    Text("Connect via Wi-Fi (same network)")
                }
            }
            .navigationTitle("Remote Cursor")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ThemePickerMenu()
                }
            }
            .onAppear { initializeFromWifiURL() }
            .onChange(of: peer.connectedPeer) { new in
                if new != nil {
                    connecting = false
                    autoConnecting = false
                    isConnected = true
                    if connectionMode == .peer {
                        savedConnectionMode = "peer"
                        lastPeerDisplayName = new?.displayName ?? ""
                    }
                }
            }
            .overlay {
                if connecting {
                    ProgressView("Connecting…").padding()
                }
            }
        }
    }

    // MARK: - IP / Port Helpers

    private var dot: some View {
        Text(".")
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(width: 8)
    }

    private func octetField(_ text: Binding<String>) -> some View {
        TextField("0", text: text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.system(.body, design: .monospaced))
            .frame(minWidth: 36, maxWidth: 50)
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onChange(of: text.wrappedValue) { newVal in
                let filtered = String(newVal.filter { $0.isNumber }.prefix(3))
                if filtered != newVal { text.wrappedValue = filtered }
                guard !isSyncingURL else { return }
                isSyncingURL = true
                syncURLFromParts()
                isSyncingURL = false
            }
    }

    private var portField: some View {
        TextField("3847", text: $port)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.system(.body, design: .monospaced))
            .frame(minWidth: 44, maxWidth: 60)
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onChange(of: port) { newVal in
                let filtered = String(newVal.filter { $0.isNumber }.prefix(5))
                if filtered != newVal { port = filtered }
                guard !isSyncingURL else { return }
                isSyncingURL = true
                syncURLFromParts()
                isSyncingURL = false
            }
    }

    private func syncURLFromParts() {
        let ip = "\(oct1).\(oct2).\(oct3).\(oct4)"
        let p = port.isEmpty ? "3847" : port
        let url = "http://\(ip):\(p)"
        if fullURL != url { fullURL = url }
        if wifiURL != url { wifiURL = url }
    }

    private func parseFullURL(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("http://") { s = String(s.dropFirst(7)) }
        if s.hasPrefix("https://") { s = String(s.dropFirst(8)) }
        let hostPort = s.split(separator: "/").first.map(String.init) ?? s
        let parts = hostPort.split(separator: ":")
        let host = String(parts.first ?? "")
        if parts.count >= 2 {
            let p = String(parts[1]).filter { $0.isNumber }
            if !p.isEmpty && p != port { port = p }
        }
        let octets = host.split(separator: ".").map(String.init)
        if octets.count == 4 {
            if octets[0] != oct1 { oct1 = octets[0] }
            if octets[1] != oct2 { oct2 = octets[1] }
            if octets[2] != oct3 { oct3 = octets[2] }
            if octets[3] != oct4 { oct4 = octets[3] }
        }
        let url = raw.trimmingCharacters(in: .whitespaces)
        if wifiURL != url { wifiURL = url }
    }

    private func initializeFromWifiURL() {
        guard !ipPortInitialized else { return }
        ipPortInitialized = true
        let saved = wifiURL.trimmingCharacters(in: .whitespaces)
        if !saved.isEmpty {
            fullURL = saved
            parseFullURL(saved)
        } else {
            syncURLFromParts()
        }
    }

    private func reconnectLast() {
        autoConnecting = true
        wifiError = nil
        if savedConnectionMode == "wifi" {
            connectionMode = .wifi
            Task {
                let url = wifiURL.trimmingCharacters(in: .whitespaces)
                let (ok, errDetail) = await HTTPClient(baseURL: url).healthCheckDetailed()
                await MainActor.run {
                    autoConnecting = false
                    if ok {
                        isConnected = true
                    } else {
                        wifiError = "Mac not reachable: \(errDetail ?? "Is the bridge running?")"
                    }
                }
            }
        } else if savedConnectionMode == "peer" {
            connectionMode = .peer
            peer.preferredPeerDisplayName = lastPeerDisplayName
            peer.startBrowsing()
            Task {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await MainActor.run {
                    if !isConnected { autoConnecting = false }
                }
            }
        }
    }

    private func checkWifiAndConnect() {
        wifiError = nil
        connecting = true
        Task {
            let url = wifiURL.trimmingCharacters(in: .whitespaces)
            let (ok, errDetail) = await HTTPClient(baseURL: url).healthCheckDetailed()
            await MainActor.run {
                connecting = false
                if ok {
                    savedConnectionMode = "wifi"
                    isConnected = true
                } else {
                    wifiError = "Could not reach Mac at \(url). \(errDetail ?? "Check URL and that the bridge is running.")"
                }
            }
        }
    }

    private func connectToBonjourService(_ svc: BonjourBrowser.DiscoveredBonjourService) {
        bonjour.stop()
        wifiURL = svc.baseURL
        connectionMode = .wifi
        checkWifiAndConnect()
    }
}

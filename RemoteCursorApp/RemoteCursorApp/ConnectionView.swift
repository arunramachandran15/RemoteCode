import SwiftUI

struct ConnectionView: View {
    @ObservedObject var peer: PeerClient
    @Binding var wifiURL: String
    @Binding var connectionMode: ConnectionMode?
    @Binding var isConnected: Bool
    @Binding var savedConnectionMode: String
    @Binding var lastPeerDisplayName: String
    @State private var connecting = false
    @State private var wifiError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Connect via Bluetooth / Wi‑Fi") {
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

                Section("Or connect via Wi‑Fi (same network)") {
                    TextField("Mac URL", text: $wifiURL, prompt: Text("http://192.168.1.x:3847"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Connect via Wi‑Fi") {
                        connectionMode = .wifi
                        checkWifiAndConnect()
                    }
                    .disabled(wifiURL.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let e = wifiError { Text(e).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("Remote Cursor")
            .onChange(of: peer.connectedPeer) { new in
                if new != nil {
                    connecting = false
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

    private func checkWifiAndConnect() {
        wifiError = nil
        connecting = true
        Task {
            let url = wifiURL.trimmingCharacters(in: .whitespaces)
            let ok = await HTTPClient(baseURL: url).healthCheck()
            await MainActor.run {
                connecting = false
                if ok {
                    savedConnectionMode = "wifi"
                    isConnected = true
                } else {
                    wifiError = "Could not reach Mac. Check URL and that the bridge is running."
                }
            }
        }
    }
}

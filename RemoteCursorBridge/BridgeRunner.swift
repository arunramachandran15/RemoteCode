import Foundation

/// Starts HTTP server and Peer connection. Used by both CLI and desktop app.
enum BridgeRunner {
    static func start() {
        Config.ensureConfigExists()
        let http = HTTPServer()
        let peer = PeerConnection()
        http.start(port: Config.httpPort)
        peer.start()
        print("Remote Cursor Bridge running.")
        print("  Wi‑Fi:  http://<this-mac-ip>:\(Config.httpPort)")
        print("  Peer:   Use \"Find Mac\" in the iOS app (Bluetooth / Wi‑Fi)")
        print("Repos: \(Config.repoPaths.joined(separator: ", "))")
    }
}

import Foundation

Config.ensureConfigExists()

let http = HTTPServer()
let peer = PeerConnection()

http.start(port: Config.httpPort)
peer.start()

print("Remote Cursor Bridge running.")
print("  Wi‑Fi:  http://<this-mac-ip>:\(Config.httpPort)")
print("  Peer:   Use \"Find Mac\" in the iOS app (Bluetooth / Wi‑Fi)")
print("Repos: \(Config.repoPaths.joined(separator: ", "))")
print("Press Ctrl+C to stop.")

RunLoop.main.run()

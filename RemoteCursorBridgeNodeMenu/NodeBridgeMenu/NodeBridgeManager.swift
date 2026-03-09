import Foundation
import AppKit

final class NodeBridgeManager {
    static let shared = NodeBridgeManager()
    private var process: Process?
    private let defaultsKey = "NodeBridgePath"

    var isRunning: Bool {
        guard let p = process else { return false }
        return p.isRunning
    }

    var bridgePath: String? {
        get {
            if let saved = UserDefaults.standard.string(forKey: defaultsKey), !saved.isEmpty, FileManager.default.fileExists(atPath: (saved as NSString).appendingPathComponent("server.js")) {
                return saved
            }
            return defaultBridgePath()
        }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
        }
    }

    private init() {}

    private func defaultBridgePath() -> String? {
        let fm = FileManager.default
        let candidates: [String] = [
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("RemoteCursorBridgeNode").path,
            Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("RemoteCursorBridgeNode").path,
            (NSHomeDirectory() as NSString).appendingPathComponent("RemoteCursorBridgeNode"),
            "/Volumes/work/NilanTech/RemoteCursor/RemoteCursorBridgeNode",
        ]
        for path in candidates {
            if fm.fileExists(atPath: (path as NSString).appendingPathComponent("server.js")) {
                return path
            }
        }
        return nil
    }

    func setBridgePath(_ path: String) {
        bridgePath = path
    }

    func start(completion: @escaping (Bool, String?) -> Void) {
        guard process == nil || process?.isRunning != true else {
            completion(true, nil)
            return
        }
        guard let path = bridgePath else {
            completion(false, "Bridge path not set. Use 'Set Bridge Path…' to choose the RemoteCursorBridgeNode folder.")
            return
        }
        let nodePath = (path as NSString).appendingPathComponent("server.js")
        guard FileManager.default.fileExists(atPath: nodePath) else {
            completion(false, "server.js not found at \(path)")
            return
        }
        var nodePathForExec: String = "/usr/local/bin/node"
        for candidate in ["/opt/homebrew/bin/node", "/usr/local/bin/node"] {
            if FileManager.default.fileExists(atPath: candidate) {
                nodePathForExec = candidate
                break
            }
        }
        let nodeURL = URL(fileURLWithPath: nodePathForExec)
        let p = Process()
        p.executableURL = nodeURL
        p.arguments = [nodePath]
        p.currentDirectoryURL = URL(fileURLWithPath: path)
        p.environment = ProcessInfo.processInfo.environment
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.process = nil
            }
        }
        do {
            try p.run()
            process = p
            completion(true, nil)
        } catch {
            completion(false, "Failed to run node: \(error.localizedDescription). Ensure Node.js is installed.")
        }
    }

    func stop() {
        process?.terminate()
        process = nil
    }
}

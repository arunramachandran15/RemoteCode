import Foundation
import MultipeerConnectivity

private let serviceType = "remotecursor"
/// Long timeout so agent code changes don't time out (e.g. 30 min).
private let requestTimeoutNanoseconds: UInt64 = 30 * 60 * 1_000_000_000

final class PeerClient: NSObject, ObservableObject, MCSessionDelegate, MCNearbyServiceBrowserDelegate {
    private var session: MCSession?
    private var browser: MCNearbyServiceBrowser?
    private let myPeerID = MCPeerID(displayName: UIDevice.current.name)
    private let streamQueue = DispatchQueue(label: "peer.streams")

    @Published var discoveredPeers: [MCPeerID] = []
    @Published var connectedPeer: MCPeerID?
    @Published var connectionError: String?

    /// When set, we auto-invite this peer as soon as we discover it (for auto/reconnect).
    var preferredPeerDisplayName: String?

    func startBrowsing() {
        connectionError = nil
        discoveredPeers = []
        let sess = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        sess.delegate = self
        session = sess
        let bro = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        bro.delegate = self
        browser = bro
        bro.startBrowsingForPeers()
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
        session?.disconnect()
        session = nil
        connectedPeer = nil
        discoveredPeers = []
    }

    func connect(to peer: MCPeerID) {
        guard let sess = session else { return }
        browser?.invitePeer(peer, to: sess, withContext: nil, timeout: 30)
    }

    func getRepos() async throws -> [String] {
        try await sendRequest(type: "getRepos", params: [:], key: "repos") as! [String]
    }

    func listFiles(path: String) async throws -> [FileItem] {
        let dict = try await sendRequest(type: "listFiles", params: ["path": path], key: nil) as? [String: Any]
        guard let files = dict?["files"] as? [[String: Any]] else {
            throw NSError(domain: "PeerClient", code: -1, userInfo: [NSLocalizedDescriptionKey: dict?["error"] as? String ?? "Invalid response"])
        }
        return files.map {
            FileItem(
                id: $0["path"] as? String ?? UUID().uuidString,
                name: $0["name"] as? String ?? "",
                path: $0["path"] as? String ?? "",
                isDirectory: $0["isDirectory"] as? Bool ?? false,
                size: $0["size"] as? Int
            )
        }
    }

    func readFile(path: String) async throws -> String {
        let dict = try await sendRequest(type: "readFile", params: ["path": path], key: nil) as? [String: Any]
        if let error = dict?["error"] as? String { throw NSError(domain: "PeerClient", code: -1, userInfo: [NSLocalizedDescriptionKey: error]) }
        guard let content = dict?["content"] as? String else {
            throw NSError(domain: "PeerClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No content"])
        }
        return content
    }

    func writeFile(path: String, content: String) async throws {
        let dict = try await sendRequest(type: "writeFile", params: ["path": path, "content": content], key: nil) as? [String: Any]
        if let error = dict?["error"] as? String { throw NSError(domain: "PeerClient", code: -1, userInfo: [NSLocalizedDescriptionKey: error]) }
    }

    func runCommand(_ command: String, workspace: String?) async throws -> CommandResult {
        var params: [String: Any] = ["command": command]
        if let w = workspace { params["workspace"] = w }
        let dict = try await sendRequest(type: "runCommand", params: params, key: nil) as? [String: Any]
        return CommandResult(
            stdout: dict?["stdout"] as? String,
            stderr: dict?["stderr"] as? String,
            exitCode: (dict?["exitCode"] as? Int) ?? -1
        )
    }

    func uploadImage(_ imageData: Data) async throws -> String {
        guard let sess = session, !sess.connectedPeers.isEmpty else {
            throw NSError(domain: "PeerClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }
        let requestId = UUID().uuidString
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("upload_\(requestId).jpg")
        try imageData.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        return try await withCheckedThrowingContinuation { cont in
            pendingResourceContinuations[requestId] = cont
            sess.sendResource(at: tmpURL, withName: "uploadImage:\(requestId)", toPeer: sess.connectedPeers[0]) { error in
                if let error = error {
                    DispatchQueue.main.async { [weak self] in
                        self?.pendingResourceContinuations.removeValue(forKey: requestId)?.resume(throwing: error)
                    }
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                if let c = self.pendingResourceContinuations.removeValue(forKey: requestId) {
                    c.resume(throwing: NSError(domain: "PeerClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Image upload timeout"]))
                }
            }
        }
    }

    private var pendingResourceContinuations: [String: CheckedContinuation<String, Error>] = [:]

    func trustWorkspace(_ workspace: String) async throws -> (ok: Bool, message: String) {
        let dict = try await sendRequest(type: "trustWorkspace", params: ["workspace": workspace], key: nil) as? [String: Any]
        let ok = dict?["ok"] as? Bool ?? false
        let msg = dict?["message"] as? String ?? dict?["error"] as? String ?? (ok ? "Done" : "Unknown error")
        return (ok, msg)
    }

    func runAgent(workspace: String, message: String, sessionId: String? = nil) async throws -> AgentResponse {
        var params: [String: Any] = ["workspace": workspace, "message": message]
        if let s = sessionId { params["sessionId"] = s }
        let dict = try await sendRequest(type: "runAgent", params: params, key: nil) as? [String: Any]
        return AgentResponse(
            output: dict?["output"] as? String,
            error: dict?["error"] as? String,
            sessionId: dict?["sessionId"] as? String
        )
    }

    /// Stream agent response; onChunk called on main actor. No timeout — waits for stream_done.
    func runAgentStreaming(
        workspace: String,
        message: String,
        sessionId: String? = nil,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> AgentResponse {
        guard let sess = session, !sess.connectedPeers.isEmpty else {
            throw NSError(domain: "PeerClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }
        let requestId = UUID().uuidString
        return try await withCheckedThrowingContinuation { cont in
            streamQueue.sync { [weak self] in
                self?.pendingStreams[requestId] = (onChunk: onChunk, continuation: cont)
            }
            var body: [String: Any] = ["type": "runAgent", "workspace": workspace, "message": message, "stream": true, "requestId": requestId]
            if let s = sessionId { body["sessionId"] = s }
            guard let data = try? JSONSerialization.data(withJSONObject: body) else {
                streamQueue.async { [weak self] in
                    self?.pendingStreams.removeValue(forKey: requestId)?.continuation.resume(throwing: NSError(domain: "PeerClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Serialization failed"]))
                }
                return
            }
            try? sess.send(data, toPeers: sess.connectedPeers, with: .reliable)
        }
    }

    private var pendingStreams: [String: (onChunk: @Sendable (String) -> Void, continuation: CheckedContinuation<AgentResponse, Error>)] = [:]
    private var pendingRequests: [String: (key: String?, continuation: CheckedContinuation<Any, Error>)] = [:]

    private func sendRequest(type: String, params: [String: Any], key: String?) async throws -> Any {
        guard let sess = session, !sess.connectedPeers.isEmpty else {
            throw NSError(domain: "PeerClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }
        let requestId = UUID().uuidString
        var body: [String: Any] = ["type": type, "requestId": requestId]
        for (k, v) in params { body[k] = v }
        let data = try JSONSerialization.data(withJSONObject: body)
        try sess.send(data, toPeers: sess.connectedPeers, with: .reliable)
        return try await withCheckedThrowingContinuation { cont in
            pendingRequests[requestId] = (key: key, continuation: cont)
            Task {
                try? await Task.sleep(nanoseconds: requestTimeoutNanoseconds)
                if let entry = self.pendingRequests.removeValue(forKey: requestId) {
                    entry.continuation.resume(throwing: NSError(domain: "PeerClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Timeout"]))
                }
            }
        }
    }

    func receiveResponse(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let type = json["type"] as? String
        if type == "uploadImage_response" {
            let requestId = json["requestId"] as? String ?? ""
            if let error = json["error"] as? String {
                pendingResourceContinuations.removeValue(forKey: requestId)?.resume(
                    throwing: NSError(domain: "PeerClient", code: -1, userInfo: [NSLocalizedDescriptionKey: error]))
            } else if let path = json["path"] as? String {
                pendingResourceContinuations.removeValue(forKey: requestId)?.resume(returning: path)
            }
            return
        }
        if type == "stream_chunk" {
            let requestId = json["requestId"] as? String ?? ""
            let delta = json["delta"] as? String ?? ""
            streamQueue.async { [weak self] in
                guard let entry = self?.pendingStreams[requestId] else { return }
                Task { @MainActor in entry.onChunk(delta) }
            }
            return
        }
        if type == "stream_done" {
            let requestId = json["requestId"] as? String ?? ""
            let response = AgentResponse(
                output: json["output"] as? String,
                error: json["error"] as? String,
                sessionId: json["sessionId"] as? String
            )
            streamQueue.async { [weak self] in
                self?.pendingStreams.removeValue(forKey: requestId)?.continuation.resume(returning: response)
            }
            return
        }
        let requestId = json["requestId"] as? String ?? ""
        guard let entry = pendingRequests.removeValue(forKey: requestId) else { return }
        if let k = entry.key, let v = json[k] {
            entry.continuation.resume(returning: v)
        } else {
            entry.continuation.resume(returning: json)
        }
    }

    func receiveError(_ error: Error) {
        for (_, entry) in pendingRequests { entry.continuation.resume(throwing: error) }
        pendingRequests.removeAll()
        for (_, cont) in pendingResourceContinuations { cont.resume(throwing: error) }
        pendingResourceContinuations.removeAll()
        streamQueue.async { [weak self] in
            for (_, v) in self?.pendingStreams ?? [:] { v.continuation.resume(throwing: error) }
            self?.pendingStreams.removeAll()
        }
    }
}

extension PeerClient {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            if !self.discoveredPeers.contains(where: { $0.displayName == peerID.displayName }) {
                self.discoveredPeers.append(peerID)
            }
            if let preferred = self.preferredPeerDisplayName, peerID.displayName == preferred, let sess = self.session {
                self.browser?.invitePeer(peerID, to: sess, withContext: nil, timeout: 30)
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.discoveredPeers.removeAll { $0.displayName == peerID.displayName }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            self.connectionError = error.localizedDescription
        }
    }
}

extension PeerClient {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            if state == .connected {
                self.connectedPeer = peerID
                self.browser?.stopBrowsingForPeers()
            } else if state == .notConnected {
                self.connectedPeer = nil
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        receiveResponse(data)
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

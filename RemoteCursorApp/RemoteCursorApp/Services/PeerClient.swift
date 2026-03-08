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
    private var pendingContinuation: (CheckedContinuation<Any, Error>)?
    private var responseKey: String?

    private func sendRequest(type: String, params: [String: Any], key: String?) async throws -> Any {
        guard let sess = session, !sess.connectedPeers.isEmpty else {
            throw NSError(domain: "PeerClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }
        var body: [String: Any] = ["type": type]
        for (k, v) in params { body[k] = v }
        let data = try JSONSerialization.data(withJSONObject: body)
        try sess.send(data, toPeers: sess.connectedPeers, with: .reliable)
        return try await withCheckedThrowingContinuation { cont in
            pendingContinuation = cont
            responseKey = key
            Task {
                try? await Task.sleep(nanoseconds: requestTimeoutNanoseconds)
                if let c = self.pendingContinuation {
                    self.pendingContinuation = nil
                    self.responseKey = nil
                    c.resume(throwing: NSError(domain: "PeerClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "Timeout"]))
                }
            }
        }
    }

    func receiveResponse(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            pendingContinuation?.resume(returning: data as Any)
            pendingContinuation = nil
            responseKey = nil
            return
        }
        let type = json["type"] as? String
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
        // Single-response (getRepos, runAgent non-stream)
        let cont = pendingContinuation
        pendingContinuation = nil
        let key = responseKey
        responseKey = nil
        guard let c = cont else { return }
        if let k = key, let v = json[k] {
            c.resume(returning: v)
        } else {
            c.resume(returning: json)
        }
    }

    func receiveError(_ error: Error) {
        pendingContinuation?.resume(throwing: error)
        pendingContinuation = nil
        responseKey = nil
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

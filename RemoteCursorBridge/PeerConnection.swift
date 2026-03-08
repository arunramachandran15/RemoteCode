import Foundation
import MultipeerConnectivity

// Service type: max 15 chars, lowercase letters/numbers/hyphens
private let serviceType = Config.serviceType

final class PeerConnection: NSObject {
    private var advertiser: MCNearbyServiceAdvertiser?
    private var session: MCSession?

    func start() {
        let peerID = MCPeerID(displayName: Host.current().localizedName ?? "Mac")
        let sess = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        sess.delegate = self
        session = sess
        let adv = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        adv.delegate = self
        advertiser = adv
        adv.startAdvertisingPeer()
        print("Peer: Advertising as \"\(peerID.displayName)\" (Bluetooth / Wi‑Fi)")
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        session?.disconnect()
        session = nil
    }

    private func handleMessage(_ data: Data, from peerID: MCPeerID, session: MCSession) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        var response: [String: Any]
        switch type {
        case "getRepos":
            response = ["repos": Config.repoPaths]
        case "runAgent":
            guard let workspace = json["workspace"] as? String, let message = json["message"] as? String else {
                response = ["error": "Missing workspace or message"]
                break
            }
            let sessionId = json["sessionId"] as? String
            let stream = (json["stream"] as? Bool) == true
            let requestId = json["requestId"] as? String ?? UUID().uuidString
            if stream {
                sendAgentStream(workspace: workspace, message: message, sessionId: sessionId, requestId: requestId, to: peerID, session: session)
                return
            }
            let (output, error, sid) = AgentRunner.run(workspace: workspace, message: message, sessionId: sessionId)
            response = ["output": output as Any, "error": error as Any]
            if let s = sid { response["sessionId"] = s }
        case "runCommand":
            guard let command = json["command"] as? String else {
                response = ["error": "Missing command"]
                break
            }
            let workspace = json["workspace"] as? String
            response = HTTPServer.runShellCommand(command, workspace: workspace)
        case "listFiles":
            guard let path = json["path"] as? String else {
                response = ["error": "Missing path"]
                break
            }
            response = HTTPServer.listFiles(at: path)
        case "readFile":
            guard let path = json["path"] as? String else {
                response = ["error": "Missing path"]
                break
            }
            response = HTTPServer.readFile(at: path)
        case "writeFile":
            guard let path = json["path"] as? String, let content = json["content"] as? String else {
                response = ["error": "Missing path or content"]
                break
            }
            response = HTTPServer.writeFile(at: path, content: content)
        case "uploadImage":
            guard let b64 = json["data"] as? String, let imageData = Data(base64Encoded: b64), !imageData.isEmpty else {
                response = ["error": "Missing or invalid image data"]
                break
            }
            response = HTTPServer.saveUploadedImage(imageData)
        default:
            response = ["error": "Unknown request type"]
        }

        guard let responseData = try? JSONSerialization.data(withJSONObject: response) else { return }
        guard session.connectedPeers.contains(peerID) else { return }
        try? session.send(responseData, toPeers: [peerID], with: .reliable)
    }

    private func sendAgentStream(workspace: String, message: String, sessionId: String?, requestId: String, to peerID: MCPeerID, session: MCSession) {
        guard session.connectedPeers.contains(peerID) else { return }
        let (output, error, sid) = AgentRunner.runStreaming(workspace: workspace, message: message, sessionId: sessionId) { delta in
            let msg: [String: Any] = ["type": "stream_chunk", "requestId": requestId, "delta": delta]
            guard let data = try? JSONSerialization.data(withJSONObject: msg), session.connectedPeers.contains(peerID) else { return }
            try? session.send(data, toPeers: [peerID], with: .reliable)
        }
        var done: [String: Any] = ["type": "stream_done", "requestId": requestId, "output": output as Any, "error": error as Any]
        if let s = sid { done["sessionId"] = s }
        if let data = try? JSONSerialization.data(withJSONObject: done), session.connectedPeers.contains(peerID) {
            try? session.send(data, toPeers: [peerID], with: .reliable)
        }
    }
}

extension PeerConnection: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        if let sess = session {
            invitationHandler(true, sess)
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Peer: Did not start advertising: \(error.localizedDescription)")
    }
}

extension PeerConnection: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        if state == .connected {
            print("Peer: Connected to \(peerID.displayName)")
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        handleMessage(data, from: peerID, session: session)
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

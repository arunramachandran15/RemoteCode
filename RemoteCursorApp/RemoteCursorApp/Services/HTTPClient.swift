import Foundation

final class HTTPClient {
    private let baseURL: String
    /// Long timeout for agent (e.g. 30 min) to avoid "timed out" on code changes.
    private static let agentTimeout: TimeInterval = 30 * 60

    init(baseURL: String) {
        var url = baseURL
        if !url.hasPrefix("http") { url = "http://" + url }
        self.baseURL = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func agentRequest(body: [String: Any]) -> URLRequest {
        let url = URL(string: baseURL + "/agent")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = Self.agentTimeout
        return req
    }

    func getRepos() async throws -> [String] {
        let url = URL(string: baseURL + "/repos")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let repos = json?["repos"] as? [String] else { throw NSError(domain: "HTTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]) }
        return repos
    }

    func runAgent(workspace: String, message: String, sessionId: String? = nil) async throws -> AgentResponse {
        var body: [String: Any] = ["workspace": workspace, "message": message]
        if let s = sessionId { body["sessionId"] = s }
        var req = agentRequest(body: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return AgentResponse(
            output: json?["output"] as? String,
            error: json?["error"] as? String,
            sessionId: json?["sessionId"] as? String
        )
    }

    /// Stream agent response; onChunk is called on main actor. Returns final response with sessionId.
    func runAgentStreaming(
        workspace: String,
        message: String,
        sessionId: String? = nil,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> AgentResponse {
        var body: [String: Any] = ["workspace": workspace, "message": message]
        if let s = sessionId { body["sessionId"] = s }
        var req = agentRequest(body: body)
        req.url = URL(string: baseURL + "/agent/stream")
        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw NSError(domain: "HTTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Agent stream failed"])
        }
        var buffer = ""
        var output = ""
        var errorMsg: String?
        var sessionIdResult: String?
        for try await byte in bytes {
            buffer.append(Character(Unicode.Scalar(byte)))
            while let idx = buffer.firstIndex(of: "\n") {
                let line = String(buffer[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
                buffer = String(buffer[buffer.index(after: idx)...])
                guard !line.isEmpty,
                      let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if obj["done"] as? Bool == true {
                    output = obj["output"] as? String ?? output
                    errorMsg = obj["error"] as? String
                    sessionIdResult = obj["sessionId"] as? String
                } else if let delta = obj["delta"] as? String, !delta.isEmpty {
                    output += delta
                    await MainActor.run { onChunk(delta) }
                }
            }
        }
        return AgentResponse(output: output.isEmpty ? nil : output, error: errorMsg, sessionId: sessionIdResult)
    }

    func runCommand(_ command: String, workspace: String?) async throws -> CommandResult {
        let url = URL(string: baseURL + "/run")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 5 * 60
        var body: [String: Any] = ["command": command]
        if let w = workspace { body["workspace"] = w }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return CommandResult(
            stdout: json?["stdout"] as? String,
            stderr: json?["stderr"] as? String,
            exitCode: (json?["exitCode"] as? Int) ?? -1
        )
    }

    func healthCheck() async -> Bool {
        guard let url = URL(string: baseURL + "/health") else { return false }
        do {
            let (_, res) = try await URLSession.shared.data(from: url)
            return (res as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

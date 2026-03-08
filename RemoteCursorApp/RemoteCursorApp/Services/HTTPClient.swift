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

    func listFiles(path: String) async throws -> [FileItem] {
        var comps = URLComponents(string: baseURL + "/files")!
        comps.queryItems = [URLQueryItem(name: "path", value: path)]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let files = json?["files"] as? [[String: Any]] else {
            throw NSError(domain: "HTTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: json?["error"] as? String ?? "Invalid response"])
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
        var comps = URLComponents(string: baseURL + "/file")!
        comps.queryItems = [URLQueryItem(name: "path", value: path)]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let error = json?["error"] as? String { throw NSError(domain: "HTTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: error]) }
        guard let content = json?["content"] as? String else {
            throw NSError(domain: "HTTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No content"])
        }
        return content
    }

    func writeFile(path: String, content: String) async throws {
        let url = URL(string: baseURL + "/file")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["path": path, "content": content])
        req.timeoutInterval = 30
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let error = json?["error"] as? String { throw NSError(domain: "HTTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: error]) }
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

    func uploadImage(_ imageData: Data) async throws -> String {
        let url = URL(string: baseURL + "/upload-image")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        let b64 = imageData.base64EncodedString()
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["data": b64])
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let error = json?["error"] as? String {
            throw NSError(domain: "HTTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: error])
        }
        guard let path = json?["path"] as? String else {
            throw NSError(domain: "HTTPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No path returned"])
        }
        return path
    }

    func trustWorkspace(_ workspace: String) async throws -> (ok: Bool, message: String) {
        let url = URL(string: baseURL + "/trust-workspace")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["workspace": workspace])
        req.timeoutInterval = 30
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let ok = json?["ok"] as? Bool ?? false
        let msg = json?["message"] as? String ?? json?["error"] as? String ?? (ok ? "Done" : "Unknown error")
        return (ok, msg)
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

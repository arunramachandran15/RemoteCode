import Foundation
import Network

final class HTTPServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "http.server")

    func start(port: UInt16) {
        guard let listener = try? NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!) else {
            print("HTTP: Failed to bind port \(port)")
            return
        }
        self.listener = listener
        listener.stateUpdateHandler = { state in
            if state == .ready {
                print("HTTP: Listening on port \(port) (Wi‑Fi)")
            }
        }
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        readRequest(conn: conn)
    }

    private func readRequest(conn: NWConnection, buffer: Data = Data()) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            var buf = buffer
            if let d = data, !d.isEmpty { buf.append(d) }
            if error != nil || isComplete {
                self.respond(conn: conn, data: buf)
                return
            }
            if buf.count > 0, let req = self.parseRequest(buf), req.bodyLength == nil || buf.count >= (req.headerLength + (req.bodyLength ?? 0)) {
                self.respond(conn: conn, data: buf)
                return
            }
            self.readRequest(conn: conn, buffer: buf)
        }
    }

    private struct ParsedRequest {
        let method: String
        let path: String
        let headerLength: Int
        let bodyLength: Int?
    }

    private func parseRequest(_ data: Data) -> ParsedRequest? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        let lines = raw.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1]).split(separator: "?").first.map(String.init) ?? ""
        var headerLength = 0
        var bodyLength: Int?
        for line in lines.dropFirst() {
            if line.isEmpty {
                if let range = raw.range(of: "\r\n\r\n") {
                    headerLength = raw.distance(from: raw.startIndex, to: range.upperBound)
                }
                if let len = lines.first(where: { $0.lowercased().hasPrefix("content-length:") })?
                    .split(separator: ":", maxSplits: 1).last
                    .map({ Int($0.trimmingCharacters(in: .whitespaces)) }) {
                    bodyLength = len
                }
                break
            }
        }
        return ParsedRequest(method: method, path: path, headerLength: headerLength, bodyLength: bodyLength)
    }

    private func respond(conn: NWConnection, data: Data) {
        guard String(data: data, encoding: .utf8) != nil,
              let req = parseRequest(data) else {
            send(conn: conn, status: "400 Bad Request", body: "Bad Request")
            conn.cancel()
            return
        }

        let bodyStart = req.headerLength
        let body = bodyStart < data.count ? Data(data.dropFirst(bodyStart)) : Data()
        let bodyStr = String(data: body, encoding: .utf8)

        if req.method == "GET" && req.path == "/repos" {
            let repos = Config.repoPaths
            let json = (try? JSONSerialization.data(withJSONObject: ["repos": repos])) ?? Data()
            send(conn: conn, status: "200 OK", body: json, contentType: "application/json")
        } else if req.method == "POST" && (req.path == "/agent" || req.path == "/agent/stream") {
            guard let str = bodyStr,
                  let obj = try? JSONSerialization.jsonObject(with: Data(str.utf8)) as? [String: Any],
                  let workspace = obj["workspace"] as? String,
                  let message = obj["message"] as? String else {
                send(conn: conn, status: "400 Bad Request", body: "{\"error\":\"Missing workspace or message\"}", contentType: "application/json")
                conn.cancel()
                return
            }
            let sessionId = obj["sessionId"] as? String
            if req.path == "/agent/stream" {
                sendStreaming(conn: conn, workspace: workspace, message: message, sessionId: sessionId)
                return
            }
            let (output, error, sid) = AgentRunner.run(workspace: workspace, message: message, sessionId: sessionId)
            var response: [String: Any?] = ["output": output, "error": error]
            if let s = sid { response["sessionId"] = s }
            let json = (try? JSONSerialization.data(withJSONObject: response)) ?? Data()
            send(conn: conn, status: "200 OK", body: json, contentType: "application/json")
        } else if req.method == "POST" && req.path == "/run" {
            guard let str = bodyStr,
                  let obj = try? JSONSerialization.jsonObject(with: Data(str.utf8)) as? [String: Any],
                  let command = obj["command"] as? String else {
                send(conn: conn, status: "400 Bad Request", body: "{\"error\":\"Missing command\"}", contentType: "application/json")
                conn.cancel()
                return
            }
            let workspace = obj["workspace"] as? String
            let result = Self.runShellCommand(command, workspace: workspace)
            let json = (try? JSONSerialization.data(withJSONObject: result)) ?? Data()
            send(conn: conn, status: "200 OK", body: json, contentType: "application/json")
        } else if req.method == "GET" && req.path == "/health" {
            send(conn: conn, status: "200 OK", body: "{\"ok\":true}", contentType: "application/json")
        } else {
            send(conn: conn, status: "404 Not Found", body: "Not Found")
        }
        conn.cancel()
    }

    private func send(conn: NWConnection, status: String, body: Data, contentType: String? = nil) {
        var header = "HTTP/1.1 \(status)\r\nContent-Length: \(body.count)\r\n"
        if let ct = contentType { header += "Content-Type: \(ct)\r\n" }
        header += "Connection: close\r\n\r\n"
        let hData = Data(header.utf8)
        conn.send(content: hData, completion: .contentProcessed { _ in })
        conn.send(content: body, completion: .contentProcessed { _ in })
    }

    private func send(conn: NWConnection, status: String, body: String, contentType: String? = nil) {
        send(conn: conn, status: status, body: Data(body.utf8), contentType: contentType)
    }

    static func runShellCommand(_ command: String, workspace: String?) -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        if let w = workspace, !w.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: w)
        }
        process.environment = ProcessInfo.processInfo.environment
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ["stdout": "", "stderr": "Failed to run: \(error.localizedDescription)", "exitCode": -1]
        }
        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ["stdout": stdout, "stderr": stderr, "exitCode": process.terminationStatus]
    }

    private func sendStreaming(conn: NWConnection, workspace: String, message: String, sessionId: String?) {
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/x-ndjson\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(header.utf8), completion: .contentProcessed { _ in })
        let (output, error, sid) = AgentRunner.runStreaming(workspace: workspace, message: message, sessionId: sessionId) { delta in
            let line = (try? JSONSerialization.data(withJSONObject: ["delta": delta])) ?? Data()
            let chunk = String(format: "%X\r\n", line.count) + String(data: line, encoding: .utf8)! + "\r\n"
            conn.send(content: Data(chunk.utf8), completion: .contentProcessed { _ in })
        }
        var done: [String: Any?] = ["done": true, "output": output, "error": error]
        if let s = sid { done["sessionId"] = s }
        let line = (try? JSONSerialization.data(withJSONObject: done)) ?? Data()
        let chunk = String(format: "%X\r\n", line.count) + String(data: line, encoding: .utf8)! + "\r\n0\r\n\r\n"
        conn.send(content: Data(chunk.utf8), completion: .contentProcessed { _ in })
        conn.cancel()
    }
}

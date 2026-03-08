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
        let queryParams: [String: String]
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
        let rawPath = String(parts[1])
        let pathParts = rawPath.split(separator: "?", maxSplits: 1)
        let path = String(pathParts[0])
        var queryParams: [String: String] = [:]
        if pathParts.count > 1 {
            for param in pathParts[1].split(separator: "&") {
                let kv = param.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    queryParams[String(kv[0])] = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                }
            }
        }
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
        return ParsedRequest(method: method, path: path, queryParams: queryParams, headerLength: headerLength, bodyLength: bodyLength)
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
        } else if req.method == "GET" && req.path == "/files" {
            guard let dirPath = req.queryParams["path"], !dirPath.isEmpty else {
                send(conn: conn, status: "400 Bad Request", body: "{\"error\":\"Missing path\"}", contentType: "application/json")
                conn.cancel()
                return
            }
            let result = Self.listFiles(at: dirPath)
            let json = (try? JSONSerialization.data(withJSONObject: result)) ?? Data()
            send(conn: conn, status: "200 OK", body: json, contentType: "application/json")
        } else if req.method == "GET" && req.path == "/file" {
            guard let filePath = req.queryParams["path"], !filePath.isEmpty else {
                send(conn: conn, status: "400 Bad Request", body: "{\"error\":\"Missing path\"}", contentType: "application/json")
                conn.cancel()
                return
            }
            let result = Self.readFile(at: filePath)
            let json = (try? JSONSerialization.data(withJSONObject: result)) ?? Data()
            send(conn: conn, status: "200 OK", body: json, contentType: "application/json")
        } else if req.method == "POST" && req.path == "/file" {
            guard let str = bodyStr,
                  let obj = try? JSONSerialization.jsonObject(with: Data(str.utf8)) as? [String: Any],
                  let filePath = obj["path"] as? String,
                  let content = obj["content"] as? String else {
                send(conn: conn, status: "400 Bad Request", body: "{\"error\":\"Missing path or content\"}", contentType: "application/json")
                conn.cancel()
                return
            }
            let result = Self.writeFile(at: filePath, content: content)
            let json = (try? JSONSerialization.data(withJSONObject: result)) ?? Data()
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
        } else if req.method == "POST" && req.path == "/upload-image" {
            let imageData: Data
            if let str = bodyStr,
               let obj = try? JSONSerialization.jsonObject(with: Data(str.utf8)) as? [String: Any],
               let b64 = obj["data"] as? String,
               let decoded = Data(base64Encoded: b64) {
                imageData = decoded
            } else {
                imageData = body
            }
            guard !imageData.isEmpty else {
                send(conn: conn, status: "400 Bad Request", body: "{\"error\":\"No image data\"}", contentType: "application/json")
                conn.cancel()
                return
            }
            let result = Self.saveUploadedImage(imageData)
            let json = (try? JSONSerialization.data(withJSONObject: result)) ?? Data()
            send(conn: conn, status: "200 OK", body: json, contentType: "application/json")
        } else if req.method == "POST" && req.path == "/trust-workspace" {
            guard let str = bodyStr,
                  let obj = try? JSONSerialization.jsonObject(with: Data(str.utf8)) as? [String: Any],
                  let workspace = obj["workspace"] as? String else {
                send(conn: conn, status: "400 Bad Request", body: "{\"error\":\"Missing workspace\"}", contentType: "application/json")
                conn.cancel()
                return
            }
            let result = Self.trustWorkspace(workspace)
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

    static func listFiles(at path: String) -> [String: Any] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return ["error": "Not a directory", "files": []]
        }
        guard let entries = try? fm.contentsOfDirectory(atPath: path) else {
            return ["error": "Cannot read directory", "files": []]
        }
        var files: [[String: Any]] = []
        for name in entries.sorted() {
            if name.hasPrefix(".") { continue }
            let full = (path as NSString).appendingPathComponent(name)
            var entryIsDir: ObjCBool = false
            fm.fileExists(atPath: full, isDirectory: &entryIsDir)
            var entry: [String: Any] = ["name": name, "path": full, "isDirectory": entryIsDir.boolValue]
            if !entryIsDir.boolValue, let attrs = try? fm.attributesOfItem(atPath: full) {
                entry["size"] = (attrs[.size] as? Int) ?? 0
            }
            files.append(entry)
        }
        return ["files": files]
    }

    static func readFile(at path: String) -> [String: Any] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            return ["error": "File not found"]
        }
        guard let data = fm.contents(atPath: path),
              let content = String(data: data, encoding: .utf8) else {
            return ["error": "Cannot read file (binary or encoding issue)"]
        }
        return ["content": content, "path": path]
    }

    static func writeFile(at path: String, content: String) -> [String: Any] {
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
            return ["ok": true]
        } catch {
            return ["error": error.localizedDescription]
        }
    }

    static func saveUploadedImage(_ data: Data) -> [String: Any] {
        let cacheDir: String
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            cacheDir = caches.appendingPathComponent("remotecursor_images").path
        } else {
            cacheDir = NSTemporaryDirectory() + "remotecursor_images/"
        }
        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        let filename = "img_\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 1000...9999)).jpg"
        let path = cacheDir + "/" + filename
        do {
            try data.write(to: URL(fileURLWithPath: path))
            return ["path": path, "ok": true]
        } catch {
            return ["error": error.localizedDescription]
        }
    }

    static func trustWorkspace(_ workspace: String) -> [String: Any] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var messages: [String] = []

        // Approach 1: Write trust directly into Cursor's state database
        let dbResult = grantTrustInStateDB(workspace: workspace, home: home)
        messages.append(dbResult)

        // Approach 2: Write trust into Cursor's settings.json
        let settingsResult = ensureTrustSettingsDisabled(home: home)
        messages.append(settingsResult)

        // Approach 3: Open folder in Cursor GUI as fallback
        let cursorPath = findCursorCLI(home: home)
        if let cp = cursorPath {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cp)
            process.arguments = ["--folder-uri", "file://\(workspace)", "--reuse-window"]
            process.environment = ProcessInfo.processInfo.environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            if let _ = try? process.run() {
                messages.append("Opened folder in Cursor")
            }
        }

        let combined = messages.joined(separator: ". ")
        print("TrustWorkspace: \(combined)")
        return ["ok": true, "message": "Trust applied. If the agent still rejects, click 'Trust' in the Cursor window on your Mac, then try again. (\(combined))"]
    }

    private static func findCursorCLI(home: String) -> String? {
        let cursorPaths = [
            "\(home)/.local/bin/cursor",
            "/usr/local/bin/cursor",
            "/opt/homebrew/bin/cursor",
            "/Applications/Cursor.app/Contents/Resources/app/bin/cursor"
        ]
        for p in cursorPaths {
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["cursor"]
        which.environment = ["PATH": "\(home)/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:\(ProcessInfo.processInfo.environment["PATH"] ?? "")"]
        let pipe = Pipe()
        which.standardOutput = pipe
        which.standardError = FileHandle.nullDevice
        try? which.run()
        which.waitUntilExit()
        if which.terminationStatus == 0,
           let data = pipe.fileHandleForReading.readDataToEndOfFile() as Data?,
           let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return path
        }
        return nil
    }

    private static func grantTrustInStateDB(workspace: String, home: String) -> String {
        let dbPaths = [
            "\(home)/Library/Application Support/Cursor/User/globalStorage/state.vscdb",
            "\(home)/Library/Application Support/Cursor/User/globalStorage/storage.json",
        ]
        let fm = FileManager.default
        for dbPath in dbPaths where fm.fileExists(atPath: dbPath) {
            if dbPath.hasSuffix(".vscdb") {
                let result = runShellCommand(
                    """
                    sqlite3 '\(dbPath)' "SELECT value FROM ItemTable WHERE key = 'storage.serviceMachineId';" 2>/dev/null && \
                    echo "DB accessible" || echo "DB not accessible"
                    """,
                    workspace: nil
                )
                let stdout = result["stdout"] as? String ?? ""
                if stdout.contains("DB accessible") || !stdout.isEmpty {
                    let folderUri = "file://\(workspace)"
                    let trustCmd = """
                    sqlite3 '\(dbPath)' "
                    INSERT OR REPLACE INTO ItemTable (key, value)
                    SELECT 'security.workspace.trust.grantedFolders',
                    CASE
                        WHEN value IS NULL THEN '[\"\(folderUri)\"]'
                        WHEN value NOT LIKE '%\(folderUri)%' THEN
                            substr(value, 1, length(value)-1) || ',\"\(folderUri)\"]'
                        ELSE value
                    END
                    FROM (SELECT value FROM ItemTable WHERE key = 'security.workspace.trust.grantedFolders'
                          UNION ALL SELECT NULL WHERE NOT EXISTS
                          (SELECT 1 FROM ItemTable WHERE key = 'security.workspace.trust.grantedFolders'))
                    LIMIT 1;
                    " 2>&1
                    """
                    let trustResult = runShellCommand(trustCmd, workspace: nil)
                    let trustErr = trustResult["stderr"] as? String ?? ""
                    let trustExit = trustResult["exitCode"] as? Int ?? -1
                    if trustExit == 0 && trustErr.isEmpty {
                        return "Added to state DB trust list"
                    } else {
                        return "State DB write attempted (exit \(trustExit)): \(trustErr)"
                    }
                }
                return "State DB found but not accessible"
            }
        }
        return "State DB not found"
    }

    private static func ensureTrustSettingsDisabled(home: String) -> String {
        let settingsPath = "\(home)/Library/Application Support/Cursor/User/settings.json"
        let fm = FileManager.default
        guard fm.fileExists(atPath: settingsPath) else { return "Settings file not found" }
        guard let data = fm.contents(atPath: settingsPath),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Cannot parse settings"
        }
        let key = "security.workspace.trust.enabled"
        if json[key] as? Bool == false {
            return "Trust already disabled in settings"
        }
        json[key] = false
        guard let newData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else {
            return "Cannot serialize settings"
        }
        do {
            try newData.write(to: URL(fileURLWithPath: settingsPath))
            return "Disabled workspace trust in settings"
        } catch {
            return "Cannot write settings: \(error.localizedDescription)"
        }
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

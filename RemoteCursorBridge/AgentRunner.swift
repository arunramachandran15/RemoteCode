import Foundation

enum AgentRunner {
    private static var agentExecutablePath: String? {
        let pathEnv = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:\(ProcessInfo.processInfo.environment["PATH"] ?? "")"
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["agent"]
        which.standardOutput = Pipe()
        which.standardError = FileHandle.nullDevice
        which.environment = ["PATH": pathEnv]
        try? which.run()
        which.waitUntilExit()
        if which.terminationStatus == 0,
           let data = (which.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile(),
           let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty { return path }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for p in ["\(home)/.local/bin/agent", "/usr/local/bin/agent", "/opt/homebrew/bin/agent"] {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: p, isDirectory: &isDir), !isDir.boolValue { return p }
        }
        return nil
    }

    private static func agentEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["CURSOR_TRUST_WORKSPACE"] = "1"
        env["VSCODE_SKIP_WORKSPACE_TRUST"] = "1"
        return env
    }

    private static func pipeYesToStdin(_ process: Process) {
        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        stdinPipe.fileHandleForWriting.write(Data("y\ny\nyes\n".utf8))
        try? stdinPipe.fileHandleForWriting.close()
    }

    /// Create a new chat and return its session ID.
    static func createChat(workspace: String) -> String? {
        guard let agentPath = agentExecutablePath else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: agentPath)
        process.arguments = ["create-chat", "--workspace", workspace]
        process.currentDirectoryURL = URL(fileURLWithPath: workspace)
        process.environment = agentEnvironment()
        let pipe = Pipe()
        process.standardOutput = pipe
        let errPipe = Pipe()
        process.standardError = errPipe
        try? process.run()
        process.waitUntilExit()
        let outData = pipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let id = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if process.terminationStatus != 0 || id.isEmpty {
            print("AgentRunner: create-chat failed (exit \(process.terminationStatus))")
            if !errStr.isEmpty { print("  stderr: \(errStr)") }
            if !id.isEmpty { print("  stdout: \(id)") }
            return nil
        }
        return id
    }

    /// Run agent with optional session (resume). Streams text deltas via onChunk. Returns (fullOutput, error, sessionId).
    static func runStreaming(
        workspace: String,
        message: String,
        sessionId: String?,
        onChunk: @escaping (String) -> Void
    ) -> (output: String?, error: String?, sessionId: String?) {
        guard let agentPath = agentExecutablePath else {
            return (nil, "Cursor CLI (agent) not found. Install from Cursor → Install CLI, then restart the bridge.", nil)
        }
        var sid = sessionId
        // Don't call create-chat for new workspaces (it can prompt for trust). Use -p --trust and capture session_id from stream.
        // --trust only works with -p (print/headless mode) so workspace is trusted without interactive prompt for new folders.
        var args: [String] = ["-p", message, "--trust", "--workspace", workspace, "--output-format", "stream-json", "--stream-partial-output"]
        if let s = sid {
            args = ["--resume", s] + args
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: agentPath)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: workspace)
        process.environment = agentEnvironment()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        var fullOutput = ""
        var buffer = ""
        outPipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty else { return }
            buffer += String(data: data, encoding: .utf8) ?? ""
            while let idx = buffer.firstIndex(of: "\n") {
                let line = String(buffer[..<idx]).trimmingCharacters(in: .whitespaces)
                buffer = String(buffer[buffer.index(after: idx)...])
                guard !line.isEmpty,
                      let d = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let type = json["type"] as? String else { continue }
                if type == "result", json["subtype"] as? String == "success" {
                    if let result = json["result"] as? String, !result.isEmpty { fullOutput = result }
                    if let s = json["session_id"] as? String, !s.isEmpty { sid = s }
                } else if type == "assistant", let message = json["message"] as? [String: Any], let content = message["content"] as? [[String: Any]] {
                    for part in content {
                        if part["type"] as? String == "text", let text = part["text"] as? String, !text.isEmpty {
                            fullOutput += text
                            onChunk(text)
                        }
                    }
                } else {
                    let text = json["text"] as? String ?? json["content"] as? String ?? json["delta"] as? String
                    if let t = text, !t.isEmpty {
                        fullOutput += t
                        onChunk(t)
                    }
                }
            }
        }
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (nil, "Failed to run agent: \(error.localizedDescription)", sid)
        }
        outPipe.fileHandleForReading.readabilityHandler = nil
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        var remaining = buffer + (String(data: outData, encoding: .utf8) ?? "")
        while let idx = remaining.firstIndex(of: "\n") {
            let line = String(remaining[..<idx]).trimmingCharacters(in: .whitespaces)
            remaining = String(remaining[remaining.index(after: idx)...])
            guard !line.isEmpty, let d = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let type = json["type"] as? String else { continue }
            if type == "result", json["subtype"] as? String == "success" {
                if let result = json["result"] as? String, !result.isEmpty { fullOutput = result }
                if let s = json["session_id"] as? String, !s.isEmpty { sid = s }
            } else if type == "assistant", let message = json["message"] as? [String: Any], let content = message["content"] as? [[String: Any]] {
                for part in content {
                    if part["type"] as? String == "text", let text = part["text"] as? String { fullOutput += text }
                }
            }
        }
        if fullOutput.isEmpty, !outData.isEmpty {
            fullOutput = String(data: outData, encoding: .utf8) ?? ""
        }
        var err = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if err.contains("No such file or directory") || err.contains("not found") {
            err = "Cursor CLI (agent) not found. Install from Cursor → Install CLI. Restart the bridge."
        }
        let errLower = err.lowercased()
        if process.terminationStatus != 0 &&
           (errLower.contains("workspace trust") || errLower.contains("pass --trust") || errLower.contains("--yolo")) {
            print("AgentRunner: Trust error detected. stderr: \(err)")
            if err.isEmpty {
                err = "Workspace trust required. Open '\(workspace)' in Cursor on your Mac and click 'Trust' in the dialog, then try again."
            }
        }
        if process.terminationStatus != 0 {
            return (fullOutput.isEmpty ? nil : fullOutput, err.isEmpty ? "Exit code \(process.terminationStatus)" : err, sid)
        }
        return (fullOutput.isEmpty ? nil : fullOutput, err.isEmpty ? nil : err, sid)
    }

    /// Non-streaming run; uses streaming and accumulates. Returns sessionId for continuity.
    static func run(workspace: String, message: String, sessionId: String? = nil) -> (output: String?, error: String?, sessionId: String?) {
        var acc = ""
        let (out, err, sid) = runStreaming(workspace: workspace, message: message, sessionId: sessionId) { acc += $0 }
        return (out ?? (acc.isEmpty ? nil : acc), err, sid)
    }
}

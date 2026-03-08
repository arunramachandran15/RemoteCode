import SwiftUI

private let sessionStorageKey = "agent_sessions"

struct AgentView: View {
    @ObservedObject var peer: PeerClient
    let wifiURL: String
    let connectionMode: ConnectionMode?
    var onConnectionLost: (() -> Void)?
    @Binding var externalMessage: String
    @State private var repos: [RepoItem] = []
    @State private var selectedRepo: RepoItem?
    @State private var message = ""
    @State private var chatMessages: [ChatMessage] = []
    @State private var streamingContent = ""
    @State private var loadError: String?
    @State private var initialLoad = true
    @State private var loading = false
    @State private var runningCommand: String?
    @State private var commandResult: CommandResult?
    @State private var showCommandResult = false
    @AppStorage(sessionStorageKey) private var sessionStorageData = "{}"

    private func getSessionId(workspace: String) -> String? {
        ((try? JSONDecoder().decode([String: String].self, from: Data(sessionStorageData.utf8))) ?? [:])[workspace]
    }

    private func setSessionId(workspace: String, value: String?) {
        var d = (try? JSONDecoder().decode([String: String].self, from: Data(sessionStorageData.utf8))) ?? [:]
        if let v = value { d[workspace] = v } else { d.removeValue(forKey: workspace) }
        if let data = try? JSONEncoder().encode(d), let s = String(data: data, encoding: .utf8) {
            sessionStorageData = s
        }
    }

    var body: some View {
        List {
            Section("Repository") {
                if repos.isEmpty && !loading {
                    Text(loadError ?? "No repos").foregroundStyle(loadError != nil ? .red : .secondary)
                } else {
                    Picker("Repo", selection: $selectedRepo) {
                        Text("Select…").tag(nil as RepoItem?)
                        ForEach(repos) { r in
                            Text(r.displayName).tag(r as RepoItem?)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            if selectedRepo != nil {
                Section("Chat history") {
                    ForEach(chatMessages) { msg in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(msg.role == .user ? "You" : "Agent")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if msg.role == .assistant {
                                MarkdownView(content: msg.content, onRunCommand: { cmd in
                                    executeCommand(cmd)
                                })
                            } else {
                                Text(msg.content)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if !streamingContent.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Agent")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            MarkdownView(content: streamingContent)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if loading && streamingContent.isEmpty {
                Section {
                    HStack {
                        ProgressView()
                        Text(runningCommand != nil ? "Running command…" : "Running agent…")
                    }
                }
            }

            Section("Message to agent") {
                TextField("Ask or command…", text: $message, axis: .vertical)
                    .lineLimit(3...8)
                Button("Go") {
                    sendMessage()
                }
                .disabled(selectedRepo == nil || message.trimmingCharacters(in: .whitespaces).isEmpty || loading)
            }
        }
        .navigationTitle("Agent")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if initialLoad {
                initialLoad = false
                loadRepos()
            }
            reloadChat()
        }
        .onChange(of: selectedRepo?.path) { _ in reloadChat() }
        .onChange(of: externalMessage) { newValue in
            if !newValue.isEmpty {
                message = newValue
                externalMessage = ""
                sendMessage()
            }
        }
        .sheet(isPresented: $showCommandResult) {
            commandResultSheet
        }
    }

    @ViewBuilder
    private var commandResultSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let cmd = runningCommand {
                        Text("Command")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(cmd)
                            .font(.system(.callout, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                    if let result = commandResult {
                        if result.exitCode != 0 {
                            Label("Exit code: \(result.exitCode)", systemImage: "xmark.circle")
                                .foregroundStyle(.red)
                                .font(.caption)
                        } else {
                            Label("Success", systemImage: "checkmark.circle")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                        if let out = result.stdout, !out.isEmpty {
                            Text("stdout")
                                .font(.caption).foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(out)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                        if let err = result.stderr, !err.isEmpty {
                            Text("stderr")
                                .font(.caption).foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(err)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    } else {
                        HStack {
                            ProgressView()
                            Text("Running…")
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Command Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showCommandResult = false }
                }
                if commandResult != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send to Agent") {
                            sendCommandResultToAgent()
                            showCommandResult = false
                        }
                    }
                }
            }
        }
    }

    private func executeCommand(_ command: String) {
        runningCommand = command
        commandResult = nil
        showCommandResult = true
        Task {
            do {
                let result: CommandResult
                let workspace = selectedRepo?.path
                if connectionMode == .wifi {
                    result = try await HTTPClient(baseURL: wifiURL.trimmingCharacters(in: .whitespaces))
                        .runCommand(command, workspace: workspace)
                } else {
                    result = try await peer.runCommand(command, workspace: workspace)
                }
                await MainActor.run { commandResult = result }
            } catch {
                await MainActor.run {
                    commandResult = CommandResult(stdout: nil, stderr: error.localizedDescription, exitCode: -1)
                }
            }
        }
    }

    private func sendCommandResultToAgent() {
        guard let result = commandResult, let cmd = runningCommand else { return }
        var output = "I ran this command on the Mac:\n```\n\(cmd)\n```\n"
        output += "Exit code: \(result.exitCode)\n"
        if let out = result.stdout, !out.isEmpty {
            output += "stdout:\n```\n\(out)\n```\n"
        }
        if let err = result.stderr, !err.isEmpty {
            output += "stderr:\n```\n\(err)\n```\n"
        }
        message = output
        sendMessage()
        runningCommand = nil
        commandResult = nil
    }

    private func reloadChat() {
        guard let repo = selectedRepo else { return }
        let sid = getSessionId(workspace: repo.path)
        chatMessages = ChatStore.shared.messages(workspacePath: repo.path, sessionId: sid)
    }

    private func loadRepos() {
        loadError = nil
        loading = true
        Task {
            do {
                let paths: [String]
                if connectionMode == .wifi {
                    paths = try await HTTPClient(baseURL: wifiURL.trimmingCharacters(in: .whitespaces)).getRepos()
                } else {
                    paths = try await peer.getRepos()
                }
                await MainActor.run {
                    repos = paths.map { RepoItem(id: $0, path: $0) }
                    if selectedRepo == nil, let first = repos.first { selectedRepo = first }
                    loading = false
                    reloadChat()
                }
            } catch {
                await MainActor.run {
                    loadError = error.localizedDescription
                    loading = false
                    if isConnectionError(error) { onConnectionLost?() }
                }
            }
        }
    }

    private func isConnectionError(_ error: Error) -> Bool {
        let s = error.localizedDescription.lowercased()
        return s.contains("not connected") || s.contains("could not connect") || s.contains("network") || s.contains("timed out") || (error as NSError).code == -1009 || (error as NSError).code == -1004
    }

    private func sendMessage() {
        guard let repo = selectedRepo else { return }
        let text = message.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        message = ""
        loading = true
        streamingContent = ""

        let userMsg = ChatMessage(
            id: UUID().uuidString,
            workspacePath: repo.path,
            sessionId: getSessionId(workspace: repo.path),
            role: .user,
            content: text,
            createdAt: Date()
        )
        ChatStore.shared.insert(userMsg)
        reloadChat()

        let sid = getSessionId(workspace: repo.path)
        Task {
            do {
                let res: AgentResponse
                if connectionMode == .wifi {
                    let client = HTTPClient(baseURL: wifiURL.trimmingCharacters(in: .whitespaces))
                    res = try await client.runAgentStreaming(workspace: repo.path, message: text, sessionId: sid) { delta in
                        streamingContent += delta
                    }
                } else {
                    res = try await peer.runAgentStreaming(workspace: repo.path, message: text, sessionId: sid) { delta in
                        streamingContent += delta
                    }
                }
                await MainActor.run {
                    if let newSid = res.sessionId {
                        setSessionId(workspace: repo.path, value: newSid)
                    }
                    let content = (res.output ?? "") + (res.error.map { "\n\nError: \($0)" } ?? "")
                    if !content.isEmpty {
                        let assistantMsg = ChatMessage(
                            id: UUID().uuidString,
                            workspacePath: repo.path,
                            sessionId: res.sessionId,
                            role: .assistant,
                            content: content,
                            createdAt: Date()
                        )
                        ChatStore.shared.insert(assistantMsg)
                    }
                    streamingContent = ""
                    loading = false
                    reloadChat()
                }
            } catch {
                await MainActor.run {
                    streamingContent = ""
                    loading = false
                    let errMsg = ChatMessage(
                        id: UUID().uuidString,
                        workspacePath: repo.path,
                        sessionId: sid,
                        role: .assistant,
                        content: "Error: \(error.localizedDescription)",
                        createdAt: Date()
                    )
                    ChatStore.shared.insert(errMsg)
                    reloadChat()
                    if isConnectionError(error) { onConnectionLost?() }
                }
            }
        }
    }
}

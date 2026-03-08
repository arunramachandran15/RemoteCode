import SwiftUI

struct TerminalView: View {
    @ObservedObject var peer: PeerClient
    let wifiURL: String
    let connectionMode: ConnectionMode?
    /// Set this to send terminal output to the Agent tab.
    @Binding var sendToAgent: String
    @State private var command = ""
    @State private var history: [TerminalEntry] = []
    @State private var running = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(history) { entry in
                            terminalEntryView(entry)
                                .id(entry.id)
                        }
                        if running {
                            HStack {
                                ProgressView()
                                Text("Running…").foregroundStyle(.secondary)
                            }
                            .id("running")
                        }
                    }
                    .padding()
                }
                .onChange(of: history.count) { _ in
                    if let last = history.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: running) { isRunning in
                    if isRunning {
                        withAnimation { proxy.scrollTo("running", anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Enter command…", text: $command, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)

                Button {
                    runCommand()
                } label: {
                    Image(systemName: "play.fill")
                        .padding(10)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                }
                .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty || running)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle("Terminal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("Clear") { history.removeAll() }
                    .disabled(history.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func terminalEntryView(_ entry: TerminalEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("$")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.green)
                Text(entry.command)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button {
                    UIPasteboard.general.string = entry.command
                } label: {
                    Image(systemName: "doc.on.doc").font(.caption)
                }
                .buttonStyle(.borderless)
            }

            if let result = entry.result {
                if result.exitCode != 0 {
                    Text("exit \(result.exitCode)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                if let out = result.stdout, !out.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(out)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(6)
                }
                if let err = result.stderr, !err.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(err)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(6)
                }

                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = formatOutput(result)
                    } label: {
                        Label("Copy Output", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)

                    Button {
                        var text = "I ran `\(entry.command)` on the Mac.\nExit code: \(result.exitCode)\n"
                        if let out = result.stdout, !out.isEmpty {
                            text += "stdout:\n```\n\(out)\n```\n"
                        }
                        if let err = result.stderr, !err.isEmpty {
                            text += "stderr:\n```\n\(err)\n```\n"
                        }
                        sendToAgent = text
                    } label: {
                        Label("Send to Agent", systemImage: "arrowshape.turn.up.right.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
                .padding(.top, 4)
            } else {
                HStack {
                    ProgressView()
                    Text("Running…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatOutput(_ result: CommandResult) -> String {
        var s = ""
        if let out = result.stdout, !out.isEmpty { s += out }
        if let err = result.stderr, !err.isEmpty {
            if !s.isEmpty { s += "\n" }
            s += err
        }
        return s
    }

    private func runCommand() {
        let cmd = command.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        command = ""
        let entry = TerminalEntry(command: cmd, result: nil)
        history.append(entry)
        running = true

        Task {
            do {
                let result: CommandResult
                if connectionMode == .wifi {
                    result = try await HTTPClient(baseURL: wifiURL.trimmingCharacters(in: .whitespaces))
                        .runCommand(cmd, workspace: nil)
                } else {
                    result = try await peer.runCommand(cmd, workspace: nil)
                }
                await MainActor.run {
                    if let idx = history.firstIndex(where: { $0.id == entry.id }) {
                        history[idx].result = result
                    }
                    running = false
                }
            } catch {
                await MainActor.run {
                    if let idx = history.firstIndex(where: { $0.id == entry.id }) {
                        history[idx].result = CommandResult(stdout: nil, stderr: error.localizedDescription, exitCode: -1)
                    }
                    running = false
                }
            }
        }
    }
}

struct TerminalEntry: Identifiable {
    let id = UUID().uuidString
    let command: String
    var result: CommandResult?
}

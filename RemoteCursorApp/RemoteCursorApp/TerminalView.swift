import SwiftUI

struct TerminalView: View {
    @ObservedObject var peer: PeerClient
    let wifiURL: String
    let connectionMode: ConnectionMode?
    @Binding var sendToAgent: String
    @State private var command = ""
    @State private var history: [TerminalEntry] = []
    @State private var running = false
    @State private var commandSuggestions: [String] = []
    @State private var showSuggestions = false

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

            if showSuggestions && !commandSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(commandSuggestions, id: \.self) { suggestion in
                            Button {
                                command = suggestion
                                showSuggestions = false
                            } label: {
                                Text(suggestion)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
                .background(Color(.systemGray6))
            }

            HStack(spacing: 8) {
                TextField("Enter command…", text: $command, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: command) { newValue in
                        updateSuggestions(for: newValue)
                    }

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
                Button("Clear") {
                    history.removeAll()
                    TerminalHistoryStore.shared.clearAll()
                }
                .disabled(history.isEmpty)
            }
        }
        .onAppear { loadHistory() }
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
                    command = entry.command
                } label: {
                    Image(systemName: "arrow.counterclockwise").font(.caption)
                }
                .buttonStyle(.borderless)
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

    private func updateSuggestions(for text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            showSuggestions = false
            return
        }
        let past = TerminalHistoryStore.shared.recentCommands(limit: 50)
        commandSuggestions = past
            .filter { $0.lowercased().contains(trimmed.lowercased()) && $0 != trimmed }
            .uniqued()
            .prefix(5)
            .map { $0 }
        showSuggestions = !commandSuggestions.isEmpty
    }

    private func loadHistory() {
        history = TerminalHistoryStore.shared.loadAll()
    }

    private func runCommand() {
        let cmd = command.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        command = ""
        showSuggestions = false
        let entry = TerminalEntry(command: cmd, result: nil)
        history.append(entry)
        TerminalHistoryStore.shared.insert(entry)
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
                        TerminalHistoryStore.shared.updateResult(id: entry.id, result: result)
                    }
                    running = false
                }
            } catch {
                await MainActor.run {
                    let errResult = CommandResult(stdout: nil, stderr: error.localizedDescription, exitCode: -1)
                    if let idx = history.firstIndex(where: { $0.id == entry.id }) {
                        history[idx].result = errResult
                        TerminalHistoryStore.shared.updateResult(id: entry.id, result: errResult)
                    }
                    running = false
                }
            }
        }
    }
}

struct TerminalEntry: Identifiable {
    let id: String
    let command: String
    var result: CommandResult?

    init(id: String = UUID().uuidString, command: String, result: CommandResult? = nil) {
        self.id = id
        self.command = command
        self.result = result
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - Persistent Terminal History (SQLite)

import SQLite3

final class TerminalHistoryStore {
    static let shared = TerminalHistoryStore()
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "terminalhistory.db")
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: (@convention(c) (UnsafeMutableRawPointer?) -> Void).self)

    private init() {
        queue.sync { open() }
    }

    private var dbPath: String {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("terminal_history.sqlite").path
    }

    private func open() {
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else { return }
        let sql = """
        CREATE TABLE IF NOT EXISTS terminal_history (
            id TEXT PRIMARY KEY,
            command TEXT NOT NULL,
            stdout TEXT,
            stderr TEXT,
            exit_code INTEGER,
            created_at REAL NOT NULL
        );
        """
        var err: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, sql, nil, nil, &err)
        if let e = err { sqlite3_free(e) }
    }

    func insert(_ entry: TerminalEntry) {
        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            let sql = "INSERT OR REPLACE INTO terminal_history (id, command, created_at) VALUES (?, ?, ?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            entry.id.withCString { sqlite3_bind_text(stmt, 1, $0, -1, self.SQLITE_TRANSIENT) }
            entry.command.withCString { sqlite3_bind_text(stmt, 2, $0, -1, self.SQLITE_TRANSIENT) }
            sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
            sqlite3_step(stmt)
        }
    }

    func updateResult(id: String, result: CommandResult) {
        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }
            let sql = "UPDATE terminal_history SET stdout = ?, stderr = ?, exit_code = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            if let out = result.stdout { out.withCString { sqlite3_bind_text(stmt, 1, $0, -1, self.SQLITE_TRANSIENT) } }
            else { sqlite3_bind_null(stmt, 1) }
            if let err = result.stderr { err.withCString { sqlite3_bind_text(stmt, 2, $0, -1, self.SQLITE_TRANSIENT) } }
            else { sqlite3_bind_null(stmt, 2) }
            sqlite3_bind_int(stmt, 3, Int32(result.exitCode))
            id.withCString { sqlite3_bind_text(stmt, 4, $0, -1, self.SQLITE_TRANSIENT) }
            sqlite3_step(stmt)
        }
    }

    func loadAll() -> [TerminalEntry] {
        queue.sync {
            guard let db = self.db else { return [] }
            let sql = "SELECT id, command, stdout, stderr, exit_code FROM terminal_history ORDER BY created_at ASC LIMIT 200;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            var entries: [TerminalEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let cmd = String(cString: sqlite3_column_text(stmt, 1))
                let stdout = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
                let stderr = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
                let exitCode = sqlite3_column_type(stmt, 4) != SQLITE_NULL ? Int(sqlite3_column_int(stmt, 4)) : nil
                var result: CommandResult?
                if exitCode != nil {
                    result = CommandResult(stdout: stdout, stderr: stderr, exitCode: exitCode!)
                }
                entries.append(TerminalEntry(id: id, command: cmd, result: result))
            }
            return entries
        }
    }

    func recentCommands(limit: Int) -> [String] {
        queue.sync {
            guard let db = self.db else { return [] }
            let sql = "SELECT DISTINCT command FROM terminal_history ORDER BY created_at DESC LIMIT ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            var cmds: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                cmds.append(String(cString: sqlite3_column_text(stmt, 0)))
            }
            return cmds
        }
    }

    func clearAll() {
        queue.async { [weak self] in
            guard let db = self?.db else { return }
            sqlite3_exec(db, "DELETE FROM terminal_history;", nil, nil, nil)
        }
    }
}

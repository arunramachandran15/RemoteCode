import Foundation
import SQLite3

/// SQLite destructor: copy string (not exposed by Swift's SQLite3 module).
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: (@convention(c) (UnsafeMutableRawPointer?) -> Void).self)

/// Persists chat messages to a local SQLite database.
final class ChatStore {
    static let shared = ChatStore()
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "chatstore.db")

    private init() {
        queue.sync { open() }
    }

    private var dbPath: String {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("chat_history.sqlite").path
    }

    private func open() {
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            return
        }
        let sql = """
        CREATE TABLE IF NOT EXISTS chat_messages (
            id TEXT PRIMARY KEY,
            workspace_path TEXT NOT NULL,
            session_id TEXT,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_chat_workspace_session ON chat_messages(workspace_path, session_id);
        """
        var err: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, sql, nil, nil, &err)
        if let e = err {
            sqlite3_free(e)
        }
    }

    func insert(_ message: ChatMessage) {
        queue.async { [weak self] in
            guard let db = self?.db else { return }
            let sql = "INSERT OR REPLACE INTO chat_messages (id, workspace_path, session_id, role, content, created_at) VALUES (?, ?, ?, ?, ?, ?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            message.id.withCString { sqlite3_bind_text(stmt, 1, $0, -1, SQLITE_TRANSIENT) }
            message.workspacePath.withCString { sqlite3_bind_text(stmt, 2, $0, -1, SQLITE_TRANSIENT) }
            if let s = message.sessionId {
                s.withCString { sqlite3_bind_text(stmt, 3, $0, -1, SQLITE_TRANSIENT) }
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            message.role.rawValue.withCString { sqlite3_bind_text(stmt, 4, $0, -1, SQLITE_TRANSIENT) }
            message.content.withCString { sqlite3_bind_text(stmt, 5, $0, -1, SQLITE_TRANSIENT) }
            sqlite3_bind_double(stmt, 6, message.createdAt.timeIntervalSince1970)
            sqlite3_step(stmt)
        }
    }

    /// Messages for a workspace, optionally filtered by session. Newest last.
    func messages(workspacePath: String, sessionId: String?) -> [ChatMessage] {
        queue.sync {
            guard let db = self.db else { return [] }
            let sql: String
            let sessionIdParam: String?
            if let sid = sessionId, !sid.isEmpty {
                sql = "SELECT id, workspace_path, session_id, role, content, created_at FROM chat_messages WHERE workspace_path = ? AND session_id = ? ORDER BY created_at ASC;"
                sessionIdParam = sid
            } else {
                sql = "SELECT id, workspace_path, session_id, role, content, created_at FROM chat_messages WHERE workspace_path = ? ORDER BY created_at ASC;"
                sessionIdParam = nil
            }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            workspacePath.withCString { sqlite3_bind_text(stmt, 1, $0, -1, SQLITE_TRANSIENT) }
            if let s = sessionIdParam {
                s.withCString { sqlite3_bind_text(stmt, 2, $0, -1, SQLITE_TRANSIENT) }
            }
            var result: [ChatMessage] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let wp = String(cString: sqlite3_column_text(stmt, 1))
                let sid = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
                let roleStr = String(cString: sqlite3_column_text(stmt, 3))
                let content = String(cString: sqlite3_column_text(stmt, 4))
                let ts = sqlite3_column_double(stmt, 5)
                let role = ChatRole(rawValue: roleStr) ?? .user
                result.append(ChatMessage(id: id, workspacePath: wp, sessionId: sid, role: role, content: content, createdAt: Date(timeIntervalSince1970: ts)))
            }
            return result
        }
    }
}

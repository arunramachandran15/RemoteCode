import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: (@convention(c) (UnsafeMutableRawPointer?) -> Void).self)

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
            conversation_id TEXT NOT NULL DEFAULT '',
            workspace_path TEXT NOT NULL,
            session_id TEXT,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_chat_conversation ON chat_messages(conversation_id);
        CREATE INDEX IF NOT EXISTS idx_chat_workspace_session ON chat_messages(workspace_path, session_id);

        CREATE TABLE IF NOT EXISTS conversations (
            id TEXT PRIMARY KEY,
            workspace_path TEXT NOT NULL,
            session_id TEXT,
            title TEXT NOT NULL DEFAULT '',
            created_at REAL NOT NULL,
            is_read INTEGER NOT NULL DEFAULT 1
        );
        CREATE INDEX IF NOT EXISTS idx_conv_workspace ON conversations(workspace_path);
        """
        var err: UnsafeMutablePointer<CChar>?
        sqlite3_exec(db, sql, nil, nil, &err)
        if let e = err { sqlite3_free(e) }
        migrate()
    }

    private func migrate() {
        var tableInfo: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(chat_messages);", -1, &tableInfo, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(tableInfo) }
        var hasConversationId = false
        while sqlite3_step(tableInfo) == SQLITE_ROW {
            if let name = sqlite3_column_text(tableInfo, 1), String(cString: name) == "conversation_id" {
                hasConversationId = true
                break
            }
        }
        if !hasConversationId {
            var err: UnsafeMutablePointer<CChar>?
            sqlite3_exec(db, "ALTER TABLE chat_messages ADD COLUMN conversation_id TEXT NOT NULL DEFAULT '';", nil, nil, &err)
            if let e = err { sqlite3_free(e) }
        }
    }

    // MARK: - Conversations

    func createConversation(workspacePath: String, sessionId: String?, title: String = "") -> Conversation {
        let conv = Conversation(
            id: UUID().uuidString,
            workspacePath: workspacePath,
            sessionId: sessionId,
            title: title,
            createdAt: Date(),
            isRead: true,
            messageCount: 0,
            lastMessageAt: nil,
            lastMessagePreview: nil
        )
        queue.async { [weak self] in
            guard let db = self?.db else { return }
            let sql = "INSERT OR REPLACE INTO conversations (id, workspace_path, session_id, title, created_at, is_read) VALUES (?, ?, ?, ?, ?, ?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            conv.id.withCString { sqlite3_bind_text(stmt, 1, $0, -1, SQLITE_TRANSIENT) }
            conv.workspacePath.withCString { sqlite3_bind_text(stmt, 2, $0, -1, SQLITE_TRANSIENT) }
            if let s = conv.sessionId {
                s.withCString { sqlite3_bind_text(stmt, 3, $0, -1, SQLITE_TRANSIENT) }
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            conv.title.withCString { sqlite3_bind_text(stmt, 4, $0, -1, SQLITE_TRANSIENT) }
            sqlite3_bind_double(stmt, 5, conv.createdAt.timeIntervalSince1970)
            sqlite3_bind_int(stmt, 6, 1)
            sqlite3_step(stmt)
        }
        return conv
    }

    func updateConversationSession(conversationId: String, sessionId: String) {
        queue.async { [weak self] in
            guard let db = self?.db else { return }
            let sql = "UPDATE conversations SET session_id = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sessionId.withCString { sqlite3_bind_text(stmt, 1, $0, -1, SQLITE_TRANSIENT) }
            conversationId.withCString { sqlite3_bind_text(stmt, 2, $0, -1, SQLITE_TRANSIENT) }
            sqlite3_step(stmt)
        }
    }

    func updateConversationTitle(conversationId: String, title: String) {
        queue.async { [weak self] in
            guard let db = self?.db else { return }
            let sql = "UPDATE conversations SET title = ? WHERE id = ? AND title = '';"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            let truncated = String(title.prefix(60))
            truncated.withCString { sqlite3_bind_text(stmt, 1, $0, -1, SQLITE_TRANSIENT) }
            conversationId.withCString { sqlite3_bind_text(stmt, 2, $0, -1, SQLITE_TRANSIENT) }
            sqlite3_step(stmt)
        }
    }

    func listConversations(workspacePath: String) -> [Conversation] {
        queue.sync {
            guard let db = self.db else { return [] }
            let sql = """
            SELECT c.id, c.workspace_path, c.session_id, c.title, c.created_at, c.is_read,
                   (SELECT COUNT(*) FROM chat_messages m WHERE m.conversation_id = c.id) as msg_count,
                   (SELECT MAX(m.created_at) FROM chat_messages m WHERE m.conversation_id = c.id) as last_msg_at,
                   (SELECT m.content FROM chat_messages m WHERE m.conversation_id = c.id ORDER BY m.created_at DESC LIMIT 1) as last_preview
            FROM conversations c
            WHERE c.workspace_path = ?
            ORDER BY COALESCE(last_msg_at, c.created_at) DESC;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            workspacePath.withCString { sqlite3_bind_text(stmt, 1, $0, -1, SQLITE_TRANSIENT) }
            var result: [Conversation] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let wp = String(cString: sqlite3_column_text(stmt, 1))
                let sid = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
                let title = String(cString: sqlite3_column_text(stmt, 3))
                let ts = sqlite3_column_double(stmt, 4)
                let isRead = sqlite3_column_int(stmt, 5) != 0
                let msgCount = Int(sqlite3_column_int(stmt, 6))
                let lastMsgTs = sqlite3_column_type(stmt, 7) != SQLITE_NULL ? sqlite3_column_double(stmt, 7) : 0
                let lastPreview = sqlite3_column_text(stmt, 8).map { String(cString: $0) }
                result.append(Conversation(
                    id: id, workspacePath: wp, sessionId: sid,
                    title: title, createdAt: Date(timeIntervalSince1970: ts),
                    isRead: isRead, messageCount: msgCount,
                    lastMessageAt: lastMsgTs > 0 ? Date(timeIntervalSince1970: lastMsgTs) : nil,
                    lastMessagePreview: lastPreview
                ))
            }
            return result
        }
    }

    func markConversationRead(conversationId: String) {
        queue.async { [weak self] in
            guard let db = self?.db else { return }
            let sql = "UPDATE conversations SET is_read = 1 WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            conversationId.withCString { sqlite3_bind_text(stmt, 1, $0, -1, SQLITE_TRANSIENT) }
            sqlite3_step(stmt)
        }
    }

    func markConversationUnread(conversationId: String) {
        queue.async { [weak self] in
            guard let db = self?.db else { return }
            let sql = "UPDATE conversations SET is_read = 0 WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            conversationId.withCString { sqlite3_bind_text(stmt, 1, $0, -1, SQLITE_TRANSIENT) }
            sqlite3_step(stmt)
        }
    }

    func deleteConversation(conversationId: String) {
        queue.async { [weak self] in
            guard let db = self?.db else { return }
            var stmt: OpaquePointer?

            let delMsgs = "DELETE FROM chat_messages WHERE conversation_id = ?;"
            guard sqlite3_prepare_v2(db, delMsgs, -1, &stmt, nil) == SQLITE_OK else { return }
            conversationId.withCString { sqlite3_bind_text(stmt, 1, $0, -1, SQLITE_TRANSIENT) }
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)

            let delConv = "DELETE FROM conversations WHERE id = ?;"
            guard sqlite3_prepare_v2(db, delConv, -1, &stmt, nil) == SQLITE_OK else { return }
            conversationId.withCString { sqlite3_bind_text(stmt, 1, $0, -1, SQLITE_TRANSIENT) }
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func conversationForSession(workspacePath: String, sessionId: String?) -> Conversation? {
        queue.sync {
            guard let db = self.db else { return nil }
            let sql: String
            if let _ = sessionId {
                sql = "SELECT id, workspace_path, session_id, title, created_at, is_read FROM conversations WHERE workspace_path = ? AND session_id = ? LIMIT 1;"
            } else {
                sql = "SELECT id, workspace_path, session_id, title, created_at, is_read FROM conversations WHERE workspace_path = ? AND session_id IS NULL LIMIT 1;"
            }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            workspacePath.withCString { sqlite3_bind_text(stmt, 1, $0, -1, SQLITE_TRANSIENT) }
            if let s = sessionId {
                s.withCString { sqlite3_bind_text(stmt, 2, $0, -1, SQLITE_TRANSIENT) }
            }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let wp = String(cString: sqlite3_column_text(stmt, 1))
            let sid = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            let title = String(cString: sqlite3_column_text(stmt, 3))
            let ts = sqlite3_column_double(stmt, 4)
            let isRead = sqlite3_column_int(stmt, 5) != 0
            return Conversation(id: id, workspacePath: wp, sessionId: sid, title: title,
                                createdAt: Date(timeIntervalSince1970: ts), isRead: isRead,
                                messageCount: 0, lastMessageAt: nil, lastMessagePreview: nil)
        }
    }

    // MARK: - Messages

    func insert(_ message: ChatMessage) {
        queue.async { [weak self] in
            guard let db = self?.db else { return }
            let sql = "INSERT OR REPLACE INTO chat_messages (id, conversation_id, workspace_path, session_id, role, content, created_at) VALUES (?, ?, ?, ?, ?, ?, ?);"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            message.id.withCString { sqlite3_bind_text(stmt, 1, $0, -1, SQLITE_TRANSIENT) }
            message.conversationId.withCString { sqlite3_bind_text(stmt, 2, $0, -1, SQLITE_TRANSIENT) }
            message.workspacePath.withCString { sqlite3_bind_text(stmt, 3, $0, -1, SQLITE_TRANSIENT) }
            if let s = message.sessionId {
                s.withCString { sqlite3_bind_text(stmt, 4, $0, -1, SQLITE_TRANSIENT) }
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            message.role.rawValue.withCString { sqlite3_bind_text(stmt, 5, $0, -1, SQLITE_TRANSIENT) }
            message.content.withCString { sqlite3_bind_text(stmt, 6, $0, -1, SQLITE_TRANSIENT) }
            sqlite3_bind_double(stmt, 7, message.createdAt.timeIntervalSince1970)
            sqlite3_step(stmt)
        }
    }

    func messages(conversationId: String, limit: Int = 50, beforeDate: Date? = nil) -> [ChatMessage] {
        queue.sync {
            guard let db = self.db else { return [] }
            let sql: String
            if beforeDate != nil {
                sql = "SELECT id, conversation_id, workspace_path, session_id, role, content, created_at FROM chat_messages WHERE conversation_id = ? AND created_at < ? ORDER BY created_at DESC LIMIT ?;"
            } else {
                sql = "SELECT id, conversation_id, workspace_path, session_id, role, content, created_at FROM chat_messages WHERE conversation_id = ? ORDER BY created_at DESC LIMIT ?;"
            }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            var paramIdx: Int32 = 1
            conversationId.withCString { sqlite3_bind_text(stmt, paramIdx, $0, -1, SQLITE_TRANSIENT) }
            paramIdx += 1
            if let bd = beforeDate {
                sqlite3_bind_double(stmt, paramIdx, bd.timeIntervalSince1970)
                paramIdx += 1
            }
            sqlite3_bind_int(stmt, paramIdx, Int32(limit))
            var result: [ChatMessage] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let convId = String(cString: sqlite3_column_text(stmt, 1))
                let wp = String(cString: sqlite3_column_text(stmt, 2))
                let sid = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
                let roleStr = String(cString: sqlite3_column_text(stmt, 4))
                let content = String(cString: sqlite3_column_text(stmt, 5))
                let ts = sqlite3_column_double(stmt, 6)
                let role = ChatRole(rawValue: roleStr) ?? .user
                result.append(ChatMessage(id: id, conversationId: convId, workspacePath: wp, sessionId: sid, role: role, content: content, createdAt: Date(timeIntervalSince1970: ts)))
            }
            return result.reversed()
        }
    }

    func messageCount(conversationId: String) -> Int {
        queue.sync {
            guard let db = self.db else { return 0 }
            let sql = "SELECT COUNT(*) FROM chat_messages WHERE conversation_id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }
            conversationId.withCString { sqlite3_bind_text(stmt, 1, $0, -1, SQLITE_TRANSIENT) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(stmt, 0))
        }
    }
}

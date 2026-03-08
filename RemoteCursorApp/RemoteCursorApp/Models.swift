import Foundation

enum ConnectionMode: String, CaseIterable {
    case peer = "Find Mac (Bluetooth / Wi‑Fi)"
    case wifi = "Wi‑Fi (URL)"
}

struct RepoItem: Identifiable, Hashable {
    let id: String
    let path: String
    var displayName: String { (path as NSString).lastPathComponent }
}

struct AgentResponse {
    var output: String?
    var error: String?
    var sessionId: String?
}

enum ChatRole: String, Codable {
    case user
    case assistant
}

struct ChatMessage: Identifiable {
    let id: String
    let conversationId: String
    let workspacePath: String
    let sessionId: String?
    let role: ChatRole
    let content: String
    let createdAt: Date

    var isImageMessage: Bool {
        content.hasPrefix("[Image: ") || content.contains("📷")
    }
}

struct Conversation: Identifiable, Hashable {
    let id: String
    let workspacePath: String
    let sessionId: String?
    var title: String
    let createdAt: Date
    var isRead: Bool
    var messageCount: Int
    var lastMessageAt: Date?
    var lastMessagePreview: String?

    var displayTitle: String {
        title.isEmpty ? "New Chat" : title
    }
}

struct CommandResult {
    var stdout: String?
    var stderr: String?
    var exitCode: Int
}

struct FileItem: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int?

    var iconName: String {
        if isDirectory { return "folder.fill" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "ts", "jsx", "tsx": return "doc.text"
        case "json", "plist", "xml", "yaml", "yml": return "doc.badge.gearshape"
        case "md", "txt", "rtf": return "doc.plaintext"
        case "png", "jpg", "jpeg", "gif", "svg", "webp": return "photo"
        default: return "doc"
        }
    }
}

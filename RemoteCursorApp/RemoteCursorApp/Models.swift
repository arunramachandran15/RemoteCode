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
    let workspacePath: String
    let sessionId: String?
    let role: ChatRole
    let content: String
    let createdAt: Date
}

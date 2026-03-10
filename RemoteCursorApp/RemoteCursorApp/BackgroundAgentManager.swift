import Foundation
import Combine

extension Notification.Name {
    static let backgroundAgentTaskCompleted = Notification.Name("backgroundAgentTaskCompleted")
}

final class BackgroundAgentManager: ObservableObject {
    static let shared = BackgroundAgentManager()

    @Published var runningConversations: Set<String> = []

    /// Accumulated streaming text per conversation — polled by ChatDetailView's timer.
    private(set) var streamingContent: [String: String] = [:]

    private var tasks: [String: Task<Void, Never>] = [:]

    private init() {}

    struct AgentRequest {
        let conversationId: String
        let workspacePath: String
        let message: String
        let sessionId: String?
        let connectionMode: ConnectionMode
        let wifiURL: String
        let peer: PeerClient
    }

    func submit(_ request: AgentRequest) {
        let convId = request.conversationId

        runningConversations.insert(convId)
        streamingContent[convId] = ""

        let connMode = request.connectionMode
        let wifiURL = request.wifiURL
        let workspace = request.workspacePath
        let message = request.message
        let sid = request.sessionId
        let peer = request.peer

        tasks[convId] = Task { [weak self] in
            do {
                let res: AgentResponse
                if connMode == .wifi {
                    let client = HTTPClient(baseURL: wifiURL.trimmingCharacters(in: .whitespaces))
                    res = try await client.runAgentStreaming(
                        workspace: workspace,
                        message: message,
                        sessionId: sid
                    ) { delta in
                        Task { @MainActor [weak self] in
                            self?.streamingContent[convId, default: ""] += delta
                        }
                    }
                } else {
                    res = try await peer.runAgentStreaming(
                        workspace: workspace,
                        message: message,
                        sessionId: sid
                    ) { delta in
                        Task { @MainActor [weak self] in
                            self?.streamingContent[convId, default: ""] += delta
                        }
                    }
                }

                await MainActor.run { [weak self] in
                    self?.handleCompletion(
                        conversationId: convId,
                        workspacePath: workspace,
                        requestSessionId: sid,
                        response: res
                    )
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.handleError(
                        conversationId: convId,
                        workspacePath: workspace,
                        sessionId: sid,
                        error: error
                    )
                }
            }
        }
    }

    func isRunning(_ conversationId: String) -> Bool {
        runningConversations.contains(conversationId)
    }

    func getStreamingContent(_ conversationId: String) -> String {
        streamingContent[conversationId] ?? ""
    }

    func cancel(_ conversationId: String) {
        tasks[conversationId]?.cancel()
        cleanup(conversationId)
    }

    // MARK: - Private

    private func cleanup(_ conversationId: String) {
        runningConversations.remove(conversationId)
        streamingContent.removeValue(forKey: conversationId)
        tasks.removeValue(forKey: conversationId)
    }

    private func handleCompletion(
        conversationId: String,
        workspacePath: String,
        requestSessionId: String?,
        response: AgentResponse
    ) {
        if let newSid = response.sessionId {
            updateSessionId(workspace: workspacePath, sessionId: newSid)
        }

        let content = (response.output ?? "") + (response.error.map { "\n\nError: \($0)" } ?? "")

        if !content.isEmpty {
            let msg = ChatMessage(
                id: UUID().uuidString,
                conversationId: conversationId,
                workspacePath: workspacePath,
                sessionId: response.sessionId ?? requestSessionId,
                role: .assistant,
                content: content,
                createdAt: Date()
            )
            ChatStore.shared.insert(msg)
        }

        ChatStore.shared.markConversationUnread(conversationId: conversationId)
        cleanup(conversationId)

        NotificationCenter.default.post(
            name: .backgroundAgentTaskCompleted,
            object: nil,
            userInfo: [
                "conversationId": conversationId,
                "workspacePath": workspacePath,
                "sessionId": response.sessionId as Any,
                "responseError": response.error as Any
            ]
        )
    }

    private func handleError(
        conversationId: String,
        workspacePath: String,
        sessionId: String?,
        error: Error
    ) {
        let errMsg = ChatMessage(
            id: UUID().uuidString,
            conversationId: conversationId,
            workspacePath: workspacePath,
            sessionId: sessionId,
            role: .assistant,
            content: "Error: \(error.localizedDescription)",
            createdAt: Date()
        )
        ChatStore.shared.insert(errMsg)
        ChatStore.shared.markConversationUnread(conversationId: conversationId)
        cleanup(conversationId)

        NotificationCenter.default.post(
            name: .backgroundAgentTaskCompleted,
            object: nil,
            userInfo: [
                "conversationId": conversationId,
                "workspacePath": workspacePath,
                "error": error.localizedDescription
            ]
        )
    }

    private func updateSessionId(workspace: String, sessionId: String) {
        let key = "agent_sessions"
        let raw = UserDefaults.standard.string(forKey: key) ?? "{}"
        var dict = (try? JSONDecoder().decode([String: String].self, from: Data(raw.utf8))) ?? [:]
        dict[workspace] = sessionId
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        if let data = try? enc.encode(dict), let s = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: key)
        }
    }
}

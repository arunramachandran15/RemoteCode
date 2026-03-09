import SwiftUI
import Combine

private let sessionStorageKey = "agent_sessions"
private let pageSize = 50

// MARK: - Timestamp Formatting

private func chatTimestamp(_ date: Date) -> String {
    let cal = Calendar.current
    let now = Date()
    let diff = now.timeIntervalSince(date)
    if diff < 60 { return "Just now" }
    if diff < 3600 { return "\(Int(diff / 60))m ago" }
    if cal.isDateInToday(date) {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        return fmt.string(from: date)
    }
    if cal.isDateInYesterday(date) {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        return "Yesterday, \(fmt.string(from: date))"
    }
    if diff < 7 * 86400 {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, h:mm a"
        return fmt.string(from: date)
    }
    let fmt = DateFormatter()
    fmt.dateFormat = "MMM d, yyyy"
    return fmt.string(from: date)
}

private func messageDateHeader(_ date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return "Today" }
    if cal.isDateInYesterday(date) { return "Yesterday" }
    let fmt = DateFormatter()
    fmt.dateFormat = "EEEE, MMM d, yyyy"
    return fmt.string(from: date)
}

private func messageTime(_ date: Date) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "h:mm a"
    return fmt.string(from: date)
}

// MARK: - Confirm Action

private enum ConfirmAction: Identifiable {
    case deleteConversation(Conversation)
    case deleteAllChats(repoPath: String)
    case removeRepo(path: String)
    case resetSession(path: String)

    var id: String {
        switch self {
        case .deleteConversation(let c): return "delConv-\(c.id)"
        case .deleteAllChats(let p): return "delAll-\(p)"
        case .removeRepo(let p): return "removeRepo-\(p)"
        case .resetSession(let p): return "resetSess-\(p)"
        }
    }

    var title: String {
        switch self {
        case .deleteConversation: return "Delete Conversation"
        case .deleteAllChats: return "Delete All Chats"
        case .removeRepo: return "Remove Repository"
        case .resetSession: return "Reset Agent Session"
        }
    }

    var message: String {
        switch self {
        case .deleteConversation: return "This conversation and all its messages will be permanently deleted."
        case .deleteAllChats: return "All conversations and messages for this repository will be permanently deleted."
        case .removeRepo: return "This will remove the repository from your list and delete all its conversations and messages."
        case .resetSession: return "This will clear the agent session. A new session will start on the next message. Existing chats are kept."
        }
    }

    var buttonLabel: String {
        switch self {
        case .deleteConversation: return "Delete"
        case .deleteAllChats: return "Delete All"
        case .removeRepo: return "Remove"
        case .resetSession: return "Reset"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .resetSession: return false
        default: return true
        }
    }
}

// MARK: - AgentView (Conversation List)

struct AgentView: View {
    @ObservedObject var peer: PeerClient
    let wifiURL: String
    let connectionMode: ConnectionMode?
    var onConnectionLost: (() -> Void)?
    @Binding var externalMessage: String
    @State private var repos: [RepoItem] = []
    @State private var selectedRepo: RepoItem?
    @State private var savedWorkspaces: [ChatStore.WorkspaceSummary] = []
    @State private var conversations: [Conversation] = []
    @State private var activeConversation: Conversation?
    @State private var showChatDetail = false
    @State private var showRepoBrowser = false
    @State private var loadError: String?
    @State private var initialLoad = true
    @State private var loading = false
    @State private var confirmAction: ConfirmAction?
    @State private var showConfirm = false
    @AppStorage(sessionStorageKey) private var sessionStorageData = "{}"
    @AppStorage("lastSelectedRepo") private var lastSelectedRepoPath = ""

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
            if let repo = selectedRepo {
                Section {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(repo.displayName)
                                .font(.headline)
                            Text(repo.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Change") {
                            showRepoBrowser = true
                        }
                        .font(.subheadline)
                    }
                } header: {
                    Text("Current Repository")
                }
            }

            if !savedWorkspaces.isEmpty {
                Section {
                    ForEach(savedWorkspaces, id: \.path) { ws in
                        Button {
                            selectedRepo = RepoItem(id: ws.path, path: ws.path)
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(ws.path == selectedRepo?.path ? .blue : .orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ws.displayName)
                                        .font(.subheadline)
                                        .fontWeight(ws.path == selectedRepo?.path ? .semibold : .regular)
                                        .foregroundStyle(.primary)
                                    Text(ws.path)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(ws.conversationCount)")
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.15))
                                        .clipShape(Capsule())
                                    Text(chatTimestamp(ws.lastActivity))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if ws.path == selectedRepo?.path {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                askConfirm(.removeRepo(path: ws.path))
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            Button {
                                askConfirm(.resetSession(path: ws.path))
                            } label: {
                                Label("Reset Session", systemImage: "arrow.counterclockwise")
                            }
                            .tint(.orange)
                        }
                    }
                } header: {
                    Text("Your Repositories")
                } footer: {
                    Text("Swipe left on a repo to remove it or reset its agent session.")
                        .font(.caption2)
                }
            }

            Section {
                Button {
                    showRepoBrowser = true
                } label: {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text(selectedRepo == nil ? "Browse & Select Repository" : "Add New Repository")
                    }
                }
                if let err = loadError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }

            if selectedRepo != nil {
                Section {
                    if conversations.isEmpty && !loading {
                        Text("No conversations yet")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(conversations) { conv in
                            Button {
                                openConversation(conv)
                            } label: {
                                conversationRow(conv)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    askConfirm(.deleteConversation(conv))
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    toggleRead(conv)
                                } label: {
                                    Label(conv.isRead ? "Unread" : "Read",
                                          systemImage: conv.isRead ? "envelope.badge" : "envelope.open")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Conversations")
                        Spacer()
                        Text("\(conversations.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Agent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let repo = selectedRepo {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            startNewChat()
                        } label: {
                            Label("New Chat", systemImage: "square.and.pencil")
                        }
                        Divider()
                        Button {
                            askConfirm(.resetSession(path: repo.path))
                        } label: {
                            Label("Reset Agent Session", systemImage: "arrow.counterclockwise")
                        }
                        Button(role: .destructive) {
                            askConfirm(.deleteAllChats(repoPath: repo.path))
                        } label: {
                            Label("Delete All Chats", systemImage: "trash")
                        }
                        Button(role: .destructive) {
                            askConfirm(.removeRepo(path: repo.path))
                        } label: {
                            Label("Remove Repository", systemImage: "folder.badge.minus")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear {
            if initialLoad {
                initialLoad = false
                loadSavedWorkspaces()
                loadRepos()
            }
            reloadConversations()
        }
        .onChange(of: selectedRepo?.path) { newPath in
            if let p = newPath { lastSelectedRepoPath = p }
            reloadConversations()
        }
        .onChange(of: externalMessage) { newValue in
            if !newValue.isEmpty {
                let msg = newValue
                externalMessage = ""
                openOrCreateConversationWithMessage(msg)
            }
        }
        .sheet(isPresented: $showRepoBrowser) {
            FolderBrowserSheet(
                peer: peer,
                wifiURL: wifiURL,
                connectionMode: connectionMode,
                onSelect: { path in
                    let repo = RepoItem(id: path, path: path)
                    selectedRepo = repo
                    if !repos.contains(where: { $0.path == path }) {
                        repos.insert(repo, at: 0)
                    }
                    showRepoBrowser = false
                },
                configRepos: repos
            )
        }
        .alert(
            confirmAction?.title ?? "",
            isPresented: $showConfirm,
            presenting: confirmAction
        ) { action in
            Button(action.buttonLabel, role: action.isDestructive ? .destructive : nil) {
                executeConfirm(action)
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(action.message)
        }
        .fullScreenCover(isPresented: $showChatDetail) {
            if let conv = activeConversation, let repo = selectedRepo {
                NavigationStack {
                    ChatDetailView(
                        peer: peer,
                        wifiURL: wifiURL,
                        connectionMode: connectionMode,
                        repo: repo,
                        conversation: conv,
                        repoSessionId: getSessionId(workspace: repo.path),
                        onConnectionLost: onConnectionLost,
                        onSessionUpdated: { newSid in
                            setSessionId(workspace: repo.path, value: newSid)
                            reloadConversations()
                        },
                        onDismiss: {
                            showChatDetail = false
                            reloadConversations()
                            loadSavedWorkspaces()
                        }
                    )
                }
            }
        }
    }

    private func conversationRow(_ conv: Conversation) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if !conv.isRead {
                Circle()
                    .fill(.blue)
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conv.displayTitle)
                        .font(.headline)
                        .fontWeight(conv.isRead ? .regular : .bold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(chatTimestamp(conv.lastMessageAt ?? conv.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let preview = conv.lastMessagePreview, !preview.isEmpty {
                    Text(preview.replacingOccurrences(of: "\n", with: " "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.caption2)
                    Text("\(conv.messageCount)")
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func openConversation(_ conv: Conversation) {
        activeConversation = conv
        ChatStore.shared.markConversationRead(conversationId: conv.id)
        showChatDetail = true
    }

    private func startNewChat() {
        guard let repo = selectedRepo else { return }
        let existingSessionId = getSessionId(workspace: repo.path)
        let conv = ChatStore.shared.createConversation(workspacePath: repo.path, sessionId: existingSessionId, title: "")
        activeConversation = conv
        showChatDetail = true
        reloadConversations()
    }

    private func openOrCreateConversationWithMessage(_ msg: String) {
        guard let repo = selectedRepo else { return }
        let conv = ChatStore.shared.createConversation(workspacePath: repo.path, sessionId: getSessionId(workspace: repo.path), title: "")
        activeConversation = conv
        showChatDetail = true
    }

    private func deleteConversation(_ conv: Conversation) {
        ChatStore.shared.deleteConversation(conversationId: conv.id)
        reloadConversations()
        loadSavedWorkspaces()
    }

    private func askConfirm(_ action: ConfirmAction) {
        confirmAction = action
        showConfirm = true
    }

    private func executeConfirm(_ action: ConfirmAction) {
        switch action {
        case .deleteConversation(let conv):
            deleteConversation(conv)
        case .deleteAllChats(let path):
            deleteAllChats(path)
        case .removeRepo(let path):
            removeRepo(path)
        case .resetSession(let path):
            clearSession(path)
        }
    }

    private func deleteAllChats(_ repoPath: String? = nil) {
        let path = repoPath ?? selectedRepo?.path
        guard let p = path else { return }
        ChatStore.shared.deleteAllForWorkspace(workspacePath: p)
        if selectedRepo?.path == p { conversations = [] }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            loadSavedWorkspaces()
        }
    }

    private func removeRepo(_ path: String) {
        ChatStore.shared.deleteAllForWorkspace(workspacePath: path)
        setSessionId(workspace: path, value: nil)
        if selectedRepo?.path == path {
            selectedRepo = nil
            conversations = []
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            loadSavedWorkspaces()
        }
    }

    private func clearSession(_ path: String) {
        setSessionId(workspace: path, value: nil)
        if selectedRepo?.path == path {
            reloadConversations()
        }
    }

    private func toggleRead(_ conv: Conversation) {
        if conv.isRead {
            ChatStore.shared.markConversationUnread(conversationId: conv.id)
        } else {
            ChatStore.shared.markConversationRead(conversationId: conv.id)
        }
        reloadConversations()
    }

    private func reloadConversations() {
        guard let repo = selectedRepo else { conversations = []; return }
        conversations = ChatStore.shared.listConversations(workspacePath: repo.path)
    }

    private func loadSavedWorkspaces() {
        savedWorkspaces = ChatStore.shared.distinctWorkspaces()
        if selectedRepo == nil, !lastSelectedRepoPath.isEmpty {
            if savedWorkspaces.contains(where: { $0.path == lastSelectedRepoPath }) {
                selectedRepo = RepoItem(id: lastSelectedRepoPath, path: lastSelectedRepoPath)
            } else if let first = savedWorkspaces.first {
                selectedRepo = RepoItem(id: first.path, path: first.path)
            }
        }
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
                    if selectedRepo == nil {
                        if let saved = repos.first(where: { $0.path == lastSelectedRepoPath }) {
                            selectedRepo = saved
                        } else if !savedWorkspaces.isEmpty, let first = savedWorkspaces.first {
                            selectedRepo = RepoItem(id: first.path, path: first.path)
                        } else if let first = repos.first {
                            selectedRepo = first
                        }
                    }
                    loading = false
                    reloadConversations()
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
}

// MARK: - Chat Item (Flat list for performant LazyVStack)

private enum ChatItem: Identifiable {
    case dateSeparator(date: Date, dayKey: String)
    case message(ChatMessage)

    var id: String {
        switch self {
        case .dateSeparator(_, let key): return "sep-\(key)"
        case .message(let msg): return msg.id
        }
    }
}

// MARK: - Folder Browser Sheet

struct FolderBrowserSheet: View {
    @ObservedObject var peer: PeerClient
    let wifiURL: String
    let connectionMode: ConnectionMode?
    let onSelect: (String) -> Void
    let configRepos: [RepoItem]
    @Environment(\.dismiss) private var dismiss

    private static let staticRoots: [(String, String, String)] = [
        ("/Volumes", "Volumes", "externaldrive.fill"),
        ("/Users", "Users", "person.2.fill"),
        ("/", "Root", "internaldrive.fill"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Starting Points") {
                    ForEach(Self.staticRoots, id: \.0) { path, label, icon in
                        NavigationLink {
                            FolderListView(
                                peer: peer,
                                wifiURL: wifiURL,
                                connectionMode: connectionMode,
                                dirPath: path,
                                title: label,
                                onSelect: onSelect
                            )
                        } label: {
                            Label(label, systemImage: icon)
                        }
                    }
                }

                if !configRepos.isEmpty {
                    Section("Folders from Mac") {
                        ForEach(configRepos) { r in
                            NavigationLink {
                                FolderListView(
                                    peer: peer,
                                    wifiURL: wifiURL,
                                    connectionMode: connectionMode,
                                    dirPath: r.path,
                                    title: r.displayName,
                                    onSelect: onSelect
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.displayName)
                                    Text(r.path)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }

                Section("Enter Path Manually") {
                    ManualPathEntry(onSelect: onSelect)
                }
            }
            .navigationTitle("Choose Repository")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct ManualPathEntry: View {
    let onSelect: (String) -> Void
    @State private var manualPath = ""

    var body: some View {
        HStack {
            TextField("/path/to/repo", text: $manualPath)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Go") {
                let p = manualPath.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !p.isEmpty else { return }
                onSelect(p)
            }
            .disabled(manualPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

private struct FolderListView: View {
    @ObservedObject var peer: PeerClient
    let wifiURL: String
    let connectionMode: ConnectionMode?
    let dirPath: String
    let title: String
    let onSelect: (String) -> Void
    @State private var items: [FileItem] = []
    @State private var loading = true
    @State private var errorMsg: String?
    @State private var trustStatus: String?
    @State private var trusting = false

    var body: some View {
        Group {
            if loading {
                ProgressView("Loading...")
            } else if let err = errorMsg {
                VStack(spacing: 12) {
                    Text(err).foregroundStyle(.red).font(.caption)
                    Button("Retry") { loadFolder() }
                }
                .padding()
            } else if items.isEmpty {
                Text("Empty folder").foregroundStyle(.secondary).padding()
            } else {
                List {
                    if let status = trustStatus {
                        Section {
                            Label(status, systemImage: "checkmark.shield")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    ForEach(items.filter { $0.isDirectory }.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })) { item in
                        NavigationLink {
                            FolderListView(
                                peer: peer,
                                wifiURL: wifiURL,
                                connectionMode: connectionMode,
                                dirPath: item.path,
                                title: item.name,
                                onSelect: onSelect
                            )
                        } label: {
                            Label(item.name, systemImage: "folder.fill")
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        onSelect(dirPath)
                    } label: {
                        Label("Select as Repository", systemImage: "checkmark.circle")
                    }
                    Button {
                        trustAndSelect()
                    } label: {
                        Label("Trust & Select", systemImage: "checkmark.shield")
                    }
                    Button {
                        trustFolder()
                    } label: {
                        Label("Trust Only", systemImage: "shield")
                    }
                } label: {
                    if trusting {
                        ProgressView()
                    } else {
                        Text("Select")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .onAppear { loadFolder() }
    }

    private func trustFolder() {
        trusting = true
        Task {
            do {
                let result: (ok: Bool, message: String)
                if connectionMode == .wifi {
                    result = try await HTTPClient(baseURL: wifiURL.trimmingCharacters(in: .whitespaces))
                        .trustWorkspace(dirPath)
                } else {
                    result = try await peer.trustWorkspace(dirPath)
                }
                await MainActor.run {
                    trusting = false
                    trustStatus = result.ok ? "Trusted — approve dialog on Mac" : result.message
                }
            } catch {
                await MainActor.run {
                    trusting = false
                    trustStatus = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func trustAndSelect() {
        trusting = true
        Task {
            do {
                if connectionMode == .wifi {
                    _ = try await HTTPClient(baseURL: wifiURL.trimmingCharacters(in: .whitespaces))
                        .trustWorkspace(dirPath)
                } else {
                    _ = try await peer.trustWorkspace(dirPath)
                }
                await MainActor.run {
                    trusting = false
                    onSelect(dirPath)
                }
            } catch {
                await MainActor.run {
                    trusting = false
                    onSelect(dirPath)
                }
            }
        }
    }

    private func loadFolder() {
        loading = true
        errorMsg = nil
        Task {
            do {
                let result: [FileItem]
                if connectionMode == .wifi {
                    result = try await HTTPClient(baseURL: wifiURL.trimmingCharacters(in: .whitespaces))
                        .listFiles(path: dirPath)
                } else {
                    result = try await peer.listFiles(path: dirPath)
                }
                await MainActor.run {
                    items = result
                    loading = false
                }
            } catch {
                await MainActor.run {
                    errorMsg = error.localizedDescription
                    loading = false
                }
            }
        }
    }
}

// MARK: - Chat Detail View

struct ChatDetailView: View {
    @ObservedObject var peer: PeerClient
    let wifiURL: String
    let connectionMode: ConnectionMode?
    let repo: RepoItem
    let conversation: Conversation
    let repoSessionId: String?
    var onConnectionLost: (() -> Void)?
    var onSessionUpdated: ((String) -> Void)?
    var onDismiss: () -> Void

    @State private var chatMessages: [ChatMessage] = []
    @State private var flatItems: [ChatItem] = []
    @State private var message = ""
    @State private var streamingContent = ""
    @State private var loading = false
    @State private var hasMoreMessages = false
    @State private var loadingMore = false
    @State private var sessionId: String?

    @State private var runningCommand: String?
    @State private var commandResult: CommandResult?
    @State private var showCommandResult = false

    @State private var showVoiceOverlay = false
    @StateObject private var speech = SpeechRecognizer()

    @State private var showImagePicker = false
    @State private var imagePickerSource: ImagePicker.Source = .photoLibrary
    @State private var showImageSourcePicker = false
    @State private var pendingImageData: Data?
    @State private var uploadingImage = false
    @State private var imageUploadError: String?

    @State private var loadingMessages = true
    @State private var isNearBottom = true
    @State private var streamingBuffer = ""
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showTrustAlert = false
    @State private var trustMessage = ""
    @State private var trustingWorkspace = false

    private let haptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if loadingMessages {
                                ProgressView("Loading messages…")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 40)
                            }

                            if !loadingMessages && hasMoreMessages {
                                Button {
                                    loadEarlierMessages()
                                } label: {
                                    HStack {
                                        if loadingMore { ProgressView() }
                                        Text(loadingMore ? "Loading…" : "Load earlier messages")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                }
                                .id("loadMore")
                            }

                            ForEach(flatItems) { item in
                                switch item {
                                case .dateSeparator(let date, _):
                                    dateSeparator(date)
                                case .message(let msg):
                                    messageBubble(msg)
                                }
                            }

                            if !streamingContent.isEmpty {
                                streamingBubble
                                    .id("streaming")
                            }

                            if loading && streamingContent.isEmpty {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text(runningCommand != nil ? "Running command…" : "Agent thinking…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .id("loading")
                            }

                            Color.clear
                                .frame(height: 60)
                                .id("bottom")
                                .onAppear { withAnimation(.none) { isNearBottom = true } }
                                .onDisappear { withAnimation(.none) { isNearBottom = false } }
                        }
                        .padding(.horizontal, 12)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onReceive(Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()) { _ in
                        guard !streamingBuffer.isEmpty else { return }
                        streamingContent += streamingBuffer
                        streamingBuffer = ""
                        if isNearBottom {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: flatItems.count) { _ in
                        if isNearBottom {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: loadingMessages) { newValue in
                        if !newValue {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                    .onAppear { scrollProxy = proxy }
                }

                if !isNearBottom {
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) {
                            scrollProxy?.scrollTo("bottom", anchor: .bottom)
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white, Color.accentColor)
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }

            Divider()
            inputBar
        }
        .animation(.easeInOut(duration: 0.2), value: isNearBottom)
        .navigationTitle(conversation.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { onDismiss() }
            }
        }
        .onAppear {
            sessionId = repoSessionId
            loadMessagesAsync()
        }
        .sheet(isPresented: $showCommandResult) {
            commandResultSheet
        }
        .sheet(isPresented: $showVoiceOverlay, onDismiss: {
            speech.stopRecording()
        }) {
            voiceOverlay
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(source: imagePickerSource) { data in
                if !data.isEmpty {
                    pendingImageData = data
                }
                showImagePicker = false
            }
        }
        .confirmationDialog("Attach Image", isPresented: $showImageSourcePicker) {
            Button("Take Photo") {
                imagePickerSource = .camera
                showImagePicker = true
            }
            Button("Choose from Library") {
                imagePickerSource = .photoLibrary
                showImagePicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Image Upload Failed", isPresented: Binding(
            get: { imageUploadError != nil },
            set: { if !$0 { imageUploadError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(imageUploadError ?? "")
        }
        .alert("Workspace Trust Required", isPresented: $showTrustAlert) {
            Button("Trust This Folder") {
                trustCurrentWorkspace()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This folder needs to be trusted in Cursor before the agent can work with it. Tap 'Trust This Folder' to open it in Cursor on your Mac, then approve the trust dialog.")
        }
        .overlay {
            if trustingWorkspace {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Opening folder in Cursor on Mac...")
                        .font(.subheadline)
                    Text("Please approve the trust dialog on your Mac, then try sending your message again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding()
            }
        }
    }

    private func trustCurrentWorkspace() {
        trustingWorkspace = true
        Task {
            do {
                let result: (ok: Bool, message: String)
                if connectionMode == .wifi {
                    result = try await HTTPClient(baseURL: wifiURL.trimmingCharacters(in: .whitespaces))
                        .trustWorkspace(repo.path)
                } else {
                    result = try await peer.trustWorkspace(repo.path)
                }
                await MainActor.run {
                    trustingWorkspace = false
                    trustMessage = result.message
                }
            } catch {
                await MainActor.run {
                    trustingWorkspace = false
                    trustMessage = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Flat Item Builder

    private func rebuildFlatItems() {
        let cal = Calendar.current
        var items: [ChatItem] = []
        var lastDay: DateComponents?
        for msg in chatMessages {
            let day = cal.dateComponents([.year, .month, .day], from: msg.createdAt)
            if day != lastDay {
                let key = "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
                items.append(.dateSeparator(date: msg.createdAt, dayKey: key))
                lastDay = day
            }
            items.append(.message(msg))
        }
        flatItems = items
    }

    // MARK: - Views

    private func dateSeparator(_ date: Date) -> some View {
        HStack {
            VStack { Divider() }
            Text(messageDateHeader(date))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize()
            VStack { Divider() }
        }
        .padding(.vertical, 8)
    }

    private func messageBubble(_ msg: ChatMessage) -> some View {
        let isUser = msg.role == .user
        return HStack(alignment: .bottom, spacing: 6) {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
                if isUser {
                    Text(msg.content)
                        .textSelection(.enabled)
                        .padding(10)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(16)
                } else {
                    MarkdownView(content: msg.content, onRunCommand: { cmd in
                        executeCommand(cmd)
                    })
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                }
                HStack(spacing: 4) {
                    Text(messageTime(msg.createdAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    if isUser {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            if !isUser { Spacer(minLength: 40) }
        }
        .padding(.vertical, 2)
        .id(msg.id)
    }

    private var streamingBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                MarkdownView(content: streamingContent, onRunCommand: { _ in })
                    .padding(10)
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
            }
            Spacer(minLength: 40)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            if uploadingImage {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Uploading image…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if let imgData = pendingImageData, let uiImage = UIImage(data: imgData) {
                HStack(alignment: .top, spacing: 8) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .cornerRadius(10)
                        .clipped()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Photo attached")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("Tap send to upload & ask agent")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        pendingImageData = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    showImageSourcePicker = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
                .disabled(loading || uploadingImage)

                TextField("Message…", text: $message, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)

                Button {
                    showVoiceOverlay = true
                    speech.startRecording()
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }

                Button {
                    if pendingImageData != nil {
                        sendMessageWithImage()
                    } else {
                        sendMessage()
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            (message.trimmingCharacters(in: .whitespaces).isEmpty && pendingImageData == nil) || loading
                                ? Color.gray : Color.accentColor
                        )
                }
                .disabled((message.trimmingCharacters(in: .whitespaces).isEmpty && pendingImageData == nil) || loading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    // MARK: - Voice Overlay

    @ViewBuilder
    private var voiceOverlay: some View {
        let isReview = !speech.isRecording && !speech.transcript.isEmpty
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                if speech.isRecording {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.red)
                        .opacity(0.6)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: speech.isRecording)
                    Text("Listening…")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                } else if isReview {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                    Text("Review Transcript")
                        .font(.headline)
                } else {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(Color.accentColor)
                    Text("Tap mic to start")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    if isReview {
                        Text("Your transcribed text:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                    ScrollView {
                        Text(speech.transcript.isEmpty ? "Say something…" : speech.transcript)
                            .font(isReview ? .body : .callout)
                            .foregroundStyle(speech.transcript.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .frame(maxHeight: isReview ? 250 : 160)
                    .background(isReview ? Color(.systemGray5) : Color(.systemGray6))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isReview ? Color.green.opacity(0.5) : Color.clear, lineWidth: 2)
                    )
                    .padding(.horizontal)
                }

                Spacer()

                VStack(spacing: 12) {
                    if isReview {
                        Button {
                            let text = speech.transcript
                            speech.stopRecording()
                            message += (message.isEmpty ? "" : " ") + text
                            showVoiceOverlay = false
                        } label: {
                            Label("Use Text", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            speech.startRecording()
                        } label: {
                            Label("Re-record", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    } else if speech.isRecording {
                        Button {
                            speech.stopRecording()
                        } label: {
                            Label("Stop Recording", systemImage: "stop.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }

                    Button {
                        speech.stopRecording()
                        showVoiceOverlay = false
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle(isReview ? "Review Transcript" : "Voice Input")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Command Result Sheet

    @ViewBuilder
    private var commandResultSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let cmd = runningCommand {
                        Text("Command").font(.caption).foregroundStyle(.secondary)
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
                                .foregroundStyle(.red).font(.caption)
                        } else {
                            Label("Success", systemImage: "checkmark.circle")
                                .foregroundStyle(.green).font(.caption)
                        }
                        if let out = result.stdout, !out.isEmpty {
                            Text("stdout").font(.caption).foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(out).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6)).cornerRadius(8)
                        }
                        if let err = result.stderr, !err.isEmpty {
                            Text("stderr").font(.caption).foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(err).font(.system(.caption, design: .monospaced)).foregroundStyle(.red).textSelection(.enabled)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6)).cornerRadius(8)
                        }
                    } else {
                        HStack { ProgressView(); Text("Running…") }
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

    // MARK: - Data Loading

    private func loadMessagesAsync() {
        loadingMessages = true
        let convId = conversation.id
        Task.detached {
            let msgs = ChatStore.shared.messages(conversationId: convId, limit: pageSize)
            let total = ChatStore.shared.messageCount(conversationId: convId)
            await MainActor.run {
                chatMessages = msgs
                rebuildFlatItems()
                hasMoreMessages = msgs.count < total
                loadingMessages = false
            }
        }
    }

    private func loadEarlierMessages() {
        guard let earliest = chatMessages.first else { return }
        loadingMore = true
        let convId = conversation.id
        let before = earliest.createdAt
        Task.detached {
            let older = ChatStore.shared.messages(conversationId: convId, limit: pageSize, beforeDate: before)
            let total = ChatStore.shared.messageCount(conversationId: convId)
            await MainActor.run {
                chatMessages.insert(contentsOf: older, at: 0)
                rebuildFlatItems()
                hasMoreMessages = chatMessages.count < total
                loadingMore = false
            }
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = message.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        message = ""
        loading = true
        streamingContent = ""
        streamingBuffer = ""
        isNearBottom = true
        haptic.impactOccurred()

        let userMsg = ChatMessage(
            id: UUID().uuidString,
            conversationId: conversation.id,
            workspacePath: repo.path,
            sessionId: sessionId,
            role: .user,
            content: text,
            createdAt: Date()
        )
        ChatStore.shared.insert(userMsg)
        ChatStore.shared.updateConversationTitle(conversationId: conversation.id, title: text)
        chatMessages.append(userMsg)
        rebuildFlatItems()

        Task {
            do {
                let res: AgentResponse
                if connectionMode == .wifi {
                    let client = HTTPClient(baseURL: wifiURL.trimmingCharacters(in: .whitespaces))
                    res = try await client.runAgentStreaming(workspace: repo.path, message: text, sessionId: sessionId) { delta in
                        streamingBuffer += delta
                    }
                } else {
                    res = try await peer.runAgentStreaming(workspace: repo.path, message: text, sessionId: sessionId) { delta in
                        streamingBuffer += delta
                    }
                }
                await MainActor.run {
                    streamingContent += streamingBuffer
                    streamingBuffer = ""

                    if let newSid = res.sessionId {
                        sessionId = newSid
                        onSessionUpdated?(newSid)
                    }
                    let content = (res.output ?? "") + (res.error.map { "\n\nError: \($0)" } ?? "")
                    let errText = (res.error ?? "").lowercased()
                    if errText.contains("workspace trust") || errText.contains("pass --trust") || errText.contains("--yolo") {
                        showTrustAlert = true
                    }
                    if !content.isEmpty {
                        let assistantMsg = ChatMessage(
                            id: UUID().uuidString,
                            conversationId: conversation.id,
                            workspacePath: repo.path,
                            sessionId: sessionId,
                            role: .assistant,
                            content: content,
                            createdAt: Date()
                        )
                        ChatStore.shared.insert(assistantMsg)
                        chatMessages.append(assistantMsg)
                        rebuildFlatItems()
                    }
                    streamingContent = ""
                    loading = false
                }
            } catch {
                await MainActor.run {
                    streamingContent += streamingBuffer
                    streamingBuffer = ""
                    streamingContent = ""
                    loading = false
                    let errDesc = error.localizedDescription.lowercased()
                    if errDesc.contains("workspace trust") || errDesc.contains("pass --trust") || errDesc.contains("--yolo") {
                        showTrustAlert = true
                    }
                    let errMsg = ChatMessage(
                        id: UUID().uuidString,
                        conversationId: conversation.id,
                        workspacePath: repo.path,
                        sessionId: sessionId,
                        role: .assistant,
                        content: "Error: \(error.localizedDescription)",
                        createdAt: Date()
                    )
                    ChatStore.shared.insert(errMsg)
                    chatMessages.append(errMsg)
                    rebuildFlatItems()
                    if isConnectionError(error) { onConnectionLost?() }
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
                if connectionMode == .wifi {
                    result = try await HTTPClient(baseURL: wifiURL.trimmingCharacters(in: .whitespaces))
                        .runCommand(command, workspace: repo.path)
                } else {
                    result = try await peer.runCommand(command, workspace: repo.path)
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

    private func sendMessageWithImage() {
        guard let imgData = pendingImageData else { return }
        let userText = message.trimmingCharacters(in: .whitespaces)
        pendingImageData = nil
        uploadingImage = true

        Task {
            do {
                let remotePath: String
                if connectionMode == .wifi {
                    remotePath = try await HTTPClient(baseURL: wifiURL.trimmingCharacters(in: .whitespaces))
                        .uploadImage(imgData)
                } else {
                    remotePath = try await peer.uploadImage(imgData)
                }
                await MainActor.run {
                    uploadingImage = false
                    let imageRef = "I've attached a screenshot saved at: \(remotePath)\nPlease look at this image and help me with what you see."
                    message = userText.isEmpty ? imageRef : "\(userText)\n\n\(imageRef)"
                    sendMessage()
                }
            } catch {
                await MainActor.run {
                    uploadingImage = false
                    if !userText.isEmpty { message = userText }
                    imageUploadError = error.localizedDescription
                }
            }
        }
    }

    private func isConnectionError(_ error: Error) -> Bool {
        let s = error.localizedDescription.lowercased()
        return s.contains("not connected") || s.contains("could not connect") || s.contains("network") || s.contains("timed out") || (error as NSError).code == -1009 || (error as NSError).code == -1004
    }
}

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

// MARK: - AgentView (Conversation List)

struct AgentView: View {
    @ObservedObject var peer: PeerClient
    let wifiURL: String
    let connectionMode: ConnectionMode?
    var onConnectionLost: (() -> Void)?
    @Binding var externalMessage: String
    @State private var repos: [RepoItem] = []
    @State private var selectedRepo: RepoItem?
    @State private var conversations: [Conversation] = []
    @State private var activeConversation: Conversation?
    @State private var showChatDetail = false
    @State private var loadError: String?
    @State private var initialLoad = true
    @State private var loading = false
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteConversation(conv)
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
            if selectedRepo != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        startNewChat()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
        .onAppear {
            if initialLoad {
                initialLoad = false
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
        .fullScreenCover(isPresented: $showChatDetail) {
            if let conv = activeConversation, let repo = selectedRepo {
                NavigationStack {
                    ChatDetailView(
                        peer: peer,
                        wifiURL: wifiURL,
                        connectionMode: connectionMode,
                        repo: repo,
                        conversation: conv,
                        onConnectionLost: onConnectionLost,
                        onSessionUpdated: { newSid in
                            setSessionId(workspace: repo.path, value: newSid)
                            if let convId = activeConversation?.id {
                                ChatStore.shared.updateConversationSession(conversationId: convId, sessionId: newSid)
                            }
                            reloadConversations()
                        },
                        onDismiss: {
                            showChatDetail = false
                            reloadConversations()
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
        let conv = ChatStore.shared.createConversation(workspacePath: repo.path, sessionId: nil, title: "")
        activeConversation = conv
        showChatDetail = true
        reloadConversations()
    }

    private func openOrCreateConversationWithMessage(_ msg: String) {
        guard let repo = selectedRepo else { return }
        if let sid = getSessionId(workspace: repo.path),
           let existing = ChatStore.shared.conversationForSession(workspacePath: repo.path, sessionId: sid) {
            activeConversation = existing
        } else {
            let conv = ChatStore.shared.createConversation(workspacePath: repo.path, sessionId: getSessionId(workspace: repo.path), title: "")
            activeConversation = conv
        }
        showChatDetail = true
    }

    private func deleteConversation(_ conv: Conversation) {
        ChatStore.shared.deleteConversation(conversationId: conv.id)
        if conv.sessionId != nil {
            setSessionId(workspace: conv.workspacePath, value: nil)
        }
        reloadConversations()
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

// MARK: - Chat Detail View

struct ChatDetailView: View {
    @ObservedObject var peer: PeerClient
    let wifiURL: String
    let connectionMode: ConnectionMode?
    let repo: RepoItem
    let conversation: Conversation
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

    @State private var loadingMessages = true
    @State private var isNearBottom = true
    @State private var streamingBuffer = ""
    @State private var scrollProxy: ScrollViewProxy?

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
            sessionId = conversation.sessionId
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
                showImagePicker = false
                pendingImageData = data
                uploadAndAttachImage(data)
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
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            message.trimmingCharacters(in: .whitespaces).isEmpty || loading
                                ? Color.gray : Color.accentColor
                        )
                }
                .disabled(message.trimmingCharacters(in: .whitespaces).isEmpty || loading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    // MARK: - Voice Overlay

    @ViewBuilder
    private var voiceOverlay: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: speech.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(speech.isRecording ? Color.red : Color.accentColor)
                    .opacity(speech.isRecording ? 0.6 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: speech.isRecording)

                Text(speech.isRecording ? "Listening…" : "Stopped")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(speech.transcript.isEmpty ? "Say something…" : speech.transcript)
                        .font(.body)
                        .foregroundStyle(speech.transcript.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(maxHeight: 200)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)

                Spacer()

                HStack(spacing: 20) {
                    Button {
                        speech.stopRecording()
                        showVoiceOverlay = false
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    if speech.isRecording {
                        Button {
                            speech.stopRecording()
                        } label: {
                            Label("Stop", systemImage: "stop.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } else if !speech.transcript.isEmpty {
                        Button {
                            message += (message.isEmpty ? "" : " ") + speech.transcript
                            showVoiceOverlay = false
                        } label: {
                            Label("Use Text", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Voice Input")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
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
                        ChatStore.shared.updateConversationSession(conversationId: conversation.id, sessionId: newSid)
                    }
                    let content = (res.output ?? "") + (res.error.map { "\n\nError: \($0)" } ?? "")
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

    private func uploadAndAttachImage(_ data: Data) {
        uploadingImage = true
        Task {
            do {
                let remotePath: String
                if connectionMode == .wifi {
                    remotePath = try await HTTPClient(baseURL: wifiURL.trimmingCharacters(in: .whitespaces))
                        .uploadImage(data)
                } else {
                    remotePath = try await peer.uploadImage(data)
                }
                await MainActor.run {
                    uploadingImage = false
                    message += (message.isEmpty ? "" : "\n") + "📷 I've attached a screenshot saved at: \(remotePath)\nPlease look at this image and help me with what you see."
                }
            } catch {
                await MainActor.run {
                    uploadingImage = false
                    message += "\n[Image upload failed: \(error.localizedDescription)]"
                }
            }
        }
    }

    private func isConnectionError(_ error: Error) -> Bool {
        let s = error.localizedDescription.lowercased()
        return s.contains("not connected") || s.contains("could not connect") || s.contains("network") || s.contains("timed out") || (error as NSError).code == -1009 || (error as NSError).code == -1004
    }
}

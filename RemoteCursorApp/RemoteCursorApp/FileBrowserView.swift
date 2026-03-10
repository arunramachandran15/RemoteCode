import SwiftUI

struct FileBrowserView: View {
    @ObservedObject var peer: PeerClient
    let wifiURL: String
    let connectionMode: ConnectionMode?
    @State private var repos: [RepoItem] = []
    @State private var selectedRepo: RepoItem?
    @AppStorage("lastSelectedRepoFiles") private var lastSelectedRepoPath = ""
    @State private var navigationPath: [FileItem] = []
    @State private var currentFiles: [FileItem] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var selectedFile: FileItem?
    @State private var initialLoad = true

    var body: some View {
        List {
            if repos.isEmpty && !loading {
                Section {
                    Text(errorMessage ?? "No repos available").foregroundStyle(errorMessage != nil ? .red : .secondary)
                }
            } else {
                Section("Repository") {
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
                if !navigationPath.isEmpty {
                    Section {
                        Button {
                            goBack()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                    }
                }

                Section(currentPathDisplay) {
                    if loading {
                        HStack {
                            ProgressView()
                            Text("Loading…").foregroundStyle(.secondary)
                        }
                    } else if let err = errorMessage {
                        Text(err).foregroundStyle(.red).font(.caption)
                    } else if currentFiles.isEmpty {
                        Text("Empty directory").foregroundStyle(.secondary)
                    } else {
                        ForEach(currentFiles) { file in
                            Button {
                                handleTap(file)
                            } label: {
                                fileRow(file)
                            }
                            .contextMenu {
                                if !file.isDirectory {
                                    Button {
                                        downloadFile(file.path)
                                    } label: {
                                        Label("Download", systemImage: "arrow.down.circle")
                                    }
                                }
                                Button {
                                    UIPasteboard.general.string = file.path
                                } label: {
                                    Label("Copy Path", systemImage: "doc.on.doc")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                if !file.isDirectory {
                                    Button {
                                        downloadFile(file.path)
                                    } label: {
                                        Label("Download", systemImage: "arrow.down.circle")
                                    }
                                    .tint(.blue)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Files")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if initialLoad {
                initialLoad = false
                loadRepos()
            }
        }
        .onChange(of: selectedRepo?.path) { newPath in
            if let p = newPath { lastSelectedRepoPath = p }
            navigationPath = []
            loadFiles()
        }
        .sheet(item: $selectedFile) { file in
            NavigationStack {
                CodeViewerView(
                    peer: peer,
                    wifiURL: wifiURL,
                    connectionMode: connectionMode,
                    file: file
                )
            }
        }
    }

    private var currentPathDisplay: String {
        if let last = navigationPath.last {
            return last.name
        }
        return selectedRepo?.displayName ?? "Files"
    }

    private var currentDirectory: String {
        if let last = navigationPath.last {
            return last.path
        }
        return selectedRepo?.path ?? ""
    }

    private func fileRow(_ file: FileItem) -> some View {
        HStack {
            Image(systemName: file.iconName)
                .foregroundStyle(file.isDirectory ? .blue : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .foregroundStyle(.primary)
                if let size = file.size, !file.isDirectory {
                    Text(formatSize(size))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    private func handleTap(_ file: FileItem) {
        if file.isDirectory {
            navigationPath.append(file)
            loadFiles()
        } else {
            selectedFile = file
        }
    }

    private func downloadFile(_ remotePath: String) {
        DownloadManager.shared.startDownload(
            remotePath: remotePath,
            peer: peer,
            wifiURL: wifiURL,
            connectionMode: connectionMode
        )
    }

    private func goBack() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
        loadFiles()
    }

    private func loadRepos() {
        loading = true
        errorMessage = nil
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
                    if selectedRepo != nil { loadFiles() }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    loading = false
                }
            }
        }
    }

    private func loadFiles() {
        let dir = currentDirectory
        guard !dir.isEmpty else { return }
        loading = true
        errorMessage = nil
        Task {
            do {
                let files: [FileItem]
                if connectionMode == .wifi {
                    files = try await HTTPClient(baseURL: wifiURL.trimmingCharacters(in: .whitespaces)).listFiles(path: dir)
                } else {
                    files = try await peer.listFiles(path: dir)
                }
                await MainActor.run {
                    currentFiles = files.sorted { a, b in
                        if a.isDirectory != b.isDirectory { return a.isDirectory }
                        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                    }
                    loading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    loading = false
                }
            }
        }
    }
}

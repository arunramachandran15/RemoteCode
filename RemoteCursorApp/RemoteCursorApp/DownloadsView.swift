import SwiftUI

struct DownloadsView: View {
    @ObservedObject var peer: PeerClient
    let wifiURL: String
    let connectionMode: ConnectionMode?
    @ObservedObject private var manager = DownloadManager.shared
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var showDeleteAllConfirm = false
    @State private var manualPath = ""

    var body: some View {
        List {
            if !manager.activeDownloads.isEmpty {
                Section("Active Downloads") {
                    ForEach(manager.activeDownloads) { dl in
                        activeDownloadRow(dl)
                    }
                }
            }

            Section {
                HStack {
                    TextField("Remote file path on Mac…", text: $manualPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.subheadline, design: .monospaced))
                    Button {
                        let path = manualPath.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !path.isEmpty else { return }
                        manager.startDownload(
                            remotePath: path,
                            peer: peer,
                            wifiURL: wifiURL,
                            connectionMode: connectionMode
                        )
                        manualPath = ""
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title3)
                    }
                    .disabled(manualPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Download File from Mac")
            } footer: {
                Text("Enter the full path of a file on your Mac (e.g. /Users/you/project/build/app.apk)")
                    .font(.caption2)
            }

            Section {
                if manager.downloads.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("No downloads yet")
                                .foregroundStyle(.secondary)
                            Text("Download files from agent chat or enter a path above")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 30)
                        Spacer()
                    }
                } else {
                    ForEach(manager.downloads) { file in
                        downloadedFileRow(file)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    manager.deleteFile(file)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            } header: {
                HStack {
                    Text("Downloaded Files")
                    Spacer()
                    if !manager.downloads.isEmpty {
                        Text("\(manager.downloads.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                if !manager.downloads.isEmpty {
                    Text("Files are saved to Documents/RemoteCursor and visible in the iOS Files app.")
                        .font(.caption2)
                }
            }
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !manager.downloads.isEmpty {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear All") {
                        showDeleteAllConfirm = true
                    }
                }
            }
        }
        .alert("Delete All Downloads?", isPresented: $showDeleteAllConfirm) {
            Button("Delete All", role: .destructive) {
                manager.deleteAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all downloaded files from your device.")
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
        .onAppear {
            manager.reload()
        }
    }

    private func activeDownloadRow(_ dl: ActiveDownload) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.blue)
                Text(dl.fileName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                if dl.isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            if let err = dl.error {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                ProgressView(value: dl.progress)
                    .tint(dl.isComplete ? .green : .blue)
                Text(dl.isComplete ? "Complete" : "\(Int(dl.progress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func downloadedFileRow(_ file: DownloadedFile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: file.iconName)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(file.formattedSize)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(fileDate(file.downloadedAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                shareURL = file.localURL
                showShareSheet = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func fileDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let fmt = DateFormatter()
            fmt.dateFormat = "h:mm a"
            return fmt.string(from: date)
        }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

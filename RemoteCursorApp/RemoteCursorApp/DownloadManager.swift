import Foundation
import SwiftUI

struct DownloadedFile: Identifiable, Hashable {
    let id: String
    let name: String
    let localURL: URL
    let remotePath: String
    let size: Int64
    let downloadedAt: Date

    var formattedSize: String {
        if size < 1024 { return "\(size) B" }
        if size < 1024 * 1024 { return String(format: "%.1f KB", Double(size) / 1024) }
        if size < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(size) / (1024 * 1024)) }
        return String(format: "%.2f GB", Double(size) / (1024 * 1024 * 1024))
    }

    var iconName: String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "apk": return "android"
        case "ipa", "app": return "iphone"
        case "zip", "tar", "gz", "tgz": return "doc.zipper"
        case "dmg": return "externaldrive"
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "webp": return "photo"
        default: return "doc"
        }
    }

    static func == (lhs: DownloadedFile, rhs: DownloadedFile) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct ActiveDownload: Identifiable {
    let id: String
    let remotePath: String
    let fileName: String
    var progress: Double
    var error: String?
    var isComplete: Bool
}

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var downloads: [DownloadedFile] = []
    @Published var activeDownloads: [ActiveDownload] = []

    private let fm = FileManager.default

    static var downloadsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("RemoteCursor", isDirectory: true)
    }

    private init() {
        ensureDirectory()
        reload()
    }

    private func ensureDirectory() {
        try? fm.createDirectory(at: Self.downloadsDirectory, withIntermediateDirectories: true)
    }

    func reload() {
        ensureDirectory()
        let dir = Self.downloadsDirectory
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]) else {
            downloads = []
            return
        }
        downloads = files.compactMap { url in
            guard let attrs = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .isDirectoryKey]),
                  attrs.isDirectory != true else { return nil }
            return DownloadedFile(
                id: url.lastPathComponent,
                name: url.lastPathComponent,
                localURL: url,
                remotePath: "",
                size: Int64(attrs.fileSize ?? 0),
                downloadedAt: attrs.creationDate ?? Date()
            )
        }
        .sorted { $0.downloadedAt > $1.downloadedAt }
    }

    func startDownload(
        remotePath: String,
        peer: PeerClient,
        wifiURL: String,
        connectionMode: ConnectionMode?
    ) {
        let fileName = (remotePath as NSString).lastPathComponent
        let localURL = Self.uniqueLocalURL(for: fileName)
        let downloadId = UUID().uuidString

        var active = ActiveDownload(
            id: downloadId,
            remotePath: remotePath,
            fileName: fileName,
            progress: 0,
            error: nil,
            isComplete: false
        )
        activeDownloads.append(active)

        Task {
            do {
                if connectionMode == .wifi {
                    try await HTTPClient(baseURL: wifiURL.trimmingCharacters(in: .whitespaces))
                        .downloadFile(remotePath: remotePath, to: localURL) { pct in
                            self.updateProgress(id: downloadId, progress: pct)
                        }
                } else {
                    try await peer.downloadFile(remotePath: remotePath, to: localURL) { pct in
                        self.updateProgress(id: downloadId, progress: pct)
                    }
                }
                markComplete(id: downloadId)
                reload()
            } catch {
                markError(id: downloadId, error: error.localizedDescription)
            }
        }
    }

    func deleteFile(_ file: DownloadedFile) {
        try? fm.removeItem(at: file.localURL)
        reload()
    }

    func deleteAll() {
        for file in downloads {
            try? fm.removeItem(at: file.localURL)
        }
        reload()
    }

    private func updateProgress(id: String, progress: Double) {
        if let idx = activeDownloads.firstIndex(where: { $0.id == id }) {
            activeDownloads[idx].progress = progress
        }
    }

    private func markComplete(id: String) {
        if let idx = activeDownloads.firstIndex(where: { $0.id == id }) {
            activeDownloads[idx].isComplete = true
            activeDownloads[idx].progress = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.activeDownloads.removeAll { $0.id == id }
        }
    }

    private func markError(id: String, error: String) {
        if let idx = activeDownloads.firstIndex(where: { $0.id == id }) {
            activeDownloads[idx].error = error
        }
    }

    private static func uniqueLocalURL(for fileName: String) -> URL {
        let dir = downloadsDirectory
        var url = dir.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: url.path) { return url }
        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var counter = 1
        while FileManager.default.fileExists(atPath: url.path) {
            counter += 1
            let newName = ext.isEmpty ? "\(name) (\(counter))" : "\(name) (\(counter)).\(ext)"
            url = dir.appendingPathComponent(newName)
        }
        return url
    }
}

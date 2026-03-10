import Foundation

final class CloudBackupManager {
    static let shared = CloudBackupManager()

    private var lastBackupTime: Date = .distantPast
    private let debounceInterval: TimeInterval = 30
    private var pendingBackup: DispatchWorkItem?
    private let backupQueue = DispatchQueue(label: "com.remotecursor.cloudbackup")

    private init() {}

    var iCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private var iCloudContainerURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
    }

    private var backupFileURL: URL? {
        iCloudContainerURL?.appendingPathComponent("chat_backup.sqlite")
    }

    /// Schedules a debounced backup — at most once per 30 seconds.
    func scheduleBackup() {
        pendingBackup?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.performBackup()
        }
        pendingBackup = item

        let elapsed = Date().timeIntervalSince(lastBackupTime)
        let delay = max(0, debounceInterval - elapsed)
        backupQueue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Immediately runs a backup (called on app background).
    func performBackupNow() {
        backupQueue.async { [weak self] in
            self?.performBackup()
        }
    }

    private func performBackup() {
        guard iCloudAvailable else {
            DebugLog.log("CloudBackup: iCloud not available, skipping")
            return
        }
        guard let containerURL = iCloudContainerURL,
              let backupURL = backupFileURL else {
            DebugLog.log("CloudBackup: Could not get iCloud container URL")
            return
        }

        do {
            try ChatStore.shared.backupDatabase(to: backupURL.path, containerDir: containerURL)
            lastBackupTime = Date()
            DebugLog.log("CloudBackup: Backup completed to \(backupURL.path)")
        } catch {
            DebugLog.log("CloudBackup: Backup failed: \(error.localizedDescription)")
        }
    }

    /// Restores from iCloud backup if local DB is empty (fresh install). Returns true if restored.
    func restoreIfNeeded() -> Bool {
        guard iCloudAvailable else {
            DebugLog.log("CloudBackup: iCloud not available for restore")
            return false
        }
        guard let backupURL = backupFileURL else {
            DebugLog.log("CloudBackup: No backup URL")
            return false
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: backupURL.path) else {
            DebugLog.log("CloudBackup: No backup found in iCloud")
            return false
        }

        if ChatStore.shared.hasData() {
            DebugLog.log("CloudBackup: Local DB has data, skipping restore")
            return false
        }

        do {
            try ChatStore.shared.restoreDatabase(from: backupURL.path)
            DebugLog.log("CloudBackup: Restored from iCloud backup")
            return true
        } catch {
            DebugLog.log("CloudBackup: Restore failed: \(error.localizedDescription)")
            return false
        }
    }
}

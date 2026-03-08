import Foundation

enum Config {
    static let serviceType = "remotecursor" // max 15 chars, lowercase
    static let httpPort: UInt16 = 3847

    static var repoPaths: [String] {
        let raw: [String]
        if let url = configURL,
           FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let repos = json["repos"] as? [String], !repos.isEmpty {
            raw = repos
        } else {
            raw = defaultRepos
        }
        // Only return paths that exist (directories) so the app never gets invalid repos
        let fm = FileManager.default
        let existing = raw.filter { path in
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }
        return existing.isEmpty ? [fm.homeDirectoryForCurrentUser.path] : existing
    }

    private static var configURL: URL? {
        let fm = FileManager.default
        // 1) Next to the running executable (works when run from Xcode or Terminal)
        if let exec = Bundle.main.executableURL?.deletingLastPathComponent() {
            let nextToExec = exec.appendingPathComponent("config.json")
            if fm.fileExists(atPath: nextToExec.path) { return nextToExec }
        }
        // 2) Current working directory
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let inCwd = cwd.appendingPathComponent("config.json")
        if fm.fileExists(atPath: inCwd.path) { return inCwd }
        return inCwd
    }

    private static var defaultRepos: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            home,
            "\(home)/Projects",
            "\(home)/Developer",
            "\(home)/work",
            "\(home)/Code",
            "/Volumes/work",
            "/Volumes/work/NilanTech",
            "/Volumes/work/NilanTech/RemoteCursor",
        ]
    }

    static func ensureConfigExists() {
        guard let url = configURL else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            let obj: [String: Any] = ["repos": defaultRepos]
            if let data = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted) {
                try? data.write(to: url)
            }
        }
    }
}

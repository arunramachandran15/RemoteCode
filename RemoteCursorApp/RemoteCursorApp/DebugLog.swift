import Foundation

/// Use only in Debug builds. Logs appear in Xcode console and in Console.app when device is connected.
enum DebugLog {
    static func log(_ message: String) {
        #if DEBUG
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let time = formatter.string(from: Date())
        print("[RemoteCursor \(time)] \(message)")
        #endif
    }
}

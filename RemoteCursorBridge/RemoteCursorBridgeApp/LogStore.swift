import Foundation
import AppKit

/// Holds log lines from the bridge for display in the app.
final class LogStore: ObservableObject {
    static let shared = LogStore()

    @Published private(set) var lines: [String] = []
    private let queue = DispatchQueue(label: "logstore")
    private let maxLines = 2000

    func append(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lines.append(trimmed)
            if self.lines.count > self.maxLines {
                self.lines.removeFirst(self.lines.count - self.maxLines)
            }
        }
    }

    func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.lines.removeAll()
        }
    }
}

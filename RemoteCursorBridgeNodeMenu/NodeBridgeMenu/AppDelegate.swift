import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let bridge = NodeBridgeManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Node Bridge")
        statusItem?.button?.imagePosition = .imageLeading
        updateMenu()
    }

    private func updateMenu() {
        guard let menu = statusItem?.menu ?? NSMenu() else { return }
        menu.removeAllItems()

        let titleItem = NSMenuItem(title: bridge.isRunning ? "Bridge: Running" : "Bridge: Stopped", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        if bridge.isRunning {
            menu.addItem(NSMenuItem(title: "Stop Bridge", action: #selector(stopBridge), keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "Start Bridge", action: #selector(startBridge), keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem(title: "Set Bridge Path…", action: #selector(choosePath), keyEquivalent: ""))
        if let path = bridge.bridgePath, !path.isEmpty {
            let pathItem = NSMenuItem(title: "Path: \(path)", action: nil, keyEquivalent: "")
            pathItem.isEnabled = false
            pathItem.toolTip = path
            menu.addItem(pathItem)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.shared.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }
        statusItem?.menu = menu
    }

    @objc private func startBridge() {
        bridge.start { [weak self] success, message in
            DispatchQueue.main.async {
                self?.updateMenu()
                if !success, let msg = message {
                    NSAlert.runModal(message: msg, title: "Could not start bridge")
                }
            }
        }
    }

    @objc private func stopBridge() {
        bridge.stop()
        updateMenu()
    }

    @objc private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the RemoteCursorBridgeNode folder (contains server.js and package.json)"
        if let current = bridge.bridgePath, !current.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: (current as NSString).deletingLastPathComponent)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("server.js").path) {
            bridge.setBridgePath(path)
            updateMenu()
        } else {
            NSAlert.runModal(message: "Selected folder does not contain server.js. Choose the RemoteCursorBridgeNode folder.", title: "Invalid folder")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        bridge.stop()
    }
}

extension NSAlert {
    static func runModal(message: String, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

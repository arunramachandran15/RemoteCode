import SwiftUI

@main
struct RemoteCursorBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var logStore = LogStore.shared

    var body: some Scene {
        WindowGroup {
            LogView()
                .environmentObject(logStore)
                .frame(minWidth: 400, minHeight: 300)
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            VStack(spacing: 12) {
                Text("Remote Cursor Bridge")
                    .font(.headline)
                Text("Wi‑Fi: http://<this-mac-ip>:\(Config.httpPort)")
                    .font(.caption)
                Text("Use \"Find Mac\" in the iOS app to connect.")
                    .font(.caption)
            }
            .frame(width: 280, height: 100)
            .padding()
        }
    }
}

struct LogView: View {
    @EnvironmentObject var logStore: LogStore
    @State private var autoScroll = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Bridge logs")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    logStore.clear()
                }
                .buttonStyle(.borderless)
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logStore.lines.enumerated()), id: \.offset) { i, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                        }
                    }
                    .id("bottom")
                }
                .onChange(of: logStore.lines.count) { _ in
                    if autoScroll {
                        withAnimation(.none) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }
        }
    }
}

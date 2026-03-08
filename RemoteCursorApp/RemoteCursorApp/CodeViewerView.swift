import SwiftUI

struct CodeViewerView: View {
    @ObservedObject var peer: PeerClient
    let wifiURL: String
    let connectionMode: ConnectionMode?
    let file: FileItem
    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var originalContent = ""
    @State private var loading = true
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var isEditing = false
    @State private var showSavedAlert = false

    private var hasChanges: Bool { content != originalContent }

    var body: some View {
        VStack(spacing: 0) {
            if loading {
                Spacer()
                ProgressView("Loading…")
                Spacer()
            } else if let err = errorMessage, content.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(err).foregroundStyle(.red)
                }
                Spacer()
            } else {
                fileInfoBar
                if isEditing {
                    TextEditor(text: $content)
                        .font(.system(.callout, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } else {
                    ScrollView(.horizontal) {
                        ScrollView(.vertical) {
                            lineNumberedCode
                                .padding(10)
                        }
                    }
                }
            }
        }
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if !loading && content.isEmpty == false {
                    Button {
                        isEditing.toggle()
                    } label: {
                        Image(systemName: isEditing ? "eye" : "pencil")
                    }
                    if hasChanges {
                        Button {
                            saveFile()
                        } label: {
                            if saving {
                                ProgressView()
                            } else {
                                Image(systemName: "square.and.arrow.down")
                            }
                        }
                        .disabled(saving)
                    }
                }
            }
        }
        .alert("Saved", isPresented: $showSavedAlert) {
            Button("OK") {}
        }
        .onAppear { loadFile() }
    }

    private var fileInfoBar: some View {
        HStack {
            Text(file.path)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if hasChanges {
                Text("Modified")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            Text("\(content.components(separatedBy: "\n").count) lines")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
    }

    private var lineNumberedCode: some View {
        let lines = content.components(separatedBy: "\n")
        let digitCount = max(String(lines.count).count, 2)
        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { idx, _ in
                    Text(String(format: "%\(digitCount)d", idx + 1))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color(.systemGray3))
                }
            }
            .padding(.trailing, 8)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding(.leading, 8)
        }
    }

    private func loadFile() {
        loading = true
        errorMessage = nil
        Task {
            do {
                let text: String
                if connectionMode == .wifi {
                    text = try await HTTPClient(baseURL: wifiURL.trimmingCharacters(in: .whitespaces)).readFile(path: file.path)
                } else {
                    text = try await peer.readFile(path: file.path)
                }
                await MainActor.run {
                    content = text
                    originalContent = text
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

    private func saveFile() {
        saving = true
        Task {
            do {
                if connectionMode == .wifi {
                    try await HTTPClient(baseURL: wifiURL.trimmingCharacters(in: .whitespaces)).writeFile(path: file.path, content: content)
                } else {
                    try await peer.writeFile(path: file.path, content: content)
                }
                await MainActor.run {
                    originalContent = content
                    saving = false
                    showSavedAlert = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    saving = false
                }
            }
        }
    }
}

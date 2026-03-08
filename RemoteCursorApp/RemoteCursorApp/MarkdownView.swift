import SwiftUI

struct MarkdownView: View {
    let content: String
    var onRunCommand: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }
}

private let shellLanguages: Set<String> = ["bash", "shell", "sh", "zsh", ""]

private extension MarkdownView {
    enum Block {
        case heading(Int, String)
        case codeBlock(String?, String)
        case bullet(String)
        case numbered(String, String)
        case paragraph(String)
        case rule
    }

    func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        let lines = content.components(separatedBy: "\n")
        var i = 0
        var paraLines: [String] = []

        func flush() {
            let text = paraLines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            paraLines = []
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flush()
                let lang = String(trimmed.dropFirst(3))
                    .trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count &&
                      !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(lang.isEmpty ? nil : lang,
                                         code.joined(separator: "\n")))
                i += 1
                continue
            }

            if let m = trimmed.range(of: #"^(#{1,6})\s+"#, options: .regularExpression) {
                flush()
                let level = trimmed[m].filter { $0 == "#" }.count
                blocks.append(.heading(level, String(trimmed[m.upperBound...])))
                i += 1
                continue
            }

            if trimmed.range(of: #"^[-*+] "#, options: .regularExpression) != nil {
                flush()
                blocks.append(.bullet(String(trimmed.dropFirst(2))))
                i += 1
                continue
            }

            if let m = trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                flush()
                let num = String(trimmed[..<m.upperBound].prefix(while: \.isNumber))
                blocks.append(.numbered(num, String(trimmed[m.upperBound...])))
                i += 1
                continue
            }

            let stripped = trimmed.replacingOccurrences(of: " ", with: "")
            if stripped.count >= 3 &&
               (stripped.allSatisfy({ $0 == "-" }) ||
                stripped.allSatisfy({ $0 == "*" }) ||
                stripped.allSatisfy({ $0 == "_" })) {
                flush()
                blocks.append(.rule)
                i += 1
                continue
            }

            if trimmed.isEmpty {
                flush()
                i += 1
                continue
            }

            paraLines.append(line)
            i += 1
        }
        flush()
        return blocks
    }
}

private extension MarkdownView {
    @ViewBuilder
    func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)
        case .codeBlock(let lang, let code):
            codeBlockView(language: lang, code: code)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                inlineMarkdown(text)
            }
            .padding(.leading, 8)
        case .numbered(let num, let text):
            HStack(alignment: .top, spacing: 6) {
                Text("\(num).").foregroundStyle(.secondary).monospacedDigit()
                inlineMarkdown(text)
            }
            .padding(.leading, 8)
        case .paragraph(let text):
            inlineMarkdown(text)
        case .rule:
            Divider()
        }
    }

    @ViewBuilder
    func headingView(level: Int, text: String) -> some View {
        switch level {
        case 1: inlineMarkdown(text).font(.title).fontWeight(.bold)
        case 2: inlineMarkdown(text).font(.title2).fontWeight(.semibold)
        case 3: inlineMarkdown(text).font(.title3).fontWeight(.semibold)
        default: inlineMarkdown(text).font(.headline)
        }
    }

    func codeBlockView(language: String?, code: String) -> some View {
        let isRunnable = onRunCommand != nil && shellLanguages.contains(language ?? "")
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let lang = language {
                    Text(lang)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                if isRunnable {
                    Button {
                        onRunCommand?(code)
                    } label: {
                        Label("Run on Mac", systemImage: "play.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    func inlineMarkdown(_ text: String) -> Text {
        if let attr = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attr)
        }
        return Text(text)
    }
}

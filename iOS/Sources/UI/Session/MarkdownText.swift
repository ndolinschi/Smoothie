import SwiftUI

/// Renders agent message content as Markdown. Splits the body into blocks
/// (paragraph, heading, list, fenced code, blockquote, hr) and lays them
/// out in a `VStack`. Inline elements (`**bold**`, `*italic*`,
/// `` `code` ``, `[link](…)`) inside text blocks are parsed via
/// Foundation's `AttributedString(markdown:)`.
struct MarkdownText: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .paragraph(let text):
            inlineMarkdown(text)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let text, let level):
            inlineMarkdown(text)
                .font(.system(size: headingSize(level), weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, level == 1 ? 6 : 2)
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                        inlineMarkdown(item)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(minWidth: 18, alignment: .trailing)
                        inlineMarkdown(item)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .quote(let text):
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 2)
                inlineMarkdown(text)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.75))
                    .italic()
                    .lineSpacing(2)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 2)
        case .codeBlock(let code, let lang):
            codeBlockView(code: code, language: lang)
        case .rule:
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5)
                .padding(.vertical, 4)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1:  return 22
        case 2:  return 19
        case 3:  return 17
        default: return 16
        }
    }

    private func inlineMarkdown(_ raw: String) -> Text {
        if let attr = try? AttributedString(
            markdown: raw,
            options: .init(
                allowsExtendedAttributes: false,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            return Text(attr)
        }
        return Text(raw)
    }

    private func codeBlockView(code: String, language: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                HStack {
                    Text(language.lowercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 10))
    }

    enum Block {
        case paragraph(String)
        case heading(String, Int)
        case bulletList([String])
        case numberedList([String])
        case quote(String)
        case codeBlock(String, String?)
        case rule
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var numbered: [String] = []
        var quote: [String] = []
        var inFence = false
        var fenceLang: String?
        var fence: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { out.append(.paragraph(text)) }
                paragraph.removeAll()
            }
        }
        func flushBullets() {
            if !bullets.isEmpty { out.append(.bulletList(bullets)); bullets.removeAll() }
        }
        func flushNumbered() {
            if !numbered.isEmpty { out.append(.numberedList(numbered)); numbered.removeAll() }
        }
        func flushQuote() {
            if !quote.isEmpty {
                out.append(.quote(quote.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)))
                quote.removeAll()
            }
        }
        func flushAllExcept(_ except: BlockKind = .none) {
            if except != .paragraph { flushParagraph() }
            if except != .bullets { flushBullets() }
            if except != .numbered { flushNumbered() }
            if except != .quote { flushQuote() }
        }

        for rawLine in content.components(separatedBy: "\n") {
            let line = rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inFence {
                    out.append(.codeBlock(fence.joined(separator: "\n"), fenceLang))
                    fence.removeAll()
                    fenceLang = nil
                    inFence = false
                } else {
                    flushAllExcept()
                    let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    fenceLang = lang.isEmpty ? nil : lang
                    inFence = true
                }
                continue
            }
            if inFence {
                fence.append(line)
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushAllExcept()
                out.append(.rule)
                continue
            }

            if let (level, headingText) = parseHeading(trimmed) {
                flushAllExcept()
                out.append(.heading(headingText, level))
                continue
            }

            if let bullet = parseBullet(trimmed) {
                flushAllExcept(.bullets)
                bullets.append(bullet)
                continue
            }

            if let (_, numItem) = parseNumbered(trimmed) {
                flushAllExcept(.numbered)
                numbered.append(numItem)
                continue
            }

            if trimmed.hasPrefix("> ") || trimmed == ">" {
                flushAllExcept(.quote)
                quote.append(String(trimmed.dropFirst(trimmed == ">" ? 1 : 2)))
                continue
            }

            if trimmed.isEmpty {
                flushAllExcept()
                continue
            }

            flushAllExcept(.paragraph)
            paragraph.append(line)
        }

        if inFence, !fence.isEmpty {
            out.append(.codeBlock(fence.joined(separator: "\n"), fenceLang))
        }
        flushAllExcept()
        return out
    }

    private enum BlockKind { case none, paragraph, bullets, numbered, quote }

    private func parseHeading(_ s: String) -> (Int, String)? {
        var level = 0
        for char in s {
            if char == "#" { level += 1 } else { break }
            if level > 6 { return nil }
        }
        guard level >= 1, level <= 6 else { return nil }
        let rest = String(s.dropFirst(level))
        guard rest.hasPrefix(" ") else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    private func parseBullet(_ s: String) -> String? {
        let bullets = ["- ", "* ", "+ ", "• "]
        for b in bullets where s.hasPrefix(b) {
            return String(s.dropFirst(b.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private func parseNumbered(_ s: String) -> (Int, String)? {
        guard let firstSpace = s.firstIndex(of: " ") else { return nil }
        let prefix = s[s.startIndex..<firstSpace]
        guard prefix.hasSuffix(".") else { return nil }
        let numStr = prefix.dropLast()
        guard let n = Int(numStr), n >= 0 else { return nil }
        let rest = String(s[s.index(after: firstSpace)...]).trimmingCharacters(in: .whitespaces)
        return (n, rest)
    }
}

import SwiftUI

/// Renders agent message content as Markdown. Splits the body into blocks
/// (paragraph, heading, list, fenced code, blockquote, hr) and lays them
/// out in a `VStack`. Inline elements (`**bold**`, `*italic*`,
/// `` `code` ``, `[link](…)`) inside text blocks are parsed via
/// Foundation's `AttributedString(markdown:)`.
struct MarkdownText: View {
    let content: String

    /// Cache the parsed blocks so a streaming agent's per-token content
    /// update doesn't re-tokenise the entire string on every body redraw.
    /// We key the cache by the content string itself — Swift's `String`
    /// hashing is cheap and Equatable check short-circuits the rare case
    /// where the same content arrives twice.
    @State private var cachedBlocks: [Block] = []
    @State private var cachedContent: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(currentBlocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { refreshBlocksIfNeeded() }
        .onChange(of: content) { _, _ in refreshBlocksIfNeeded() }
    }

    /// Read-through accessor — falls back to a fresh parse if `.onAppear`
    /// hasn't fired yet (first render). Subsequent renders use the cache.
    private var currentBlocks: [Block] {
        cachedContent == content ? cachedBlocks : Self.parseBlocks(content)
    }

    private func refreshBlocksIfNeeded() {
        guard cachedContent != content else { return }
        cachedBlocks = Self.parseBlocks(content)
        cachedContent = content
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .paragraph(let text):
            InlineMarkdownFlow(raw: text, font: .system(size: 15), lineSpacing: 3, textColor: SmoothieColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        case .heading(let text, let level):
            inlineMarkdown(text)
                .font(.system(size: headingSize(level), weight: .bold))
                .foregroundStyle(SmoothieColor.textPrimary)
                .padding(.top, level == 1 ? 6 : 2)
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SmoothieColor.textSecondary)
                        InlineMarkdownFlow(raw: item, font: .system(size: 15), lineSpacing: 2, textColor: SmoothieColor.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(SmoothieColor.textSecondary)
                            .frame(minWidth: 18, alignment: .trailing)
                        InlineMarkdownFlow(raw: item, font: .system(size: 15), lineSpacing: 2, textColor: SmoothieColor.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
            }
        case .quote(let text):
            HStack(spacing: 10) {
                Rectangle()
                    .fill(SmoothieColor.strokeDashed)
                    .frame(width: 2)
                InlineMarkdownFlow(raw: text, font: .system(size: 14), lineSpacing: 2, textColor: SmoothieColor.textSecondary, italic: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 2)
        case .codeBlock(let code, let lang):
            codeBlockView(code: code, language: lang)
        case .rule:
            Rectangle()
                .fill(SmoothieColor.stroke)
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
                        .foregroundStyle(SmoothieColor.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(SyntaxHighlighter.highlight(code, language: language))
                    .font(.system(size: 12.5, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SmoothieColor.codeBg, in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5)
        )
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

    /// Parse the markdown body into structural blocks. Lifted out of the
    /// instance so it can be called from `currentBlocks` (computed) AND
    /// `refreshBlocksIfNeeded` (cache primer) without re-entering SwiftUI's
    /// dependency graph through `self`.
    static func parseBlocks(_ content: String) -> [Block] {
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

            if let (level, headingText) = Self.parseHeading(trimmed) {
                flushAllExcept()
                out.append(.heading(headingText, level))
                continue
            }

            if let bullet = Self.parseBullet(trimmed) {
                flushAllExcept(.bullets)
                bullets.append(bullet)
                continue
            }

            if let (_, numItem) = Self.parseNumbered(trimmed) {
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

    fileprivate static func parseHeading(_ s: String) -> (Int, String)? {
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

    fileprivate static func parseBullet(_ s: String) -> String? {
        let bullets = ["- ", "* ", "+ ", "• "]
        for b in bullets where s.hasPrefix(b) {
            return String(s.dropFirst(b.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    fileprivate static func parseNumbered(_ s: String) -> (Int, String)? {
        guard let firstSpace = s.firstIndex(of: " ") else { return nil }
        let prefix = s[s.startIndex..<firstSpace]
        guard prefix.hasSuffix(".") else { return nil }
        let numStr = prefix.dropLast()
        guard let n = Int(numStr), n >= 0 else { return nil }
        let rest = String(s[s.index(after: firstSpace)...]).trimmingCharacters(in: .whitespaces)
        return (n, rest)
    }
}

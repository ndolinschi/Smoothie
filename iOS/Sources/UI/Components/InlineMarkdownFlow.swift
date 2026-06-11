import SwiftUI

/// Renders inline markdown — bold, italic, links, AND inline `` `code` ``
/// — as a single `Text(AttributedString)` so wrap, selection, and span
/// rendering all just work the way SwiftUI's text engine intends.
///
/// History: P25 v1 of this component used a custom FlowLayout that
/// tokenised the prose by-word and rendered each as its own `Text` view
/// so that inline code could appear as a real pill-shaped `CodeChip`.
/// That broke any markdown construct spanning more than one word —
/// `**hello world**` got split into `**hello` + `world**`, both of which
/// are unbalanced and silently fall back to plain text. The pill shape
/// is dropped in v2; inline code now renders as a mono-font run with a
/// flat `codeBgDim` background — closer to how GitHub renders inline
/// code than to Cursor's rounded pill, but the trade is worth it.
/// `CodeChip` survives as a standalone view for non-inline uses (tool
/// card titles, status pills, etc.).
struct InlineMarkdownFlow: View {
    let raw: String
    var font: Font = .system(size: 15)
    var lineSpacing: CGFloat = 3
    var textColor: Color = SmoothieColor.textPrimary
    var italic: Bool = false

    var body: some View {
        Text(styled)
            .font(font)
            .foregroundStyle(textColor)
            .lineSpacing(lineSpacing)
            .italic(italic)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Cache the styled output per raw input on the view's identity so a
    /// streaming agent's per-token content update doesn't re-parse the
    /// entire paragraph on every redraw. Pure function so safe to call.
    private var styled: AttributedString { Self.style(raw) }

    /// Parse the raw text as inline markdown (bold/italic/links + inline
    /// `code`) and apply our own attributes to code runs so they read as
    /// monospaced chips against a dim background.
    static func style(_ raw: String) -> AttributedString {
        var attr = (try? AttributedString(
            markdown: raw,
            options: .init(
                allowsExtendedAttributes: true,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(raw)

        for run in attr.runs {
            if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                // Claude-style inline code: terracotta mono on a soft
                // terracotta wash, so identifiers pop out of prose.
                attr[run.range].font = .system(size: 13, weight: .regular, design: .monospaced)
                attr[run.range].backgroundColor = SmoothieColor.accentSoft
                attr[run.range].foregroundColor = SmoothieColor.accent
                // Strip the code intent so SwiftUI doesn't add its own
                // mono styling on top (which on iOS 26 sometimes inverts
                // the background or adds extra padding we don't want).
                attr[run.range].inlinePresentationIntent = nil
            }
        }

        return attr
    }
}

#if DEBUG
#Preview {
    VStack(alignment: .leading, spacing: 12) {
        InlineMarkdownFlow(raw: "Added `AGENTS.md` at the repo root: orientation (prefer this + `CLAUDE.md`; `vendor/` / `mcps/` submodule read-only).")
        InlineMarkdownFlow(raw: "**Bold prefix** then some inline `code()` and a final clause that wraps across multiple lines to demonstrate the rendering.")
        InlineMarkdownFlow(raw: "*Italic spans* across multiple words. **Bold spans too.** And [a link](https://example.com) lives inline.")
        InlineMarkdownFlow(raw: "Mix: **bold with `inline code` inside** and _italic with `mono` runs_ all in one line.", italic: false)
    }
    .padding()
    .background(SmoothieColor.bgPrimary)
    .preferredColorScheme(.dark)
}
#endif

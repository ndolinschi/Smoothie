import SwiftUI

/// Inline mono pill around code identifiers in prose. Replaces the prior
/// flat `codeBgDim` background run with a pill-shaped chip so it reads
/// as a distinct token rather than a highlighted span. Used by
/// `InlineMarkdownFlow` inside paragraphs — embedded as a sibling view
/// to text segments and flows with surrounding prose.
struct CodeChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(SmoothieColor.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: SmoothieMetrics.cornerXS, style: .continuous)
                    .fill(SmoothieColor.accentSoft)
            )
            .fixedSize(horizontal: true, vertical: true)
    }
}

#if DEBUG
#Preview {
    VStack(alignment: .leading, spacing: 12) {
        CodeChip(text: "AGENTS.md")
        CodeChip(text: "vendor/")
        CodeChip(text: "OPENCODE_DISABLE_CHANNEL_DB")
        HStack(spacing: 4) {
            Text("Read")
            CodeChip(text: "DesignTokens.swift")
            Text("first.")
        }
        .foregroundStyle(.white)
    }
    .padding()
    .background(SmoothieColor.bgPrimary)
}
#endif

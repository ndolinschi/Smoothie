import SwiftUI

/// P29 §2 — wraps a session row with optional indent + vertical guide
/// when the descriptor is nested under a parent session. Used by
/// HomeView's grouped session list once `bucketed()` annotates each
/// row with its tree depth.
///
/// `depth == 0` is a root row (no indent, no guide). For `depth >= 1`
/// we add 16pt per level of indent, draw a soft vertical guide along
/// the left edge of the indented region, and prefix the row content
/// with a small `corner.down.right` glyph so the parent/child
/// relationship is visually unmistakable at a glance.
struct SessionTreeRow<Content: View>: View {
    let depth: Int
    let content: () -> Content

    init(depth: Int, @ViewBuilder content: @escaping () -> Content) {
        self.depth = depth
        self.content = content
    }

    private let indentPerLevel: CGFloat = 16

    var body: some View {
        if depth <= 0 {
            content()
        } else {
            HStack(alignment: .center, spacing: 0) {
                ForEach(0..<depth, id: \.self) { level in
                    ZStack(alignment: .leading) {
                        // Vertical guide line along each level of
                        // indent. Stops at the second-to-last column
                        // since the leaf gets the corner glyph (not a
                        // continuing guide).
                        if level < depth - 1 {
                            Rectangle()
                                .fill(SmoothieColor.strokeSoft)
                                .frame(width: 0.5)
                                .padding(.vertical, 2)
                        } else {
                            // Last column owns the corner-down glyph.
                            cornerGlyph
                        }
                        Color.clear
                            .frame(width: indentPerLevel)
                    }
                }
                content()
            }
        }
    }

    private var cornerGlyph: some View {
        VStack(spacing: 0) {
            // Half-height vertical line above the corner glyph so the
            // visual guide flows continuously from the parent row.
            Rectangle()
                .fill(SmoothieColor.strokeSoft)
                .frame(width: 0.5)
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(SmoothieColor.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.leading, 0)
    }
}

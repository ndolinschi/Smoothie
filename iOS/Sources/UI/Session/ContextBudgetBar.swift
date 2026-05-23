import SwiftUI

/// 4pt-tall horizontal bar segmented by token-budget category. Reads
/// from a `ContextSnapshotWire` and renders one slice per category
/// proportional to its share of `total` (NOT `max`) so the bar always
/// fills its track — the percent indicator next to the bar carries
/// the "of-max" signal separately. Color palette mirrors the design
/// spec JSON in the plan file.
struct ContextBudgetBar: View {
    let snapshot: ContextSnapshotWire
    var height: CGFloat = 4

    /// Stable color map keyed by category id — matches the daemon's
    /// canonical ordering so a Mac-side preview and iOS render the
    /// same bar shape.
    private static let palette: [String: Color] = [
        "system_prompt":        Color(red: 0.61, green: 0.64, blue: 0.69), // #9CA3AF
        "tool_definitions":     Color(red: 0.65, green: 0.55, blue: 0.98), // #A78BFA
        "rules":                Color(red: 0.20, green: 0.83, blue: 0.60), // #34D399
        "skills":               Color(red: 0.98, green: 0.75, blue: 0.14), // #FBBF24
        "mcp":                  Color(red: 0.96, green: 0.45, blue: 0.71), // #F472B6
        "subagent_definitions": Color(red: 0.38, green: 0.65, blue: 0.98), // #60A5FA
        "conversation":         Color(red: 0.98, green: 0.57, blue: 0.24), // #FB923C
    ]

    static func color(for id: String) -> Color {
        palette[id] ?? SmoothieColor.textTertiary
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(snapshot.breakdown) { cat in
                    Rectangle()
                        .fill(Self.color(for: cat.id))
                        .frame(width: width(for: cat, total: snapshot.total, container: geo.size.width))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: height)
        .clipShape(Capsule())
        .background(SmoothieColor.bgChip, in: .capsule)
    }

    private func width(for cat: ContextCategoryWire, total: Int, container: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        let share = CGFloat(cat.tokens) / CGFloat(total)
        return max(0, container * share)
    }
}

#if DEBUG
#Preview {
    let snapshot = ContextSnapshotWire(
        total: 29100,
        max: 200000,
        breakdown: [
            ContextCategoryWire(id: "system_prompt",        label: "System prompt",        tokens: 588),
            ContextCategoryWire(id: "tool_definitions",     label: "Tool definitions",     tokens: 6700),
            ContextCategoryWire(id: "rules",                label: "Rules",                tokens: 11000),
            ContextCategoryWire(id: "skills",               label: "Skills",               tokens: 2200),
            ContextCategoryWire(id: "mcp",                  label: "MCP",                  tokens: 3100),
            ContextCategoryWire(id: "subagent_definitions", label: "Subagent definitions", tokens: 412),
            ContextCategoryWire(id: "conversation",         label: "Conversation",         tokens: 5100),
        ]
    )
    return VStack(alignment: .leading, spacing: 12) {
        ContextBudgetBar(snapshot: snapshot)
        ContextBudgetBar(snapshot: snapshot, height: 8)
    }
    .padding()
    .background(SmoothieColor.bgPrimary)
    .preferredColorScheme(.dark)
}
#endif

import SwiftUI

/// 44pt-tall bar pinned above the composer. Mirrors Cursor mobile's
/// bottom-of-thread status strip: left = "Local" + branch / project,
/// right = compact ring + percent showing how full the context window
/// is. Tapping the percent indicator opens `ContextBudgetPanel`. When
/// the daemon hasn't sent a context snapshot yet (older daemon, or
/// session just opened), the percent half hides entirely and only the
/// branch label shows — no fake numbers.
struct StatusFooter: View {
    let branchLabel: String
    let snapshot: ContextSnapshotWire?
    let onTapBudget: () -> Void

    private var fillPct: Int? {
        guard let s = snapshot, s.max > 0 else { return nil }
        return Int((Double(s.total) / Double(s.max)) * 100)
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 10))
                    .foregroundStyle(SmoothieColor.textTertiary)
                Text("Local")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(SmoothieColor.textTertiary)
                Text(branchLabel)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(SmoothieColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if let pct = fillPct, let snapshot {
                Button(action: onTapBudget) {
                    HStack(spacing: 6) {
                        ring(pct: pct, snapshot: snapshot)
                            .frame(width: 14, height: 14)
                        Text("\(pct)% context")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(SmoothieColor.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: SmoothieMetrics.footerHeight)
        .background(SmoothieColor.bgPrimary)
        .overlay(
            Rectangle()
                .fill(SmoothieColor.strokeSoft)
                .frame(height: 0.5),
            alignment: .top
        )
    }

    /// Mini segmented ring — uses the same per-category color map as
    /// `ContextBudgetBar` so visual identity carries through. Renders
    /// each category as an arc proportional to its share of `total`,
    /// with an empty gap representing the remaining unused window.
    private func ring(pct: Int, snapshot: ContextSnapshotWire) -> some View {
        Canvas { ctx, size in
            let lineWidth: CGFloat = 2.5
            let radius = (min(size.width, size.height) - lineWidth) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let full = CGFloat(snapshot.max)
            let occupied = CGFloat(snapshot.total)
            guard full > 0, occupied > 0 else { return }
            // Background track for the unused portion
            var bg = Path()
            bg.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(270), clockwise: false)
            ctx.stroke(bg, with: .color(SmoothieColor.strokeSoft), lineWidth: lineWidth)
            // Occupied portion split per category
            var cursorAngle: CGFloat = -90
            let totalSweep: CGFloat = 360 * (occupied / full)
            for cat in snapshot.breakdown {
                guard cat.tokens > 0 else { continue }
                let sweep = totalSweep * CGFloat(cat.tokens) / CGFloat(snapshot.total)
                var seg = Path()
                seg.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(Double(cursorAngle)),
                    endAngle: .degrees(Double(cursorAngle + sweep)),
                    clockwise: false
                )
                ctx.stroke(
                    seg,
                    with: .color(ContextBudgetBar.color(for: cat.id)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                )
                cursorAngle += sweep
            }
        }
    }
}

#if DEBUG
#Preview {
    let snap = ContextSnapshotWire(
        total: 29100,
        max: 200000,
        breakdown: [
            ContextCategoryWire(id: "system_prompt",    label: "System prompt",    tokens: 588),
            ContextCategoryWire(id: "tool_definitions", label: "Tool definitions", tokens: 6700),
            ContextCategoryWire(id: "rules",            label: "Rules",            tokens: 11000),
            ContextCategoryWire(id: "skills",           label: "Skills",           tokens: 2200),
            ContextCategoryWire(id: "mcp",              label: "MCP",              tokens: 3100),
            ContextCategoryWire(id: "subagent_definitions", label: "Subagent definitions", tokens: 412),
            ContextCategoryWire(id: "conversation",     label: "Conversation",     tokens: 5100),
        ]
    )
    return VStack(spacing: 0) {
        Color.clear.frame(maxHeight: .infinity)
        StatusFooter(branchLabel: "main", snapshot: snap, onTapBudget: {})
        StatusFooter(branchLabel: "main", snapshot: nil, onTapBudget: {})
    }
    .background(SmoothieColor.bgPrimary)
    .preferredColorScheme(.dark)
}
#endif

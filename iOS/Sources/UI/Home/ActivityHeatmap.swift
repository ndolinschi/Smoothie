import SwiftUI

/// Compact GitHub-style contribution graph for "sessions started per day".
/// Rows = day-of-week (Mon → Sun), columns = weeks (oldest left, today
/// right). Cell tint deepens monochromatically as the bucket count grows
/// (P25 retired the coral accent here — density is signalled by white
/// opacity alone). Tap a day to scroll the list below to that range
/// (wiring left out for v1 — the visual alone is what the user asked for).
///
/// Adapted from the Claude Code desktop dashboard's heatmap, but sized
/// for a phone width: 12 weeks × 7 days gives a comfortable square grid
/// at ~16 pt cells.
struct ActivityHeatmap: View {
    /// Sessions-per-day, keyed by `Date` truncated to midnight.
    let buckets: [Date: Int]
    /// How many weeks to display (most recent on the right).
    let weeks: Int

    private let cellSpacing: CGFloat = 4
    private let minCellSize: CGFloat = 12
    private let maxCellSize: CGFloat = 22

    /// Per-cell intensity ceiling. Uses the 90th-percentile (when there
    /// are enough samples) so a single monster-day doesn't crush every
    /// other day into the bottom intensity bucket — anything above this
    /// renders at full intensity but stops pulling the gradient with it.
    private var maxCount: Int {
        let allCounts = buckets.values.sorted()
        if allCounts.count >= 10 {
            let pIndex = Int(Double(allCounts.count - 1) * 0.9)
            return max(1, allCounts[pIndex])
        }
        return max(1, allCounts.max() ?? 1)
    }

    var body: some View {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        // Anchor: the most recent Sunday so columns are clean weeks.
        let weekday = cal.component(.weekday, from: today) // 1 = Sunday
        let daysSinceMonday = (weekday + 5) % 7 // Mon=0 ... Sun=6
        let mostRecentMonday = cal.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
        let maxCount = self.maxCount

        // Dynamic cell sizing — the prior fixed 14pt cell left a blank
        // right gutter on iPhone widths where the stats card was wider
        // than 12 * (14 + 4) ≈ 212pt. Read the parent's offered width
        // via GeometryReader and divide it evenly across the weeks so
        // the heatmap fills its column.
        GeometryReader { geo in
            let computed = (geo.size.width - cellSpacing * CGFloat(weeks - 1)) / CGFloat(weeks)
            let cellSize = min(maxCellSize, max(minCellSize, computed))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: cellSpacing) {
                    ForEach(0..<weeks, id: \.self) { weekIndex in
                        let weekStart = cal.date(
                            byAdding: .day,
                            value: -(weeks - 1 - weekIndex) * 7,
                            to: mostRecentMonday
                        ) ?? mostRecentMonday
                        VStack(spacing: cellSpacing) {
                            ForEach(0..<7, id: \.self) { dow in
                                let day = cal.date(byAdding: .day, value: dow, to: weekStart) ?? weekStart
                                cellView(for: day, today: today, count: buckets[day] ?? 0, max: maxCount, size: cellSize)
                            }
                        }
                    }
                }
                HStack(spacing: 6) {
                    Text("Less")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(SmoothieColor.textTertiary)
                    ForEach(0..<5, id: \.self) { step in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(legendColor(step: step))
                            .frame(width: cellSize * 0.8, height: cellSize * 0.6)
                    }
                    Text("More")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(SmoothieColor.textTertiary)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Outer height: 7 rows * cellSize + 6 gaps * spacing + 6 (VStack
        // spacing) + ~14 (legend row). Use a heuristic upper bound so
        // the GeometryReader gets vertical space; the actual grid sits
        // top-aligned inside it.
        .frame(height: maxCellSize * 7 + cellSpacing * 6 + 6 + 14)
    }

    private func cellView(for day: Date, today: Date, count: Int, max: Int, size: CGFloat) -> some View {
        let isFuture = day > today
        let intensity = isFuture ? -1.0 : intensity(count: count, max: max)
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color(for: intensity))
            .frame(width: size, height: size)
    }

    /// Map (0 ... max) to a normalised intensity in [0, 1]. We bin in
    /// quartiles so a single busy day doesn't make every other day
    /// barely visible.
    private func intensity(count: Int, max: Int) -> Double {
        guard count > 0, max > 0 else { return 0 }
        let ratio = Double(count) / Double(max)
        switch ratio {
        case 0:           return 0
        case ..<0.25:     return 0.25
        case ..<0.5:      return 0.5
        case ..<0.75:     return 0.75
        default:          return 1
        }
    }

    private func color(for intensity: Double) -> Color {
        // `-1` = future day. We render it transparent so the card
        // background shows through, keeping the visible grid uniform.
        // Previously this used `bgPrimary` which was *darker* than the
        // card surface and left a visible hole in the bottom-right
        // corner.
        if intensity < 0 { return Color.clear }
        if intensity == 0 { return SmoothieColor.bgChip }
        // Mono density signal: white from 10% to 60% opacity. The narrow
        // range keeps the card from screaming at the eye while still
        // reading as a clear high-vs-low gradient.
        return Color.white.opacity(0.10 + intensity * 0.50)
    }

    private func legendColor(step: Int) -> Color {
        if step == 0 { return SmoothieColor.bgChip }
        let intensity = Double(step) / 4.0
        return Color.white.opacity(0.10 + intensity * 0.50)
    }
}

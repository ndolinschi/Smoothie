import SwiftUI

/// Bottom-sheet detail view for the token budget. Header carries the
/// current "context window %" headline + the same segmented bar used in
/// the status footer; body lists every category with its color dot,
/// label, and token count. Presented from `StatusFooter` when the user
/// taps the percent ring; built on `SmoothieBottomSheet` so it gets the
/// standard drag-to-dismiss + safe-area handling for free.
struct ContextBudgetPanel: View {
    let snapshot: ContextSnapshotWire
    let onDismiss: () -> Void

    private var fillPct: Int {
        guard snapshot.max > 0 else { return 0 }
        return Int((Double(snapshot.total) / Double(snapshot.max)) * 100)
    }

    var body: some View {
        SmoothieBottomSheet(title: "Context Window", onDismiss: onDismiss) {
            VStack(alignment: .leading, spacing: 14) {
                headlineRow
                ContextBudgetBar(snapshot: snapshot, height: 6)
                Divider()
                    .background(SmoothieColor.strokeSoft)
                VStack(spacing: 6) {
                    ForEach(snapshot.breakdown) { cat in
                        categoryRow(cat)
                    }
                }
                Text("Estimated client view — provider-billed tokens may differ.")
                    .font(.system(size: 10))
                    .foregroundStyle(SmoothieColor.textTertiary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 20)
        }
    }

    private var headlineRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(fillPct)% Full")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SmoothieColor.textPrimary)
            Spacer()
            Text("~\(formatK(snapshot.total)) / \(formatK(snapshot.max)) Tokens")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(SmoothieColor.textSecondary)
        }
    }

    private func categoryRow(_ cat: ContextCategoryWire) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(ContextBudgetBar.color(for: cat.id))
                .frame(width: 8, height: 8)
            Text(cat.label)
                .font(.system(size: 13))
                .foregroundStyle(SmoothieColor.textPrimary)
            Spacer(minLength: 4)
            Text(formatK(cat.tokens))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(SmoothieColor.textSecondary)
        }
        .padding(.vertical, 4)
    }

    private func formatK(_ n: Int) -> String {
        if n >= 10_000 { return String(format: "%.1fK", Double(n) / 1000) }
        if n >= 1_000  { return String(format: "%.1fK", Double(n) / 1000) }
        return String(n)
    }
}

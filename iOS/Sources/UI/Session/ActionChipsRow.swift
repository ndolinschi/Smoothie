import SwiftUI

/// Chip row above the composer. Surfaces the Diff button when the session
/// has produced file edits. The prior "Plan" chip was removed in this
/// revision — Code/Plan mode is already switchable from the `ModeChip`
/// inside the composer, and showing the same toggle in two places
/// confused users. `onPlanTap` is preserved on the type signature so the
/// SessionView call site doesn't need rewiring; the closure is unused.
struct ActionChipsRow: View {
    let events: [SmoothieEventWire]
    let onPlanTap: () -> Void
    let onDiffTap: () -> Void

    private var fileEditCount: Int {
        events.filter { $0.type == .fileEdit }.count
    }

    var body: some View {
        if fileEditCount > 0 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    diffChip
                }
                .padding(.horizontal, 14)
            }
        }
    }

    private var diffChip: some View {
        Button(action: onDiffTap) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textPrimary)
                Text("Diff")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textPrimary)
                Text("\(fileEditCount) file\(fileEditCount == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(SmoothieColor.statusDone)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(SmoothieColor.bgCard, in: .capsule)
            .overlay(Capsule().strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

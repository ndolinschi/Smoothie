import SwiftUI

/// REF-5 chip row that sits above the composer in an active session. Three
/// chips: open the mode picker, see a coarse diff summary derived from
/// file-edit events, and a Create-PR placeholder marked v1.5.
struct ActionChipsRow: View {
    let events: [SmoothieEventWire]
    let onPlanTap: () -> Void
    let onDiffTap: () -> Void

    private var fileEditCount: Int {
        events.filter { $0.type == .fileEdit }.count
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                planChip
                diffChip
                prChip
            }
            .padding(.horizontal, 14)
        }
    }

    private var planChip: some View {
        Button(action: onPlanTap) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textPrimary)
                Text("Plan")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(SmoothieColor.bgCard, in: .capsule)
            .overlay(Capsule().strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
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
                if fileEditCount > 0 {
                    Text("\(fileEditCount) files")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(SmoothieColor.statusDone)
                } else {
                    Text("0")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(SmoothieColor.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(SmoothieColor.bgCard, in: .capsule)
            .overlay(Capsule().strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(fileEditCount == 0)
        .opacity(fileEditCount == 0 ? 0.5 : 1)
    }

    private var prChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SmoothieColor.textSecondary)
            Text("Create PR")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SmoothieColor.textSecondary)
            Text("v1.5")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(SmoothieColor.accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(SmoothieColor.accentSoft, in: .capsule)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(SmoothieColor.bgCard, in: .capsule)
        .overlay(Capsule().strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5))
        .opacity(0.7)
    }
}

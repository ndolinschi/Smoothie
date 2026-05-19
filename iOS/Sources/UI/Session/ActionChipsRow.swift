import SwiftUI

/// REF-5 chip row that sits above the composer in an active session. Two
/// chips today: open the mode picker, and (when the session has produced
/// file edits) a Diff button that opens DiffSheet for review + comments.
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
                if fileEditCount > 0 {
                    diffChip
                }
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

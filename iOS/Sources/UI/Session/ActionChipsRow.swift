import SwiftUI

/// REF-5 chip row that sits above the composer in an active session. Two
/// chips today: open the mode picker, and (when the session has produced
/// file edits) a Diff button that opens DiffSheet for review + comments.
struct ActionChipsRow: View {
    let events: [SmoothieEventWire]
    let state: SessionStateWire
    let onPlanTap: () -> Void
    let onDiffTap: () -> Void
    let onAbortTap: () -> Void

    private var fileEditCount: Int {
        events.filter { $0.type == .fileEdit }.count
    }

    private var isThinking: Bool {
        state == .starting || state == .thinking
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if isThinking {
                    abortChip
                }
                planChip
                if fileEditCount > 0 {
                    diffChip
                }
            }
            .padding(.horizontal, 14)
        }
    }

    private var abortChip: some View {
        Button(action: onAbortTap) {
            HStack(spacing: 6) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Abort")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(SmoothieColor.statusErr.opacity(0.85), in: .capsule)
        }
        .buttonStyle(.plain)
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

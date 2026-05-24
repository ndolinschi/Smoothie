import SwiftUI

/// P29 §8 — Composer action chips row. Surfaces three context-aware
/// affordances directly above the message input:
///
///   • **Plan** — visible while a plan-mode preamble is staged.
///     Tapping opens a small popover with the buffered instruction +
///     a Clear button.
///   • **Diff +X −Y** — visible once the session has produced any
///     fileEdit. Counts aggregate every fileEdit event in the session.
///     Tap → opens the existing `DiffSheet`.
///   • **Create PR** — visible only when both: the session has
///     produced fileEdits AND the daemon precheck (`/git/pr-ready`)
///     confirmed `gh` is installed + authenticated. Tap opens the
///     `CreatePRSheet`.
///
/// The signatures are non-optional on the callsite so SessionView can
/// thread state without conditional plumbing. Each chip's visibility
/// is decided inside this view.
struct ActionChipsRow: View {
    let events: [SmoothieEventWire]
    /// True while `SessionLiveStore.pendingMode` holds a buffered
    /// preamble that will prepend the user's next message.
    let hasPendingPlanPreamble: Bool
    /// Result of the precheck (`gh --version` + `gh auth status`) on
    /// the daemon. `nil` = precheck hasn't run yet (chip hidden);
    /// `false` = explicitly not ready (chip hidden); `true` = chip
    /// shown when there are fileEdits in the session.
    let prReady: Bool?
    let onPlanTap: () -> Void
    let onClearPlan: () -> Void
    let onDiffTap: () -> Void
    let onCreatePRTap: () -> Void

    @State private var showingPlanPopover: Bool = false

    private var totals: (added: Int, removed: Int, files: Int) {
        var added = 0
        var removed = 0
        var files = 0
        for event in events where event.type == .fileEdit {
            if let entry = DiffEntry(event: event) {
                let rows = entry.diffRows()
                added += rows.filter { $0.kind == .addition }.count
                removed += rows.filter { $0.kind == .deletion }.count
                files += 1
            }
        }
        return (added, removed, files)
    }

    private var anyChipVisible: Bool {
        hasPendingPlanPreamble || totals.files > 0
    }

    var body: some View {
        if anyChipVisible {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if hasPendingPlanPreamble {
                        planChip
                    }
                    if totals.files > 0 {
                        diffChip
                        if prReady == true {
                            createPRChip
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
        }
    }

    // MARK: - Plan chip

    private var planChip: some View {
        Button {
            showingPlanPopover = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SmoothieColor.modePlan)
                Text("Plan")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(SmoothieColor.modePlan.opacity(0.12), in: .capsule)
            .overlay(Capsule().strokeBorder(SmoothieColor.modePlan.opacity(0.35), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPlanPopover, arrowEdge: .bottom) {
            planPopover
        }
    }

    private var planPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.clipboard")
                    .foregroundStyle(SmoothieColor.modePlan)
                Text("Plan-mode preamble staged")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text("Your next message will be prefixed with a plan-mode instruction. Send the message to use it, or clear it now.")
                .font(.system(size: 12))
                .foregroundStyle(SmoothieColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(role: .destructive) {
                    onClearPlan()
                    showingPlanPopover = false
                } label: {
                    Text("Clear")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
        }
        .padding(14)
        .frame(width: 280)
        .presentationCompactAdaptation(.popover)
    }

    // MARK: - Diff chip

    private var diffChip: some View {
        Button(action: onDiffTap) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textPrimary)
                Text("Diff")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textPrimary)
                if totals.added > 0 {
                    Text("+\(totals.added)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(SmoothieColor.statusDone)
                }
                if totals.removed > 0 {
                    Text("−\(totals.removed)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(SmoothieColor.statusErr)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(SmoothieColor.bgCard, in: .capsule)
            .overlay(Capsule().strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Create PR chip

    private var createPRChip: some View {
        Button(action: onCreatePRTap) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.pull")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SmoothieColor.accent)
                Text("Create PR")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(SmoothieColor.accent.opacity(0.10), in: .capsule)
            .overlay(Capsule().strokeBorder(SmoothieColor.accent.opacity(0.35), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

/// Generic capsule chip — the standard "[icon] [label] [trailing]" pill
/// shape used by ActionChipsRow, ModeChip, RepoChip, and the filter
/// capsules on HomeView. Each previously inlined the same HStack +
/// bgCard + capsule + strokeSoft pattern; this centralises it.
///
/// Usage:
/// ```
/// SmoothieChip(systemName: "checklist", label: "Plan") {
///     showModeSheet = true
/// }
///
/// SmoothieChip(label: "All", trailing: "12", active: true) { … }
/// ```
struct SmoothieChip: View {
    /// Optional leading SF Symbol.
    var systemName: String? = nil
    /// Optional tint for the leading symbol — defaults to the primary
    /// text colour to match label.
    var systemColor: Color = SmoothieColor.textPrimary
    let label: String
    /// Optional trailing affordance (count badge, chevron-down, etc.)
    /// rendered as monospaced caption.
    var trailing: String? = nil
    /// Active state controls the background fill — coral-soft when
    /// active, bgCard otherwise. Matches the All/Completed filter
    /// behaviour on HomeView.
    var active: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        let content = HStack(spacing: 6) {
            if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(systemColor)
            }
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? SmoothieColor.textPrimary : SmoothieColor.textSecondary)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(active ? SmoothieColor.textPrimary.opacity(0.55) : SmoothieColor.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(active ? SmoothieColor.accentSoft : SmoothieColor.bgCard, in: .capsule)
        .overlay(
            Capsule().strokeBorder(
                active ? SmoothieColor.accent.opacity(0.5) : SmoothieColor.strokeSoft,
                lineWidth: 0.5
            )
        )

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

import SwiftUI

/// Cloud-icon capsule that sits just below the navigation bar on the
/// session screen (P25.c). Mirrors the Claude Code mobile reference's
/// "Default" environment pill.
///
/// Smoothie doesn't have a separate environment concept yet — the label
/// is wired to the session mode for now, and tapping opens the existing
/// mode sheet. The semantics can split later (env vs. mode) without
/// changing the visual treatment.
struct EnvPill: View {
    let label: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: SmoothieMetrics.space6) {
                Image(systemName: "cloud")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SmoothieColor.envPillIcon)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SmoothieColor.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, SmoothieMetrics.space12)
            .padding(.vertical, SmoothieMetrics.space6)
            .background(SmoothieColor.envPillBg, in: Capsule())
            .overlay(
                Capsule().strokeBorder(SmoothieColor.envPillStroke, lineWidth: 0.5)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Environment: \(label). Tap to change mode.")
    }
}

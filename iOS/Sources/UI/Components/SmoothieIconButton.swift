import SwiftUI

/// Circular icon button — the dark-coral aesthetic's standard 36 pt /
/// 44 pt tappable circle (hamburger, +, ellipsis, close-X). Centralises
/// the bgCard + strokeSoft + system-symbol shape that was duplicated in
/// six places before this extraction (audit P24.c C4).
///
/// Usage:
/// ```
/// SmoothieIconButton(systemName: "line.3.horizontal") { presentingPairings = true }
/// SmoothieIconButton(systemName: "ellipsis", size: 36) { showMenu = true }
/// ```
struct SmoothieIconButton: View {
    let systemName: String
    var size: CGFloat = SmoothieMetrics.topCircle
    /// SwiftUI weight applied to the SF Symbol. Defaults to `.semibold`
    /// which reads well at 36-44 pt on dark surfaces.
    var weight: Font.Weight = .semibold
    /// Optional tint override — defaults to `textPrimary`. Pass
    /// `.accent` for coral-fill primary actions (rare; the standard
    /// coral FAB has its own treatment).
    var foreground: Color = SmoothieColor.textPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: weight))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(SmoothieColor.bgCard, in: .circle)
                .overlay(
                    Circle().strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

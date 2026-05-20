import SwiftUI

/// Uppercase tracking-0.6 label used as a section header across
/// DashboardHeader, NewSessionView, ComposerMenu, ManualPairView, and
/// EventRow's input-fields detail block. Replaces three inline
/// duplicates with one place to tune the typography.
///
/// Usage:
/// ```
/// SmoothieSectionLabel("Sessions")
/// SmoothieSectionLabel("CLI", weight: .heavy)
/// ```
struct SmoothieSectionLabel: View {
    let text: String
    var size: CGFloat = 11
    var weight: Font.Weight = .bold
    /// Casing is upper-cased automatically; pass the value in any case
    /// and we render the SwiftUI-locale-correct uppercase form.
    var uppercased: Bool = true

    init(_ text: String, size: CGFloat = 11, weight: Font.Weight = .bold, uppercased: Bool = true) {
        self.text = text
        self.size = size
        self.weight = weight
        self.uppercased = uppercased
    }

    var body: some View {
        Text(uppercased ? text.uppercased() : text)
            .font(.system(size: size, weight: weight))
            .tracking(0.6)
            .foregroundStyle(SmoothieColor.textTertiary)
    }
}

import SwiftUI

/// Standard bottom-sheet row: leading 32pt glyph container, title + optional
/// subtitle, optional trailing checkmark. Used by ModeSheet, AttachSheet,
/// PairingsSheet and other REF-2 family sheets.
struct SheetRow: View {
    let glyph: String
    let glyphColor: Color
    let glyphBackground: Color
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    init(
        glyph: String,
        glyphColor: Color = SmoothieColor.textPrimary,
        glyphBackground: Color = SmoothieColor.bgGlyph,
        title: String,
        subtitle: String? = nil,
        isSelected: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.glyph = glyph
        self.glyphColor = glyphColor
        self.glyphBackground = glyphBackground
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: glyph)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(glyphColor)
                    .frame(width: SmoothieMetrics.glyphTile, height: SmoothieMetrics.glyphTile)
                    .background(glyphBackground, in: .rect(cornerRadius: SmoothieMetrics.cornerSm))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SmoothieColor.textPrimary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(SmoothieColor.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(hex: 0x2563EB))
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }
}

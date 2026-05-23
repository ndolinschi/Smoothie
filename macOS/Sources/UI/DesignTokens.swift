import SwiftUI
import AppKit

/// macOS design tokens — vocabulary parity with the iOS
/// `SmoothieColor`/`SmoothieMetrics` enums (P26.a). Where iOS uses a
/// fixed dark hex (the iOS app is locked dark), Gin maps to system
/// semantic colors so the menubar popover stays light/dark adaptive.
/// Coral accent and status hues are pinned to the same hex as iOS so
/// the products read as one.
enum SmoothieColor {
    // MARK: - Text (system-adaptive)
    static let textPrimary   = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary  = Color(nsColor: .tertiaryLabelColor)
    static let textDim       = Color(nsColor: .quaternaryLabelColor)

    // MARK: - Surfaces (system-adaptive)
    static let surface0      = Color(nsColor: .windowBackgroundColor)
    static let surface1      = Color(nsColor: .controlBackgroundColor)
    static let surface2      = Color(nsColor: .underPageBackgroundColor)
    static let surface3      = Color(nsColor: .controlBackgroundColor)

    // MARK: - Strokes (system-adaptive)
    static let stroke        = Color(nsColor: .separatorColor)
    static let strokeSoft    = Color.primary.opacity(0.06)

    // MARK: - Accent (pinned to iOS hex)
    static let accent        = Color(hex: 0xED7C5C)
    static let accentSoft    = Color(hex: 0xED7C5C).opacity(0.18)

    // MARK: - Status (pinned to iOS hex)
    static let statusThinking = Color(hex: 0x3B82F6)
    static let statusWaiting  = Color(hex: 0xFB923C)
    static let statusDone     = Color(hex: 0x34D399)
    static let statusErr      = Color(hex: 0xEF4444)
    static let statusIdle     = Color(nsColor: .tertiaryLabelColor)

    // MARK: - Chip / pill (system-adaptive)
    static let chipBg         = surface1
    static let chipStroke     = strokeSoft
    static let chipLabel      = textPrimary
}

enum SmoothieMetrics {
    static let cornerLg: CGFloat = 14
    static let cornerMd: CGFloat = 10
    static let cornerSm: CGFloat = 8
    static let cornerXS: CGFloat = 6

    static let space2:  CGFloat = 2
    static let space4:  CGFloat = 4
    static let space6:  CGFloat = 6
    static let space8:  CGFloat = 8
    static let space10: CGFloat = 10
    static let space12: CGFloat = 12
    static let space14: CGFloat = 14
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24

    /// Width of the menubar popover content. Centralised so the full-QR
    /// sheet and any future expanded view can read the same scale.
    static let popoverWidth: CGFloat = 340
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

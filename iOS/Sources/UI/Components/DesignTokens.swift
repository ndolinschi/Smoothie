import SwiftUI

/// Centralised design tokens shared across every Smoothie surface. P16 swaps
/// the prior Liquid-Glass aesthetic for a flat, dark, coral-accented look
/// modelled after the reference screenshots. New surfaces should read tokens
/// from here instead of hard-coding `.white.opacity(...)` or hex literals.
enum SmoothieColor {
    static let bgPrimary     = Color(hex: 0x0E0E0E)
    static let bgCard        = Color(hex: 0x141414)
    static let bgChip        = Color(hex: 0x1A1A1A)
    static let bgSheet       = Color(hex: 0x161616)
    static let bgGlyph       = Color(hex: 0x2A2A2A)

    static let stroke        = Color.white.opacity(0.12)
    static let strokeSoft    = Color.white.opacity(0.06)
    static let strokeDashed  = Color.white.opacity(0.20)

    static let accent        = Color(hex: 0xED7C5C)
    static let accentSoft    = Color(hex: 0xED7C5C).opacity(0.18)

    static let textPrimary   = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary  = Color.white.opacity(0.40)
    static let textDim       = Color.white.opacity(0.25)

    static let modeCode      = Color(hex: 0xA78BFA)
    static let modePlan      = Color(hex: 0x60A5FA)

    static let statusThinking = Color(hex: 0x3B82F6)
    static let statusWaiting  = Color(hex: 0xFB923C)
    static let statusDone     = Color(hex: 0x34D399)
    static let statusErr      = Color(hex: 0xEF4444)
}

enum SmoothieMetrics {
    static let cornerLg: CGFloat = 18
    static let cornerMd: CGFloat = 14
    static let cornerSm: CGFloat = 10
    static let cornerXS: CGFloat = 6

    static let topCircle: CGFloat = 44
    static let glyphTile: CGFloat = 32
    static let sendButton: CGFloat = 36

    static let rowPaddingH: CGFloat = 14
    static let rowPaddingV: CGFloat = 12
}

extension Color {
    /// Hex initialiser for design tokens. RGB only (no alpha) — use
    /// `.opacity(_)` for translucency.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

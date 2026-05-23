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

    // MARK: - P24.c additions

    /// Blue used for selection checkmarks on sheet rows (matches the
    /// reference's Tailwind-blue-600).
    static let linkBlue       = Color(hex: 0x2563EB)

    /// Tile tints for `SheetRow` glyph backgrounds. Each pairs with a
    /// foreground token (modeCode / modePlan / accent / statusDone /
    /// statusErr) but renders the small 32-pt square behind the glyph.
    static let glyphModeCode  = Color(hex: 0x1F1F2E)
    static let glyphModePlan  = Color(hex: 0x1F2A3E)
    static let glyphModeRun   = Color(hex: 0x2E1717)
    static let glyphAmber     = Color(hex: 0xFBBF24)
    static let glyphAmberSoft = Color(hex: 0x2A2415)
    static let glyphGreenSoft = Color(hex: 0x152A22)

    /// Markdown code-block surfaces. `codeBg` for fenced blocks,
    /// `codeBgDim` for inline `code` spans.
    static let codeBg         = Color.white.opacity(0.07)
    static let codeBgDim      = Color.white.opacity(0.04)

    /// Subtle screen veil used by dashed banners / decorative surfaces.
    static let overlayVeil    = Color.white.opacity(0.02)

    // MARK: - P25.a surface tiers
    //
    // Named tiers introduced by the iOS design refresh. Existing
    // tokens above (bgPrimary / bgCard / bgChip / bgSheet) remain the
    // source of truth — these are aliases that let new surfaces read
    // a semantic name (page vs. card vs. chip vs. popover) without
    // needing to know which hex backs them today. `surface3` is the
    // one new value: a slightly lighter popover background used by
    // the centered model dropdown and similar overlays.

    static let surface0      = bgPrimary
    static let surface1      = bgCard
    static let surface2      = bgChip
    static let surface3      = Color(hex: 0x1C1C1C)

    // MARK: - P25.a chip + pill styles

    static let chipBg         = bgChip
    static let chipBgPressed  = Color(hex: 0x222222)
    static let chipStroke     = stroke
    static let chipLabel      = textPrimary

    static let envPillBg      = bgChip
    static let envPillIcon    = textSecondary
    static let envPillStroke  = strokeSoft

    // MARK: - P25.a menu / dropdown

    static let menuBg         = surface3
    static let menuStroke     = stroke
    static let menuRowHover   = Color.white.opacity(0.04)
    static let menuDivider    = strokeSoft
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

    // MARK: - P25.a spacing scale
    //
    // Granular scale introduced so later phases (chips row, suggestion
    // chips, env pill, dropdown) can read a named value instead of
    // sprinkling literals. The existing rowPadding* values stay as
    // the canonical row inset; these are for inter-element gaps.

    static let space2:  CGFloat = 2
    static let space4:  CGFloat = 4
    static let space6:  CGFloat = 6
    static let space8:  CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
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

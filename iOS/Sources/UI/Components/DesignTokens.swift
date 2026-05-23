import SwiftUI

/// Centralised design tokens shared across every Smoothie surface. P16 swapped
/// the prior Liquid-Glass aesthetic for a flat, dark surface; P25 retires the
/// coral accent in favour of a mono (white-on-#0E0E0E) palette modelled after
/// Cursor's mobile session view. New surfaces should read tokens from here
/// instead of hard-coding `.white.opacity(...)` or hex literals. Active states
/// use `accent` (white) for "pressable primary action" and `linkBlue` for
/// "current selection in a list" — two-axis convention to avoid conflation
/// after coral removal.
enum SmoothieColor {
    static let bgPrimary     = Color(hex: 0x0E0E0E)
    static let bgCard        = Color(hex: 0x141414)
    static let bgChip        = Color(hex: 0x1A1A1A)
    static let bgSheet       = Color(hex: 0x161616)
    static let bgGlyph       = Color(hex: 0x2A2A2A)

    static let stroke        = Color.white.opacity(0.12)
    static let strokeSoft    = Color.white.opacity(0.06)
    static let strokeDashed  = Color.white.opacity(0.20)

    /// Primary action fill / "pressable" hue. Reassigned from coral (#ED7C5C)
    /// in P25; existing call sites continue to compile against the same token.
    static let accent        = Color.white
    static let accentSoft    = Color.white.opacity(0.10)
    /// Outline for "this is the currently active variant" (e.g. selected mode
    /// chip). Replaces the prior `accent.opacity(0.5)` pattern.
    static let activeBorder  = Color.white.opacity(0.30)
    /// Foreground colour that sits ON TOP of an `accent` fill. With the P25
    /// mono palette, `accent` is white — so any text or icon previously
    /// rendered as `.white` over an accent button now needs `onAccent`
    /// (`bgPrimary`) to remain visible. Use this instead of `.white` whenever
    /// the background is `SmoothieColor.accent` (or `accent.opacity(...)`).
    static let onAccent      = Color(hex: 0x0E0E0E)

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

    /// Padding for `ToolCallCard` header + body blocks. Slightly tighter
    /// than `rowPadding*` because the card already has a visible border.
    static let toolCardPaddingH: CGFloat = 14
    static let toolCardPaddingV: CGFloat = 12
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

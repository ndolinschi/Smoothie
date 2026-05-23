import SwiftUI

/// Centralised design tokens shared across every Smoothie surface.
///
/// History: P16 retired Liquid Glass for a flat dark palette; P25 replaced
/// the coral accent with a mono (white-on-#0E0E0E) palette; **P27.d makes
/// the surface + text tokens adaptive** so the app can follow the system
/// light/dark setting. Pinned hex stays for the status / mode / code-block
/// accents — those read on both backgrounds.
///
/// New surfaces should read tokens from here instead of hard-coding
/// `.primary.opacity(...)` or hex literals. Active states use `accent` for
/// "pressable primary action" and `linkBlue` for "current selection in a
/// list" — a two-axis convention to avoid conflation.
enum SmoothieColor {
    // MARK: - Surfaces (adaptive, P27.d)

    static let bgPrimary     = Color(uiColor: .systemBackground)
    static let bgCard        = Color(uiColor: .secondarySystemBackground)
    static let bgChip        = Color(uiColor: .tertiarySystemBackground)
    static let bgSheet       = Color(uiColor: .secondarySystemGroupedBackground)
    static let bgGlyph       = Color(uiColor: .quaternarySystemFill)

    // MARK: - Strokes (adaptive)

    static let stroke        = Color.primary.opacity(0.12)
    static let strokeSoft    = Color.primary.opacity(0.06)
    static let strokeDashed  = Color.primary.opacity(0.20)

    // MARK: - Primary action / accent (adaptive)

    /// Primary action fill / "pressable" hue. Black in light mode, white in
    /// dark mode. Used as a background fill for buttons; pair with
    /// `onAccent` for the foreground.
    static let accent        = Color.primary
    static let accentSoft    = Color.primary.opacity(0.10)
    /// Outline for "this is the currently active variant" (e.g. selected mode
    /// chip).
    static let activeBorder  = Color.primary.opacity(0.30)
    /// Foreground colour that sits ON TOP of an `accent` fill. Inverts with
    /// the system mode so contrast always holds: light surface in light mode
    /// (over a dark accent), dark surface in dark mode (over a white accent).
    static let onAccent      = Color(uiColor: .systemBackground)

    // MARK: - Text (adaptive)

    static let textPrimary   = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary  = Color(uiColor: .tertiaryLabel)
    static let textDim       = Color(uiColor: .quaternaryLabel)

    // MARK: - Mode glyphs (pinned hex — readable on both surfaces)

    static let modeCode      = Color(hex: 0xA78BFA)
    static let modePlan      = Color(hex: 0x60A5FA)

    // MARK: - Status (pinned hex)

    static let statusThinking = Color(hex: 0x3B82F6)
    static let statusWaiting  = Color(hex: 0xFB923C)
    static let statusDone     = Color(hex: 0x34D399)
    static let statusErr      = Color(hex: 0xEF4444)

    // MARK: - Sheet checkmark + tile tints (P24.c)

    /// Blue used for selection checkmarks on sheet rows (Tailwind-blue-600).
    static let linkBlue       = Color(hex: 0x2563EB)

    /// Tile tints for `SheetRow` glyph backgrounds. Each pairs with a
    /// foreground token (modeCode / modePlan / accent / statusDone /
    /// statusErr) but renders the small 32-pt square behind the glyph.
    /// These were designed for the dark palette — they read as quiet
    /// muted blocks in dark mode and as accent-tinted blocks in light
    /// mode (asset-catalog overrides would be a cleaner follow-up).
    static let glyphModeCode  = Color(hex: 0x1F1F2E)
    static let glyphModePlan  = Color(hex: 0x1F2A3E)
    static let glyphModeRun   = Color(hex: 0x2E1717)
    static let glyphAmber     = Color(hex: 0xFBBF24)
    static let glyphAmberSoft = Color(hex: 0x2A2415)
    static let glyphGreenSoft = Color(hex: 0x152A22)

    // MARK: - Code-block surfaces (adaptive)

    /// Markdown code-block surfaces. `codeBg` for fenced blocks,
    /// `codeBgDim` for inline `code` spans.
    static let codeBg         = Color.primary.opacity(0.07)
    static let codeBgDim      = Color.primary.opacity(0.04)

    /// Subtle screen veil used by dashed banners / decorative surfaces.
    static let overlayVeil    = Color.primary.opacity(0.02)

    // MARK: - P25.a surface tiers

    static let surface0      = bgPrimary
    static let surface1      = bgCard
    static let surface2      = bgChip
    static let surface3      = Color(uiColor: .tertiarySystemGroupedBackground)

    // MARK: - P25.a chip + pill styles

    static let chipBg         = bgChip
    static let chipBgPressed  = Color.primary.opacity(0.08)
    static let chipStroke     = stroke
    static let chipLabel      = textPrimary

    static let envPillBg      = bgChip
    static let envPillIcon    = textSecondary
    static let envPillStroke  = strokeSoft

    // MARK: - P25.a menu / dropdown

    static let menuBg         = surface3
    static let menuStroke     = stroke
    static let menuRowHover   = Color.primary.opacity(0.04)
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

    /// Padding for `ToolCallCard` header + body blocks. Slightly tighter
    /// than `rowPadding*` because the card already has a visible border.
    static let toolCardPaddingH: CGFloat = 14
    static let toolCardPaddingV: CGFloat = 12

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

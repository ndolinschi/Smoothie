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
    // MARK: - Surfaces (adaptive, warm "Claude" palette)
    //
    // Claude-app-style warm neutrals replace the cold system grays:
    // cream paper in light mode, warm charcoal in dark mode. Each pair
    // is (light, dark).

    static let bgPrimary     = dynamic(light: 0xFAF9F5, dark: 0x262624)
    static let bgCard        = dynamic(light: 0xFFFFFF, dark: 0x30302E)
    static let bgChip        = dynamic(light: 0xF0EEE6, dark: 0x393937)
    static let bgSheet       = dynamic(light: 0xFAF9F5, dark: 0x30302E)
    static let bgGlyph       = dynamic(light: 0xEAE8E1, dark: 0x3A3A38)

    // MARK: - Strokes (adaptive)

    static let stroke        = Color.primary.opacity(0.12)
    static let strokeSoft    = Color.primary.opacity(0.06)
    static let strokeDashed  = Color.primary.opacity(0.20)

    // MARK: - Primary action / accent

    /// Primary action fill / "pressable" hue — Claude's terracotta.
    /// Reads on both the cream and charcoal surfaces, so it's pinned
    /// rather than adaptive. Pair with `onAccent` for the foreground.
    static let accent        = Color(hex: 0xD97757)
    static let accentSoft    = Color(hex: 0xD97757).opacity(0.15)
    /// Outline for "this is the currently active variant" (e.g. selected mode
    /// chip).
    static let activeBorder  = Color.primary.opacity(0.30)
    /// Foreground colour that sits ON TOP of an `accent` fill. White holds
    /// contrast on terracotta in both modes.
    static let onAccent      = Color.white

    // MARK: - Chat bubbles

    /// User-authored message bubble. Claude-style quiet warm gray —
    /// the conversation's loud color is reserved for the send button,
    /// not the user's own words.
    static let bubbleUser    = dynamic(light: 0xF0EEE6, dark: 0x393937)

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

    // MARK: - CLI brand colors (P29 — pinned hex)
    //
    // Per-CLI brand tints used by the provider strip on Home and the
    // top-line accent on `ToolCallCard`. Chosen to be visually distinct
    // from each other AND from the status/mode tokens above so the
    // provider chip dots don't collide with semantic meaning.

    static let brandClaude    = Color(hex: 0xED7C5C)   // Anthropic coral
    static let brandCodex     = Color(hex: 0x10A37F)   // OpenAI deep teal
    static let brandCursor    = Color(hex: 0x6366F1)   // Cursor indigo
    static let brandGemini    = Color(hex: 0x4285F4)   // Google blue
    static let brandOpenCode  = Color(hex: 0xF97316)   // OpenCode orange

    /// Returns the brand tint for a CLI. Falls back to `textSecondary`
    /// for `.unknown` / `.antigravity` — both are intentionally
    /// neutral (Antigravity is hidden from the picker; unknown is the
    /// forward-compat sentinel from the wire decoder).
    static func brand(for cli: CLIWire) -> Color {
        switch cli {
        case .claudeCode:  return brandClaude
        case .codex:       return brandCodex
        case .cursor:      return brandCursor
        case .gemini:      return brandGemini
        case .openCode:    return brandOpenCode
        case .antigravity: return textSecondary
        case .unknown:     return textSecondary
        }
    }

    // MARK: - Sheet checkmark + tile tints (P24.c)

    /// Blue used for selection checkmarks on sheet rows (Tailwind-blue-600).
    static let linkBlue       = Color(hex: 0x2563EB)

    /// Tile tints for `SheetRow` glyph backgrounds. Each pairs with a
    /// foreground token (modeCode / modePlan / accent / statusDone /
    /// statusErr) but renders the small 32-pt square behind the glyph.
    /// P27.k — derived from the matching foreground at 18% opacity so
    /// the tile is a soft tint of the glyph colour in both modes
    /// rather than a fixed dark block that turned into a near-black
    /// square on a white card in light mode.
    static let glyphModeCode  = modeCode.opacity(0.18)
    static let glyphModePlan  = modePlan.opacity(0.18)
    static let glyphModeRun   = statusErr.opacity(0.18)
    static let glyphAmber     = Color(hex: 0xFBBF24)
    static let glyphAmberSoft = Color(hex: 0xFBBF24).opacity(0.18)
    static let glyphGreenSoft = statusDone.opacity(0.18)

    // MARK: - Code-block surfaces (adaptive)

    /// Markdown code-block surfaces. `codeBg` for fenced blocks,
    /// `codeBgDim` for inline `code` spans. Warm pairs matching the
    /// Claude palette: fenced blocks sit a step darker than the body in
    /// dark mode (and a step warmer in light) so code reads as its own
    /// surface.
    static let codeBg         = dynamic(light: 0xF0EEE6, dark: 0x1F1E1B)
    static let codeBgDim      = dynamic(light: 0xEAE8E1, dark: 0x393937)

    /// Subtle screen veil used by dashed banners / decorative surfaces.
    static let overlayVeil    = Color.primary.opacity(0.02)

    // MARK: - P25.a surface tiers

    static let surface0      = bgPrimary
    static let surface1      = bgCard
    static let surface2      = bgChip
    static let surface3      = dynamic(light: 0xEAE8E1, dark: 0x3A3A38)

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
    // Corner radius scale. The named tiers cover every radius the app
    // actually uses; the numeric aliases exist so the many `cornerRadius: 12`
    // / `16` call sites map to a token without a behaviour change.
    static let cornerXL: CGFloat = 22   // hero / large sheets
    static let cornerLg: CGFloat = 18
    static let cornerCard: CGFloat = 16 // cards, panels, message blocks
    static let cornerMd: CGFloat = 14
    static let cornerRow: CGFloat = 12  // list rows, picker rows
    static let cornerSm: CGFloat = 10
    static let cornerChip: CGFloat = 8  // small inline tiles
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
    static let space10: CGFloat = 10
    static let space12: CGFloat = 12
    static let space14: CGFloat = 14
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
}

// MARK: - Elevation (Claude-style soft shadows)

/// Card elevation tiers. Claude's mobile surfaces sit on a soft, low,
/// warm-tinted shadow rather than the flat hairline-only look we had.
/// Black at low opacity reads correctly on both the cream and charcoal
/// backgrounds; SwiftUI composites it under the rounded card shape.
enum SmoothieShadow {
    struct Spec {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }
    /// Resting cards (stat tiles, tool cards, suggestion pills).
    static let card  = Spec(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
    /// Raised / floating surfaces (jump-to-latest pill, popovers).
    static let float = Spec(color: Color.black.opacity(0.16), radius: 14, x: 0, y: 6)
}

extension View {
    /// Apply a named elevation shadow. Use `.card` for resting surfaces,
    /// `.float` for things that hover above the content.
    func smoothieShadow(_ spec: SmoothieShadow.Spec = SmoothieShadow.card) -> some View {
        shadow(color: spec.color, radius: spec.radius, x: spec.x, y: spec.y)
    }

    /// Standard Smoothie card surface: rounded fill + hairline stroke +
    /// soft elevation, so every card reads the same. Replaces the
    /// `.background(bgCard, in: .rect(cornerRadius: 12/14/16))` +
    /// `.overlay(RoundedRectangle…strokeBorder)` pair that was copy-pasted
    /// across ~20 sites.
    func smoothieCard(
        cornerRadius: CGFloat = SmoothieMetrics.cornerCard,
        fill: Color = SmoothieColor.bgCard,
        stroke: Color = SmoothieColor.strokeSoft,
        elevated: Bool = true
    ) -> some View {
        self
            .background(fill, in: .rect(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(stroke, lineWidth: 0.5)
            )
            .smoothieShadow(elevated ? SmoothieShadow.card : SmoothieShadow.Spec(color: .clear, radius: 0, x: 0, y: 0))
    }
}

// MARK: - Press feedback

/// Tactile press feedback for tappable surfaces — a subtle scale + dim,
/// matching the way Claude's controls respond. Apply via `.buttonStyle(.smoothiePress)`.
struct SmoothiePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SmoothiePressStyle {
    static var smoothiePress: SmoothiePressStyle { SmoothiePressStyle() }
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

extension SmoothieColor {
    /// Light/dark hex pair resolved through UIKit's trait system so the
    /// warm palette follows the user's theme override (SmoothieThemed
    /// re-applies `preferredColorScheme` per presentation tree).
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                blue: CGFloat(hex & 0xFF) / 255.0,
                alpha: 1
            )
        })
    }
}

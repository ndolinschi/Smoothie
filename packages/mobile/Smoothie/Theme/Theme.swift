import SwiftUI

/// Visual tokens for Smoothie. Dark, near-black palette with green accent. Surfaces
/// use native materials (`.regularMaterial`, `.ultraThinMaterial`) for the iOS 18+
/// glassmorphism look, with `.glassEffect()` Liquid Glass on iOS 26+ where available.
enum Theme {
    // Backdrop colors — these sit under the materials and give the glass something to refract.
    static let bg          = Color(red: 0.04, green: 0.04, blue: 0.05)
    static let bgDeep      = Color(red: 0.015, green: 0.015, blue: 0.02)

    // Accent + signal colors
    static let accent      = Color(red: 0.30, green: 1.00, blue: 0.66)   // mint-green
    static let accentSoft  = Color(red: 0.30, green: 1.00, blue: 0.66).opacity(0.18)
    static let waiting     = Color(red: 1.00, green: 0.78, blue: 0.20)   // amber
    static let waitingSoft = Color(red: 1.00, green: 0.78, blue: 0.20).opacity(0.18)
    static let error       = Color(red: 1.00, green: 0.38, blue: 0.35)
    static let errorSoft   = Color(red: 1.00, green: 0.38, blue: 0.35).opacity(0.18)
    static let thinking    = Color(red: 0.45, green: 0.74, blue: 1.00)
    static let thinkingSoft = Color(red: 0.45, green: 0.74, blue: 1.00).opacity(0.18)

    // Text. Use SwiftUI's `.primary`/`.secondary` for vibrancy over materials when possible —
    // these explicit colors are for places where vibrancy would lose too much contrast.
    static let text        = Color.white
    static let textMuted   = Color.white.opacity(0.62)
    static let textDim     = Color.white.opacity(0.36)
    static let textFaint   = Color.white.opacity(0.18)

    // Strokes that catch light along glass edges
    static let glassStroke      = Color.white.opacity(0.12)
    static let glassStrokeSoft  = Color.white.opacity(0.06)

    enum Radius {
        static let pill: CGFloat = 999
        static let card: CGFloat = 18
        static let row: CGFloat = 14
        static let input: CGFloat = 14
        static let button: CGFloat = 14
    }
}

// MARK: - Backdrop

/// Animated subtle mesh gradient that sits under all glass surfaces. iOS 18+ uses
/// the new `MeshGradient` for a soft, organic gradient; iOS earlier ones fall back
/// to a radial gradient (we ship iOS 18 as minimum, but the fallback is safe).
struct BackdropView: View {
    var body: some View {
        ZStack {
            Theme.bgDeep.ignoresSafeArea()
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    .init(0.0, 0.0), .init(0.5, 0.0), .init(1.0, 0.0),
                    .init(0.0, 0.5), .init(0.55, 0.45), .init(1.0, 0.5),
                    .init(0.0, 1.0), .init(0.5, 1.0), .init(1.0, 1.0),
                ],
                colors: [
                    Theme.bgDeep,                              Theme.bgDeep,                 Theme.bgDeep,
                    Theme.accent.opacity(0.10),                Theme.bg,                     Theme.thinking.opacity(0.08),
                    Theme.bgDeep,                              Theme.bgDeep,                 Theme.bgDeep,
                ]
            )
            .ignoresSafeArea()
            .blur(radius: 60)
            .opacity(0.9)
        }
    }
}

// MARK: - Glass surfaces

/// A card-shaped glass surface. Uses iOS 26 Liquid Glass when available, falls back
/// to `.regularMaterial` on iOS 18–25.
struct GlassCard<Content: View>: View {
    private let cornerRadius: CGFloat
    private let content: Content

    init(cornerRadius: CGFloat = Theme.Radius.card, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            content
                .padding(14)
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Theme.glassStroke, lineWidth: 0.5)
                )
        } else {
            content
                .padding(14)
                .background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Theme.glassStroke, lineWidth: 0.5)
                )
        }
    }
}

/// Glass background applied as a `.background` modifier — leaves padding to the caller.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.row
    var tint: Color? = nil

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    tint.map { .regular.tint($0.opacity(0.30)) } ?? .regular,
                    in: .rect(cornerRadius: cornerRadius)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Theme.glassStroke, lineWidth: 0.5)
                )
        } else {
            content
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.regularMaterial)
                        if let tint {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(tint.opacity(0.18))
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Theme.glassStroke, lineWidth: 0.5)
                )
        }
    }
}

/// Capsule-shaped glass — for chips, badges, pills.
struct GlassPill: ViewModifier {
    var tint: Color? = nil

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    tint.map { .regular.tint($0.opacity(0.35)) } ?? .regular,
                    in: .capsule
                )
                .overlay(Capsule().strokeBorder(Theme.glassStroke, lineWidth: 0.5))
        } else {
            content
                .background(
                    ZStack {
                        Capsule().fill(.thinMaterial)
                        if let tint {
                            Capsule().fill(tint.opacity(0.20))
                        }
                    }
                )
                .overlay(Capsule().strokeBorder(Theme.glassStroke, lineWidth: 0.5))
        }
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = Theme.Radius.row, tint: Color? = nil) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, tint: tint))
    }

    func glassPill(tint: Color? = nil) -> some View {
        modifier(GlassPill(tint: tint))
    }
}

import SwiftUI

/// Visual tokens for Smoothie. Monochrome palette inspired by Cursor — pure black
/// backdrop, white at varying opacities for chrome and text, glassmorphism via
/// native materials. Semantic state still uses minimal chromatic hints (mostly
/// for the error state) but is otherwise driven by opacity and stroke weight.
enum Theme {
    // Backdrop — near-black with a hint of warmth so glass has something to refract.
    static let bg          = Color(red: 0.030, green: 0.030, blue: 0.034)
    static let bgDeep      = Color(red: 0.008, green: 0.008, blue: 0.010)

    // Primary accent is pure white — used for CTAs (white-on-black).
    static let accent      = Color.white
    static let accentSoft  = Color.white.opacity(0.12)

    // Semantic state — desaturated almost-white. Only `error` keeps a faint hue.
    static let waiting     = Color.white                                  // attention = brightest white
    static let waitingSoft = Color.white.opacity(0.14)
    static let thinking    = Color.white.opacity(0.78)
    static let thinkingSoft = Color.white.opacity(0.10)
    static let error       = Color(red: 1.00, green: 0.55, blue: 0.55)    // faint warm hint, no full red
    static let errorSoft   = Color(red: 1.00, green: 0.55, blue: 0.55).opacity(0.14)

    // Text — vibrant primary, then descending opacities for hierarchy
    static let text        = Color.white
    static let textMuted   = Color.white.opacity(0.62)
    static let textDim     = Color.white.opacity(0.36)
    static let textFaint   = Color.white.opacity(0.18)

    // Strokes — catch light along glass edges
    static let glassStroke      = Color.white.opacity(0.10)
    static let glassStrokeSoft  = Color.white.opacity(0.05)

    enum Radius {
        static let pill: CGFloat = 999
        static let card: CGFloat = 18
        static let row: CGFloat = 14
        static let input: CGFloat = 14
        static let button: CGFloat = 14
    }
}

// MARK: - Backdrop

/// Quiet near-black backdrop with a very subtle vignette. No color tints — pure
/// monochrome so the glass surfaces above stay neutral.
struct BackdropView: View {
    var body: some View {
        ZStack {
            Theme.bgDeep.ignoresSafeArea()
            RadialGradient(
                colors: [Color.white.opacity(0.04), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 600
            )
            .ignoresSafeArea()
            .blendMode(.plusLighter)
            // Sublime mesh: pure greys at very low opacities so reflections feel real
            // without introducing color cast.
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    .init(0.0, 0.0), .init(0.5, 0.0), .init(1.0, 0.0),
                    .init(0.0, 0.5), .init(0.55, 0.5), .init(1.0, 0.5),
                    .init(0.0, 1.0), .init(0.5, 1.0), .init(1.0, 1.0),
                ],
                colors: [
                    Theme.bgDeep,                       Theme.bgDeep,                  Theme.bgDeep,
                    Color.white.opacity(0.045),         Theme.bg,                      Color.white.opacity(0.025),
                    Theme.bgDeep,                       Theme.bgDeep,                  Theme.bgDeep,
                ]
            )
            .ignoresSafeArea()
            .blur(radius: 70)
            .opacity(0.9)
        }
    }
}

// MARK: - Glass surfaces

/// A card-shaped glass surface. iOS 26 uses Liquid Glass; iOS 18–25 uses
/// `.regularMaterial`. No colored tints by default — pure neutral glass.
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

/// Glass background as a modifier — caller controls padding. Optional white-only
/// tint is layered as a low-opacity overlay to keep the surface monochrome.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = Theme.Radius.row
    var emphasis: Emphasis = .none

    enum Emphasis {
        case none      // neutral glass
        case subtle    // very faint white tint for selected/active state
        case error     // faint warm tint for error rows
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(tintStyle, in: .rect(cornerRadius: cornerRadius))
                .overlay(shape.strokeBorder(strokeColor, lineWidth: emphasis == .none ? 0.5 : 0.75))
        } else {
            content
                .background(
                    ZStack {
                        shape.fill(.regularMaterial)
                        if emphasis == .subtle {
                            shape.fill(Color.white.opacity(0.05))
                        } else if emphasis == .error {
                            shape.fill(Theme.error.opacity(0.10))
                        }
                    }
                )
                .overlay(shape.strokeBorder(strokeColor, lineWidth: emphasis == .none ? 0.5 : 0.75))
        }
    }

    @available(iOS 26.0, *)
    private var tintStyle: Glass {
        switch emphasis {
        case .none:    return .regular
        case .subtle:  return .regular.tint(Color.white.opacity(0.10))
        case .error:   return .regular.tint(Theme.error.opacity(0.20))
        }
    }

    private var strokeColor: Color {
        switch emphasis {
        case .none:    return Theme.glassStroke
        case .subtle:  return Color.white.opacity(0.18)
        case .error:   return Theme.error.opacity(0.30)
        }
    }
}

/// Capsule-shaped glass — for chips, badges, pills.
struct GlassPill: ViewModifier {
    var emphasized: Bool = false

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    emphasized ? .regular.tint(Color.white.opacity(0.12)) : .regular,
                    in: .capsule
                )
                .overlay(
                    Capsule().strokeBorder(
                        emphasized ? Color.white.opacity(0.22) : Theme.glassStroke,
                        lineWidth: emphasized ? 0.75 : 0.5
                    )
                )
        } else {
            content
                .background(
                    ZStack {
                        Capsule().fill(.thinMaterial)
                        if emphasized { Capsule().fill(Color.white.opacity(0.08)) }
                    }
                )
                .overlay(
                    Capsule().strokeBorder(
                        emphasized ? Color.white.opacity(0.22) : Theme.glassStroke,
                        lineWidth: emphasized ? 0.75 : 0.5
                    )
                )
        }
    }
}

extension View {
    func glassSurface(
        cornerRadius: CGFloat = Theme.Radius.row,
        emphasis: GlassSurface.Emphasis = .none
    ) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, emphasis: emphasis))
    }

    func glassPill(emphasized: Bool = false) -> some View {
        modifier(GlassPill(emphasized: emphasized))
    }
}

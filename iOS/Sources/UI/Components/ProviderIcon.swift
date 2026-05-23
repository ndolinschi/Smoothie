import SwiftUI

/// Branded glyph for each CLI. SwiftUI-drawn so we don't bundle / license
/// the vendors' actual marks, but the shapes intentionally echo them:
///
/// - Claude — 12 radial spokes (shape carries the brand recognition; P25
///   retired the coral fill in favour of white@0.85 to match the new
///   mono palette)
/// - Gemini — 4-point cushion star with Google's red→yellow→green→blue arc
/// - OpenCode — a single OpenAI-ish ring placeholder
/// - Antigravity — upward arrow inside a violet→cyan gradient circle (the
///   "anti-gravity" metaphor, riffing on the desktop app's violet palette)
struct ProviderIcon: View {
    let cli: CLIWire
    var size: CGFloat = 18

    var body: some View {
        Group {
            switch cli {
            case .claudeCode:  ClaudeMark()
            case .gemini:      GeminiMark()
            case .openCode:    OpenCodeMark()
            case .antigravity: AntigravityMark()
            case .codex:       CodexMark()
            case .cursor:      CursorMark()
            case .unknown:     UnknownCliMark()
            }
        }
        .frame(width: size, height: size)
    }
}

/// Fallback mark for `CLIWire.unknown` — a daemon-newer-than-iOS CLI
/// that this build hasn't been taught about. Renders as a question
/// mark inside a neutral square so the row reads "we don't recognise
/// this provider" without blowing up the layout.
private struct UnknownCliMark: View {
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(Color(white: 0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                Image(systemName: "questionmark")
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}

struct ProviderChip: View {
    let cli: CLIWire
    var label: String?

    var body: some View {
        HStack(spacing: 6) {
            ProviderIcon(cli: cli, size: 13)
            Text(label ?? cli.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(SmoothieColor.bgCard, in: .capsule)
        .overlay(Capsule().strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5))
    }
}

// MARK: - Claude

private struct ClaudeMark: View {
    private let spokeCount = 12
    private let spokeColor = Color.white.opacity(0.85)

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerRadius = min(size.width, size.height) / 2 * 0.96
            let innerRadius = outerRadius * 0.18
            let spokeHalfWidth = outerRadius * 0.07
            for i in 0..<spokeCount {
                let angle = (CGFloat(i) / CGFloat(spokeCount)) * .pi * 2 - .pi / 2
                var path = Path()
                let cosA = cos(angle)
                let sinA = sin(angle)
                let perpCos = cos(angle + .pi / 2)
                let perpSin = sin(angle + .pi / 2)

                let p1 = CGPoint(
                    x: center.x + cosA * innerRadius + perpCos * spokeHalfWidth,
                    y: center.y + sinA * innerRadius + perpSin * spokeHalfWidth
                )
                let p2 = CGPoint(
                    x: center.x + cosA * outerRadius + perpCos * spokeHalfWidth * 0.5,
                    y: center.y + sinA * outerRadius + perpSin * spokeHalfWidth * 0.5
                )
                let p3 = CGPoint(
                    x: center.x + cosA * outerRadius - perpCos * spokeHalfWidth * 0.5,
                    y: center.y + sinA * outerRadius - perpSin * spokeHalfWidth * 0.5
                )
                let p4 = CGPoint(
                    x: center.x + cosA * innerRadius - perpCos * spokeHalfWidth,
                    y: center.y + sinA * innerRadius - perpSin * spokeHalfWidth
                )
                path.move(to: p1)
                path.addLine(to: p2)
                path.addLine(to: p3)
                path.addLine(to: p4)
                path.closeSubpath()
                ctx.fill(path, with: .color(spokeColor))
            }
            // Tiny core to fill the gap between spokes
            let coreRadius = innerRadius * 1.6
            let core = Path(ellipseIn: CGRect(
                x: center.x - coreRadius,
                y: center.y - coreRadius,
                width: coreRadius * 2,
                height: coreRadius * 2
            ))
            ctx.fill(core, with: .color(spokeColor))
        }
    }
}

// MARK: - Gemini

private struct GeminiMark: View {
    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            geminiStar(in: rect)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 0.94, green: 0.27, blue: 0.27), location: 0.00),  // red
                            .init(color: Color(red: 0.98, green: 0.71, blue: 0.16), location: 0.30),  // amber
                            .init(color: Color(red: 0.40, green: 0.78, blue: 0.34), location: 0.55),  // green
                            .init(color: Color(red: 0.27, green: 0.55, blue: 0.95), location: 1.00),  // blue
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    /// Cushion-shaped 4-point star (Google's Gemini sparkle).
    private func geminiStar(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY
        let r = min(rect.width, rect.height) / 2
        let inset = r * 0.45         // how concave the cushion is
        let pad = r * 0.04

        let top    = CGPoint(x: cx,         y: cy - r + pad)
        let right  = CGPoint(x: cx + r - pad, y: cy)
        let bottom = CGPoint(x: cx,         y: cy + r - pad)
        let left   = CGPoint(x: cx - r + pad, y: cy)

        // Inner control points for the cushion curve
        let topRight   = CGPoint(x: cx + inset, y: cy - inset)
        let bottomRight = CGPoint(x: cx + inset, y: cy + inset)
        let bottomLeft = CGPoint(x: cx - inset, y: cy + inset)
        let topLeft    = CGPoint(x: cx - inset, y: cy - inset)

        path.move(to: top)
        path.addQuadCurve(to: right,  control: topRight)
        path.addQuadCurve(to: bottom, control: bottomRight)
        path.addQuadCurve(to: left,   control: bottomLeft)
        path.addQuadCurve(to: top,    control: topLeft)
        path.closeSubpath()
        return path
    }
}

// MARK: - Antigravity

/// Stylised "upward arrow inside a cushion" — the marketing site uses a
/// rounded violet→cyan gradient with a thick arrow glyph in the centre. We
/// approximate it in two layers: a gradient-filled rounded-square plate and
/// a chunky white triangle pointing up. Distinct from Gemini's four-point
/// star and Claude's spokes at a glance, which matters because the iOS
/// home list shows the icons at 18 pt.
private struct AntigravityMark: View {
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let rect = CGRect(
                x: (geo.size.width - size) / 2,
                y: (geo.size.height - size) / 2,
                width: size,
                height: size
            )
            ZStack {
                // Rounded-square plate with the official violet→cyan gradient
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color(red: 0.43, green: 0.21, blue: 0.85), location: 0.00),  // deep violet
                                .init(color: Color(red: 0.55, green: 0.40, blue: 0.95), location: 0.45),  // light violet
                                .init(color: Color(red: 0.27, green: 0.70, blue: 0.95), location: 1.00),  // cyan
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: rect.width, height: rect.height)

                // White upward triangle — the "anti-gravity" arrow
                Path { path in
                    let cx = rect.midX
                    let cy = rect.midY
                    let half = size * 0.28
                    let height = size * 0.34
                    path.move(to: CGPoint(x: cx, y: cy - height / 2))
                    path.addLine(to: CGPoint(x: cx + half, y: cy + height / 2))
                    path.addLine(to: CGPoint(x: cx - half, y: cy + height / 2))
                    path.closeSubpath()
                }
                .fill(Color.white)
            }
        }
    }
}

// MARK: - OpenCode / Codex placeholder

private struct OpenCodeMark: View {
    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = min(size.width, size.height) / 2 * 0.92
            let inner = outer * 0.55
            let strokeWidth = (outer - inner) * 0.45

            // Six knotted petals (a rough nod to OpenAI's six-line knot)
            for i in 0..<6 {
                let angle = (CGFloat(i) / 6) * .pi * 2
                var path = Path()
                let start = CGPoint(
                    x: center.x + cos(angle) * outer,
                    y: center.y + sin(angle) * outer
                )
                let cw = CGPoint(
                    x: center.x + cos(angle + .pi / 3) * inner * 0.5,
                    y: center.y + sin(angle + .pi / 3) * inner * 0.5
                )
                let end = CGPoint(
                    x: center.x + cos(angle + 2 * .pi / 3) * outer,
                    y: center.y + sin(angle + 2 * .pi / 3) * outer
                )
                path.move(to: start)
                path.addQuadCurve(to: end, control: cw)
                ctx.stroke(
                    path,
                    with: .color(.white),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
            }
        }
    }
}

// MARK: - Codex

/// OpenAI Codex mark — black rounded square with a centered white
/// asterisk-like burst. Matches OpenAI's monochrome wordmark colour
/// without bundling the actual logotype.
private struct CodexMark: View {
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let rect = CGRect(
                x: (geo.size.width - size) / 2,
                y: (geo.size.height - size) / 2,
                width: size,
                height: size
            )
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(Color(white: 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .frame(width: rect.width, height: rect.height)
                // Six-spoke burst, OpenAI-flavoured.
                Canvas { ctx, canvasSize in
                    let cx = rect.midX
                    let cy = rect.midY
                    let r = size * 0.32
                    let stroke = size * 0.08
                    for i in 0..<6 {
                        let angle = Double(i) * .pi / 3.0
                        var path = Path()
                        path.move(to: CGPoint(x: cx, y: cy))
                        path.addLine(to: CGPoint(
                            x: cx + r * cos(angle),
                            y: cy + r * sin(angle)
                        ))
                        ctx.stroke(
                            path,
                            with: .color(.white),
                            style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                        )
                    }
                    _ = canvasSize
                }
                .frame(width: rect.width, height: rect.height)
            }
        }
    }
}

// MARK: - Cursor

/// Cursor mark — black rounded square with a stylised diagonal arrow
/// (the editor's cursor mascot). Mono palette so it sits next to the
/// other marks without fighting them.
private struct CursorMark: View {
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let rect = CGRect(
                x: (geo.size.width - size) / 2,
                y: (geo.size.height - size) / 2,
                width: size,
                height: size
            )
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(Color(white: 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .frame(width: rect.width, height: rect.height)
                // Diagonal cursor arrow filled in white.
                Path { path in
                    let inset = size * 0.20
                    let topLeft = CGPoint(x: rect.minX + inset, y: rect.minY + inset)
                    let bottomLeft = CGPoint(x: rect.minX + inset, y: rect.maxY - inset)
                    let bottomRight = CGPoint(x: rect.maxX - inset, y: rect.maxY - inset * 0.55)
                    let mid = CGPoint(x: rect.midX, y: rect.midY)
                    path.move(to: topLeft)
                    path.addLine(to: bottomRight)
                    path.addLine(to: mid)
                    path.addLine(to: bottomLeft)
                    path.closeSubpath()
                }
                .fill(Color.white)
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 18) {
            ForEach(CLIWire.allCases) { cli in
                HStack(spacing: 12) {
                    ProviderIcon(cli: cli, size: 32)
                    Text(cli.displayName)
                        .foregroundStyle(.white)
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                    ProviderChip(cli: cli, label: "sonnet · high")
                }
            }
        }
        .padding(28)
    }
    .preferredColorScheme(.dark)
}

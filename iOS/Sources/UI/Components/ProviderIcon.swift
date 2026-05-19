import SwiftUI

/// Branded glyph for each CLI. iOS 26 Asset Catalogs natively support SVG,
/// so when canonical provider marks land in `Assets.xcassets/Providers/`,
/// this view will load them from the bundle. Until then it falls back to
/// SF Symbols tinted with each vendor's accent colour.
struct ProviderIcon: View {
    let cli: CLIWire
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let _ = UIImage(named: assetName) {
                Image(assetName)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size, weight: .semibold))
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(brandColor)
    }

    private var assetName: String { "Providers/\(cli.rawValue)" }

    private var fallbackSymbol: String {
        switch cli {
        case .claudeCode: return "sparkle"
        case .gemini:     return "diamond.fill"
        case .openCode:   return "terminal.fill"
        }
    }

    var brandColor: Color {
        switch cli {
        case .claudeCode:
            // Anthropic / Claude warm coral
            return Color(red: 0.85, green: 0.46, blue: 0.34)
        case .gemini:
            // Google blue-violet — gradient approximated as single tone for now
            return Color(red: 0.36, green: 0.55, blue: 0.95)
        case .openCode:
            // OpenCode mark — neutral white with a hint of teal
            return Color(red: 0.42, green: 0.85, blue: 0.75)
        }
    }
}

/// Glass pill with the brand glyph + label. Used in CLI rows and the active
/// session's model chip.
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
        .glassEffect(in: .capsule)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 16) {
            ForEach(CLIWire.allCases) { cli in
                HStack(spacing: 12) {
                    ProviderIcon(cli: cli, size: 28)
                    Text(cli.displayName)
                        .foregroundStyle(.white)
                    Spacer()
                    ProviderChip(cli: cli, label: "sonnet · high")
                }
            }
        }
        .padding(24)
    }
    .preferredColorScheme(.dark)
}

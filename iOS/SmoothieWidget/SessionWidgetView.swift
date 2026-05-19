import WidgetKit
import SwiftUI

/// State-aware widget body. Three families:
///   - `.systemSmall`: square card with provider mark + project + status line.
///   - `.accessoryRectangular`: Lock Screen rectangle, monochrome.
///   - `.accessoryInline`: Lock Screen text-only chip.
struct SessionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                inlineView
            case .accessoryRectangular:
                rectangularView
            default:
                smallView
            }
        }
        .widgetURL(deepLink)
    }

    private var deepLink: URL? {
        guard let id = snapshot.sessionId else { return URL(string: "smoothie://home") }
        return URL(string: "smoothie://session/\(id)")
    }

    // MARK: - Small (Home Screen)

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                statePixel
                Text(headline)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
                    .tracking(0.6)
                Spacer()
            }
            Spacer(minLength: 2)
            Text(snapshot.projectName ?? "Ready to vibe")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 5) {
                Image(systemName: providerSymbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Accessory rectangular (Lock Screen)

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: providerSymbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(headline)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(0.6)
            }
            Text(snapshot.projectName ?? "Ready to vibe")
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
            Text(footnote)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Accessory inline (Lock Screen text chip)

    private var inlineView: some View {
        Label("\(snapshot.projectName ?? "Smoothie") · \(headline.lowercased())",
              systemImage: providerSymbol)
    }

    // MARK: - Helpers

    private var headline: String {
        switch snapshot.state {
        case .none:         return "IDLE"
        case .starting:     return "STARTING"
        case .thinking:     return "THINKING"
        case .waiting:      return "NEEDS YOU"
        case .done:         return "DONE"
        case .error:        return "ERROR"
        case .limitReached: return "LIMIT"
        }
    }

    private var footnote: String {
        if snapshot.state == .none { return "no session" }
        if snapshot.lastEventAt == .distantPast { return cliLabel }
        let interval = Date.now.timeIntervalSince(snapshot.lastEventAt)
        let age: String
        if interval < 60 { age = "now" }
        else if interval < 3600 { age = "\(Int(interval / 60))m" }
        else if interval < 86_400 { age = "\(Int(interval / 3600))h" }
        else { age = "\(Int(interval / 86_400))d" }
        return "\(cliLabel) · \(age)"
    }

    private var cliLabel: String {
        switch snapshot.cli {
        case .claudeCode: return "Claude"
        case .gemini:     return "Gemini"
        case .openCode:   return "OpenCode"
        case .none:       return "Smoothie"
        }
    }

    private var providerSymbol: String {
        switch snapshot.cli {
        case .claudeCode: return "rays"
        case .gemini:     return "sparkles"
        case .openCode:   return "terminal.fill"
        case .none:       return "circle.dotted"
        }
    }

    /// Small coloured pulse next to the headline. Used in `.systemSmall` only.
    @ViewBuilder
    private var statePixel: some View {
        let color: Color = {
            switch snapshot.state {
            case .none:                            return .white.opacity(0.25)
            case .starting:                        return .white.opacity(0.55)
            case .thinking:                        return .blue
            case .waiting:                         return .orange
            case .done:                            return .green.opacity(0.7)
            case .error, .limitReached:            return .red
            }
        }()
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }
}

import SwiftUI

/// Status pill shown only when the agent is *actively doing something*.
/// `starting`, `done`, `waiting` are intentionally invisible — they're not
/// meaningful state for the user to act on, and a perpetual "waiting" chip
/// becomes wallpaper noise. The pill returns for `thinking` (real work
/// happening), `error` (something went wrong), and `limitReached` (needs
/// user action).
struct StatusBadge: View {
    let state: SessionStateWire
    var connected: Bool = true

    var body: some View {
        if let palette {
            HStack(spacing: 6) {
                Circle()
                    .fill(palette.dot)
                    .frame(width: 6, height: 6)
                    .opacity(connected ? 1 : 0.35)
                    .shadow(color: palette.dot.opacity(0.5), radius: 4)
                Text(palette.label)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(palette.text)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassEffect(in: .capsule)
        }
    }

    private struct Palette {
        let label: String
        let dot: Color
        let text: Color
    }

    private var palette: Palette? {
        switch state {
        case .starting, .done, .waiting:
            return nil
        case .thinking:
            return Palette(label: "thinking", dot: .blue, text: .blue)
        case .error:
            return Palette(label: "error", dot: .red, text: .red)
        case .limitReached:
            return Palette(label: "limit", dot: .red, text: .red)
        }
    }
}

// Kept so existing call sites that read `.color` on a state for tinting
// (e.g. HomeView's session card glyph) still resolve. Returns muted white
// for the "quiet" states.
extension SessionStateWire {
    var color: Color {
        switch self {
        case .starting:     return .white.opacity(0.45)
        case .thinking:     return .blue
        case .waiting:      return .white.opacity(0.55)
        case .done:         return .white.opacity(0.4)
        case .error:        return .red
        case .limitReached: return .red
        }
    }
}

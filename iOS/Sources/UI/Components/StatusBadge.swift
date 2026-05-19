import SwiftUI

struct StatusBadge: View {
    let state: SessionStateWire
    var connected: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.color)
                .frame(width: 6, height: 6)
                .opacity(connected ? 1 : 0.35)
                .shadow(color: state.color.opacity(0.5), radius: 4)
            Text(state.label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(state.textColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .glassEffect(in: .capsule)
    }
}

extension SessionStateWire {
    var label: String {
        switch self {
        case .starting:     return "starting"
        case .thinking:     return "thinking"
        case .waiting:      return "waiting"
        case .done:         return "done"
        case .error:        return "error"
        case .limitReached: return "limit"
        }
    }

    var color: Color {
        switch self {
        case .starting:     return .gray
        case .thinking:     return .blue
        case .waiting:      return .orange
        case .done:         return Color(white: 0.6)
        case .error:        return .red
        case .limitReached: return .red
        }
    }

    var textColor: Color {
        switch self {
        case .done: return .white.opacity(0.6)
        default:    return color
        }
    }
}

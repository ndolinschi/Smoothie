import SwiftUI

struct StatusBadge: View {
    let state: SessionState
    var connected: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .opacity(connected ? 1.0 : 0.3)
                .shadow(color: dotColor.opacity(0.55), radius: 4)
            Text(state.rawValue)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(textColor)
                .tracking(0.3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassPill(emphasized: state == .waiting || state == .error)
    }

    private var dotColor: Color {
        switch state {
        case .waiting: return .white                           // attention
        case .error:   return Theme.error
        case .thinking: return .white.opacity(0.85)
        case .done:    return .white.opacity(0.5)
        case .starting: return .white.opacity(0.5)
        }
    }

    private var textColor: Color {
        switch state {
        case .error:   return Theme.error
        case .waiting: return .white
        case .thinking: return .white.opacity(0.85)
        default:       return .white.opacity(0.6)
        }
    }
}

#Preview {
    ZStack {
        BackdropView()
        VStack(spacing: 12) {
            StatusBadge(state: .starting)
            StatusBadge(state: .thinking)
            StatusBadge(state: .waiting)
            StatusBadge(state: .done)
            StatusBadge(state: .error)
        }
    }
    .preferredColorScheme(.dark)
}

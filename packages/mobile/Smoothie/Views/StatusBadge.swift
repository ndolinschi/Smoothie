import SwiftUI

struct StatusBadge: View {
    let state: SessionState
    var connected: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.tint)
                .frame(width: 6, height: 6)
                .opacity(connected ? 1.0 : 0.3)
                .shadow(color: state.tint.opacity(0.6), radius: 4)
            Text(state.rawValue)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(state.tint)
                .tracking(0.3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassPill(tint: state.tint)
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

import SwiftUI

struct MessageInput: View {
    let state: SessionState
    let onSend: (String) async -> Void
    var disabled: Bool = false

    @State private var text: String = ""
    @State private var sending = false
    @FocusState private var focused: Bool

    private var canSend: Bool { !sending && !disabled && !text.trimmingCharacters(in: .whitespaces).isEmpty }
    private var accentTint: Color { state == .waiting ? Theme.waiting : .clear }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(
                state == .waiting ? "agent is waiting for you…" : "send a message",
                text: $text,
                axis: .vertical
            )
            .focused($focused)
            .lineLimit(1...5)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .foregroundStyle(.white)
            .glassSurface(cornerRadius: Theme.Radius.input, tint: accentTint)
            .disabled(disabled)

            Button(action: send) {
                Image(systemName: sending ? "ellipsis" : "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(canSend ? .black : .white.opacity(0.4))
                    .frame(width: 44, height: 44)
                    .background {
                        ZStack {
                            if canSend {
                                LinearGradient(
                                    colors: [Theme.accent, Theme.accent.opacity(0.85)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            } else {
                                Color.white.opacity(0.08)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                            .strokeBorder(Theme.glassStroke, lineWidth: 0.5)
                    )
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(state == .waiting ? Theme.waiting.opacity(0.6) : Color.white.opacity(0.08))
                .frame(height: 0.5),
            alignment: .top
        )
        .onChange(of: state) { _, newState in
            if newState == .waiting { focused = true }
        }
    }

    private func send() {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        sending = true
        Task {
            await onSend(value)
            text = ""
            sending = false
        }
    }
}

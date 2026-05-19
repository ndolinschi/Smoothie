import SwiftUI

struct MessageInput: View {
    let state: SessionStateWire
    let onSend: (String) async -> Void

    @State private var text: String = ""
    @State private var sending = false
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !sending && !trimmed.isEmpty }

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
            .glassEffect(in: .rect(cornerRadius: 14))

            Button(action: send) {
                Image(systemName: sending ? "ellipsis" : "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(canSend ? .black : .white.opacity(0.4))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(.white)
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(state == .waiting ? Color.orange.opacity(0.5) : Color.white.opacity(0.08))
                .frame(height: 0.5),
            alignment: .top
        )
        .onChange(of: state) { _, new in
            if new == .waiting { focused = true }
        }
    }

    private func send() {
        let value = trimmed
        guard !value.isEmpty else { return }
        sending = true
        Task {
            await onSend(value)
            text = ""
            sending = false
        }
    }
}

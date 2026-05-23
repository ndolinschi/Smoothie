import SwiftUI

/// Thin status strip pinned under the SessionView toolbar. Tells the user
/// at a glance whether the SSE link is live. Hidden once the connection is
/// `.connected` AND at least one event has arrived (so a stale connection
/// to an idle session doesn't pretend everything's fine).
///
/// Color language mirrors the rest of the design tokens — neutral grey while
/// optimistic, coral while reconnecting, red when stopped.
struct ConnectionBanner: View {
    let connection: SSEClient.State
    let state: SessionStateWire
    let hasReceivedEvent: Bool
    /// Optional reconnect action — surfaces a trailing "Reconnect" pill
    /// when the SSE link is in a non-transient bad state (`.retrying`,
    /// `.stopped`, `.gone`). When nil the banner stays read-only.
    var onReconnect: (() -> Void)? = nil

    var body: some View {
        if let payload {
            HStack(spacing: 8) {
                payload.indicator
                Text(payload.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(payload.text)
                Spacer(minLength: 0)
                if payload.allowsReconnect, let onReconnect {
                    reconnectButton(action: onReconnect)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(payload.background)
            .overlay(
                Rectangle()
                    .fill(SmoothieColor.strokeSoft)
                    .frame(height: 0.5),
                alignment: .bottom
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func reconnectButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .bold))
                Text("Reconnect")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(SmoothieColor.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(SmoothieColor.bgCard, in: .capsule)
            .overlay(Capsule().strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private struct Payload {
        let label: String
        let text: Color
        let background: Color
        let indicator: AnyView
        var allowsReconnect: Bool = false
    }

    /// Returns nil → banner hides. Returns a payload → banner shows.
    private var payload: Payload? {
        switch connection {
        case .connecting:
            return Payload(
                label: "Connecting to your Mac…",
                text: SmoothieColor.textSecondary,
                background: SmoothieColor.bgCard,
                indicator: AnyView(spinner(.gray))
            )
        case .retrying(let seconds):
            return Payload(
                label: "Lost connection — retrying in \(seconds)s",
                text: SmoothieColor.accent,
                background: SmoothieColor.accentSoft,
                indicator: AnyView(pulseDot(SmoothieColor.accent)),
                allowsReconnect: true
            )
        case .stopped:
            return Payload(
                label: "Disconnected from your Mac",
                text: SmoothieColor.statusErr,
                background: SmoothieColor.statusErr.opacity(0.12),
                indicator: AnyView(staticDot(SmoothieColor.statusErr)),
                allowsReconnect: true
            )
        case .gone(let reason):
            // Terminal — session no longer exists on the Mac. We surface
            // a Reconnect anyway so the user can take a manual stab at
            // recovery (usually reproduces the gone state, but the
            // agency matters when the daemon side just restarted).
            return Payload(
                label: reason,
                text: SmoothieColor.statusErr,
                background: SmoothieColor.statusErr.opacity(0.12),
                indicator: AnyView(Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SmoothieColor.statusErr)),
                allowsReconnect: true
            )
        case .connected:
            // Show a one-shot "Connected — waiting for the first event"
            // hint when the link is up but the session hasn't streamed
            // anything yet. Disappears the moment a single event lands.
            if hasReceivedEvent { return nil }
            switch state {
            case .starting:
                return Payload(
                    label: "Connected — agent is starting up…",
                    text: SmoothieColor.textSecondary,
                    background: SmoothieColor.bgCard,
                    indicator: AnyView(spinner(.gray))
                )
            case .thinking:
                return Payload(
                    label: "Connected — agent is thinking…",
                    text: SmoothieColor.textSecondary,
                    background: SmoothieColor.bgCard,
                    indicator: AnyView(pulseDot(.blue))
                )
            case .waiting:
                return Payload(
                    label: "Connected — type a message to start",
                    text: SmoothieColor.textSecondary,
                    background: SmoothieColor.bgCard,
                    indicator: AnyView(staticDot(.green))
                )
            case .done, .error, .limitReached:
                // For terminal states an event row already explains things.
                return nil
            case .unknown:
                // Future-daemon state we don't recognise — stay quiet rather
                // than make up a label. The session state machine will keep
                // ticking on subsequent events.
                return nil
            }
        }
    }

    private func spinner(_ tint: Color) -> some View {
        ProgressView()
            .controlSize(.mini)
            .tint(tint)
    }

    private func staticDot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(0.6), radius: 4)
    }

    private func pulseDot(_ color: Color) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let pulse = (sin(t * 2.4) + 1) / 2 // 0..1
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .opacity(0.4 + pulse * 0.6)
                .shadow(color: color.opacity(0.6), radius: 4)
        }
    }
}

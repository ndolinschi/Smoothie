import SwiftUI

struct AgentStream: View {
    let events: [SmoothieEventWire]
    let connection: SSEClient.State
    let state: SessionStateWire

    /// Memoised tool-stack collapse output. We rebuild it only when the
    /// event count or the trailing event identity actually changes —
    /// running `AgentStreamItem.collapse` per body redraw was O(events) on
    /// every keystroke / SSE frame and dominated CPU during long
    /// streaming responses.
    @State private var cachedItems: [AgentStreamItem] = []
    @State private var cachedSignature: String = ""

    private var items: [AgentStreamItem] {
        if cachedSignature == signature(of: events) { return cachedItems }
        return AgentStreamItem.collapse(events)
    }

    private func signature(of events: [SmoothieEventWire]) -> String {
        let last = events.last
        return "\(events.count)|\(last?.id ?? "-")|\(last?.content.count ?? 0)"
    }

    private func refreshItemsIfNeeded() {
        let sig = signature(of: events)
        guard sig != cachedSignature else { return }
        cachedItems = AgentStreamItem.collapse(events)
        cachedSignature = sig
    }

    /// Whether to render the small typing pulse at the bottom of the stream.
    /// Fires when the agent is thinking but the *latest* event isn't a
    /// streaming assistant message (a streaming message updates content in
    /// place, so an additional pulse there would feel redundant).
    private var showsThinkingPulse: Bool {
        guard state == .thinking else { return false }
        guard let last = events.last else { return true }
        return last.type != .message
    }

    /// Re-render trigger that picks up incremental changes the agent makes to
    /// the latest event — Claude / OpenCode stream by emitting many
    /// `.message` / `.toolUse` rows in quick succession, but stale appends
    /// can also extend the trailing event's content (think OpenCode delta
    /// buffer flushes). Combining count + last id + last length means we
    /// scroll on either trigger.
    private var scrollKey: String {
        let last = events.last
        return "\(events.count)-\(last?.id ?? "-")-\(last?.content.count ?? 0)-\(showsThinkingPulse)"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if events.isEmpty {
                    EmptyStreamPlaceholder(connection: connection, state: state)
                        .frame(maxWidth: .infinity, minHeight: 320)
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                        .id("EMPTY")
                } else {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(items) { item in
                            switch item.kind {
                            case .event(let e):
                                EventRow(event: e).id(item.id)
                            case .toolStack(let name, let members):
                                ToolStackRow(name: name, members: members).id(item.id)
                            }
                        }
                        if showsThinkingPulse {
                            ThinkingPulseRow()
                                .id("THINKING")
                                .transition(.opacity)
                        }
                        Color.clear.frame(height: 1).id("BOTTOM")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .onChange(of: scrollKey) { _, _ in
                // One runloop tick so LazyVStack lays out the new row before
                // we ask the proxy to scroll. Without the delay the target
                // index hasn't been registered yet and the scroll is a no-op.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(40))
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo("BOTTOM", anchor: .bottom)
                    }
                }
            }
            .onAppear {
                refreshItemsIfNeeded()
                // Snap to the bottom on first appearance so opening an
                // active session lands you at the latest message.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(40))
                    proxy.scrollTo("BOTTOM", anchor: .bottom)
                }
            }
            .onChange(of: events.count) { _, _ in refreshItemsIfNeeded() }
            .onChange(of: events.last?.content.count ?? 0) { _, _ in refreshItemsIfNeeded() }
        }
    }
}

/// Centered card shown when the stream is empty. Communicates "we're
/// connected and ready" / "we're connecting" / "we're stuck" so the user
/// never stares at a blank screen wondering whether the app froze.
private struct EmptyStreamPlaceholder: View {
    let connection: SSEClient.State
    let state: SessionStateWire

    var body: some View {
        VStack(spacing: 14) {
            indicator
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(SmoothieColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(SmoothieColor.bgCard, in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var indicator: some View {
        switch connection {
        case .connecting:
            ProgressView().controlSize(.regular).tint(SmoothieColor.textSecondary)
        case .retrying:
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(SmoothieColor.accent)
        case .stopped:
            Image(systemName: "xmark.circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(SmoothieColor.statusErr)
        case .gone:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(SmoothieColor.statusErr)
        case .connected:
            switch state {
            case .starting, .thinking:
                ProgressView().controlSize(.regular).tint(.blue)
            case .waiting:
                Image(systemName: "paperplane")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textSecondary)
            case .done:
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SmoothieColor.statusDone)
            case .error, .limitReached:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SmoothieColor.statusErr)
            }
        }
    }

    private var title: String {
        switch connection {
        case .connecting: return "Connecting to your Mac…"
        case .retrying:   return "Reconnecting"
        case .stopped:    return "Disconnected"
        case .gone:       return "Session ended on the Mac"
        case .connected:
            switch state {
            case .starting, .thinking: return "Agent is warming up"
            case .waiting:             return "Ready when you are"
            case .done:                return "Session finished"
            case .error:               return "Something went wrong"
            case .limitReached:        return "Rate limit reached"
            }
        }
    }

    private var subtitle: String {
        switch connection {
        case .connecting:
            return "Setting up a live stream over the pairing token."
        case .retrying:
            return "Network blip — we'll try again. Your session keeps running on the Mac."
        case .stopped:
            return "Pull down to refresh or open the session again."
        case .gone(let reason):
            return reason
        case .connected:
            switch state {
            case .starting, .thinking:
                return "The agent is reading the project. First message should appear in a moment."
            case .waiting:
                return "Type a prompt below and hit send to start the conversation."
            case .done:
                return "No more events will arrive on this session."
            case .error:
                return "The CLI process reported an error before producing output."
            case .limitReached:
                return "The provider rejected the turn. Try again later or hand off to another CLI."
            }
        }
    }
}

/// Three-dot typing indicator pinned to the bottom of the stream while the
/// agent is thinking but hasn't produced a fresh assistant message yet.
private struct ThinkingPulseRow: View {
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let offset = Double(i) * 0.25
                    let pulse = (sin((t - offset) * 2.4) + 1) / 2
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                        .opacity(0.35 + pulse * 0.55)
                }
                .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(SmoothieColor.bgCard, in: .capsule)
        .overlay(Capsule().strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5))
    }
}

/// Either a single event or a collapsed run of same-name `.toolUse` events
/// (e.g. three consecutive `Bash` calls render as a `Bash ×3` stack chip).
struct AgentStreamItem: Identifiable {
    enum Kind {
        case event(SmoothieEventWire)
        case toolStack(name: String, members: [SmoothieEventWire])
    }
    let kind: Kind
    let id: String

    /// Walk `events` and merge consecutive `.toolUse` runs that share the
    /// same tool name. `.toolResult` events between the same-name tool_use
    /// calls are absorbed into the stack (and surfaced only when the user
    /// taps to expand). Any other event type (message, thinking, fileEdit,
    /// etc.) breaks the run.
    static func collapse(_ events: [SmoothieEventWire]) -> [AgentStreamItem] {
        var out: [AgentStreamItem] = []
        var i = 0
        while i < events.count {
            let e = events[i]
            guard e.type == .toolUse else {
                out.append(AgentStreamItem(kind: .event(e), id: e.id))
                i += 1
                continue
            }
            let name = e.content
            var run: [SmoothieEventWire] = [e]
            var j = i + 1
            while j < events.count {
                let next = events[j]
                if next.type == .toolUse && next.content == name {
                    run.append(next); j += 1
                } else if next.type == .toolResult {
                    run.append(next); j += 1
                } else {
                    break
                }
            }
            // Count how many tool_use entries we collected. A "stack" only
            // makes sense if there are 2+ tool_uses; otherwise emit each
            // individually so a lonely Bash call still shows its own chip.
            let useCount = run.filter { $0.type == .toolUse }.count
            if useCount >= 2 {
                out.append(AgentStreamItem(kind: .toolStack(name: name, members: run), id: e.id))
            } else {
                // One tool_use (plus maybe a tool_result) — render in place.
                for member in run {
                    out.append(AgentStreamItem(kind: .event(member), id: member.id))
                }
            }
            i = j
        }
        return out
    }
}

/// Compact stacked view for a run of N same-name tool calls (e.g. `Bash ×3`).
/// Tap toggles expansion; expanded view streams the underlying tool_use +
/// tool_result rows in order, each reusing the existing EventRow renderer.
private struct ToolStackRow: View {
    let name: String
    let members: [SmoothieEventWire]
    @State private var expanded: Bool = false

    private var useCount: Int {
        members.filter { $0.type == .toolUse }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.adjustable")
                        .font(.system(size: 11))
                    Text(name)
                        .font(.system(size: 12, design: .monospaced))
                    Text("×\(useCount)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(SmoothieColor.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(SmoothieColor.accentSoft, in: .capsule)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(SmoothieColor.bgCard, in: .capsule)
                .overlay(Capsule().strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(members) { e in
                        EventRow(event: e)
                    }
                }
                .padding(.leading, 14)
            }
        }
    }
}

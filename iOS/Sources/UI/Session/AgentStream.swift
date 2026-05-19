import SwiftUI

struct AgentStream: View {
    let events: [SmoothieEventWire]

    private var items: [AgentStreamItem] {
        AgentStreamItem.collapse(events)
    }

    /// Re-render trigger that picks up incremental changes the agent makes to
    /// the latest event — Claude / OpenCode stream by emitting many
    /// `.message` / `.toolUse` rows in quick succession, but stale appends
    /// can also extend the trailing event's content (think OpenCode delta
    /// buffer flushes). Combining count + last id + last length means we
    /// scroll on either trigger.
    private var scrollKey: String {
        let last = events.last
        return "\(events.count)-\(last?.id ?? "-")-\(last?.content.count ?? 0)"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(items) { item in
                        switch item.kind {
                        case .event(let e):
                            EventRow(event: e).id(item.id)
                        case .toolStack(let name, let members):
                            ToolStackRow(name: name, members: members).id(item.id)
                        }
                    }
                    Color.clear.frame(height: 1).id("BOTTOM")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
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
                // Snap to the bottom on first appearance so opening an
                // active session lands you at the latest message.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(40))
                    proxy.scrollTo("BOTTOM", anchor: .bottom)
                }
            }
        }
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
                .glassEffect(in: .capsule)
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

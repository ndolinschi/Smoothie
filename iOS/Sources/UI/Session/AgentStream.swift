import SwiftUI

struct AgentStream: View {
    let events: [SmoothieEventWire]
    let connection: SSEClient.State
    let state: SessionStateWire
    /// Lives on `SessionLiveStore` so tool-card expanded chevrons survive
    /// `LazyVStack` view recycling. AgentStream is the only consumer.
    @Bindable var expandStore: SessionLiveStore
    /// P29 §5 — drives the brand-color top stripe on every
    /// ToolCallCard rendered inside the stream. Defaults to nil so
    /// existing previews / call sites without a session context
    /// keep their neutral accent fallback.
    var cli: CLIWire? = nil
    /// P29 §3 — invoked from a `FileChangesPanel`'s "Show all"
    /// footer. SessionView wires this to its existing DiffSheet
    /// presentation so the full review surface (with comments) stays
    /// reachable inline from any file change.
    var onShowDiff: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// P29 §4 — bottom-anchor + viewport tracking for the smart
    /// auto-hide pill. `bottomMaxY` is the global Y of the BOTTOM
    /// sentinel; `viewportMaxY` is the global Y of the ScrollView
    /// itself. When the sentinel is below the viewport's bottom edge
    /// (with a small slack), the user has scrolled away and we surface
    /// the jump-to-latest pill.
    @State private var bottomMaxY: CGFloat = 0
    @State private var viewportMaxY: CGFloat = 0

    private var isAtBottom: Bool {
        guard viewportMaxY > 0, bottomMaxY > 0 else { return true }
        return bottomMaxY <= viewportMaxY + 60
    }

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

    /// Treat the stream as empty for placeholder purposes when there are
    /// no events that would actually render visibly. WAITING / DONE /
    /// EmptyView-rendered divider rows count as invisible — they only
    /// move the state machine. Without this guard, a freshly spawned
    /// session (single WAITING event from ProcessRegistry) showed a
    /// blank middle area instead of the friendly "Ready when you are"
    /// placeholder.
    private var hasVisibleEvents: Bool {
        events.contains { event in
            switch event.type {
            case .waiting, .done, .unknown, .contextUpdate:
                return false
            case .message, .thinking, .toolUse, .toolResult, .fileEdit, .error, .limitReached:
                // toolResult dividers (metadata.divider) are technically
                // visible but rendering them in isolation reads as a
                // floating "( )" — they're meant as separators between
                // visible content. We still count them so the placeholder
                // doesn't appear after the divider lands.
                return true
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if !hasVisibleEvents {
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
                                ToolStackRow(
                                    name: name,
                                    members: members,
                                    cli: cli,
                                    expandBinding: expandBinding(for: item.id),
                                    resultExpandBinding: resultExpandBinding(for: item.id)
                                ).id(item.id)
                            case .toolCard(let use, let result):
                                let isSubagent = use.content == "Task"
                                ToolCallCard(
                                    icon: iconForTool(use),
                                    name: use.content,
                                    status: result != nil ? .completed : .running,
                                    inputFields: EventRow.inputFields(from: use, hidingKeys: isSubagent ? ["subagent_type"] : []),
                                    result: result?.content,
                                    tint: isSubagent ? SmoothieColor.accent : SmoothieColor.textPrimary.opacity(0.85),
                                    subtitleBadge: isSubagent ? EventRow.subagentType(from: use) : nil,
                                    emphasised: isSubagent,
                                    cli: cli,
                                    expanded: expandBinding(for: use.id),
                                    resultExpanded: resultExpandBinding(for: use.id)
                                )
                                .id(item.id)
                            case .fileChanges(let e):
                                FileChangesPanel(event: e, onShowAll: onShowDiff)
                                    .id(item.id)
                            }
                        }
                        if showsThinkingPulse {
                            ThinkingPulseRow()
                                .id("THINKING")
                                .transition(.opacity)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("BOTTOM")
                            // P29 §4 — publish the BOTTOM sentinel's
                            // global Y so the jump-to-latest pill knows
                            // whether the user is at the bottom.
                            .background(
                                GeometryReader { g in
                                    Color.clear.preference(
                                        key: AgentStreamBottomMaxYKey.self,
                                        value: g.frame(in: .global).maxY
                                    )
                                }
                            )
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            // P29 §4 — publish the ScrollView's global bounds so we
            // can decide whether the BOTTOM sentinel is inside the
            // visible viewport.
            .background(
                GeometryReader { g in
                    Color.clear.preference(
                        key: AgentStreamViewportMaxYKey.self,
                        value: g.frame(in: .global).maxY
                    )
                }
            )
            .onPreferenceChange(AgentStreamBottomMaxYKey.self) { bottomMaxY = $0 }
            .onPreferenceChange(AgentStreamViewportMaxYKey.self) { viewportMaxY = $0 }
            .overlay(alignment: .bottomTrailing) {
                jumpToLatestPill(proxy: proxy)
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

    /// P29 §4 — floating "jump to latest" pill. Hidden when the user
    /// is already at the bottom; appears with a soft fade when they
    /// scroll up. Tap → smoothly scrolls back to the BOTTOM anchor.
    @ViewBuilder
    private func jumpToLatestPill(proxy: ScrollViewProxy) -> some View {
        Button {
            let animation: Animation? = reduceMotion ? nil : .easeOut(duration: 0.22)
            withAnimation(animation) {
                proxy.scrollTo("BOTTOM", anchor: .bottom)
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SmoothieColor.textSecondary)
                .frame(width: 36, height: 36)
                .background(SmoothieColor.bgCard, in: .circle)
                .overlay(
                    Circle().strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.bottom, 16)
        .opacity(isAtBottom ? 0 : 1)
        .scaleEffect(isAtBottom ? 0.85 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isAtBottom)
        .allowsHitTesting(!isAtBottom)
        .accessibilityLabel("Jump to latest message")
    }

    /// Build a Set<id> ↔ Bool binding for the per-card expanded chevron.
    /// The Set lives on `SessionLiveStore` so it survives view recycles
    /// when the LazyVStack reuses ToolCallCard instances during scroll.
    private func expandBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandStore.expandedCardIds.contains(id) },
            set: { newValue in
                if newValue { expandStore.expandedCardIds.insert(id) }
                else        { expandStore.expandedCardIds.remove(id) }
            }
        )
    }

    private func resultExpandBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandStore.expandedResultIds.contains(id) },
            set: { newValue in
                if newValue { expandStore.expandedResultIds.insert(id) }
                else        { expandStore.expandedResultIds.remove(id) }
            }
        )
    }

    /// Picks the SF Symbol that fronts a tool card. File-mutating tools
    /// reuse the document glyph; Claude's `Task` tool gets a distinct
    /// people glyph so subagent invocations stand out from regular tool
    /// calls in a busy stream. Everything else falls back to the generic
    /// wrench so adapter-emitted tools (Read, Grep, Bash, Glob, etc.)
    /// share a single visual lane.
    private func iconForTool(_ use: SmoothieEventWire) -> String {
        if use.type == .fileEdit {
            return "doc.text.fill"
        }
        switch use.content {
        case "Task":         return "person.2.fill"
        case "Bash":         return "terminal.fill"
        case "Read":         return "doc.text"
        case "Grep":         return "magnifyingglass"
        case "Glob":         return "asterisk"
        case "WebFetch",
             "WebSearch":    return "globe"
        default:             return "wrench.adjustable"
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
        .smoothieCard(cornerRadius: SmoothieMetrics.cornerCard, elevated: true)
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
                ProgressView().controlSize(.regular).tint(SmoothieColor.accent)
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
            case .unknown:
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textTertiary)
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
            case .unknown:             return "Unknown session state"
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
            case .unknown:
                return "This iOS build doesn't recognise the daemon's session state. Update the app or check release notes."
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
                        .fill(SmoothieColor.accent)
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

/// One visual row in the agent stream. Either a single event, a single
/// tool invocation paired with its optional result, or a collapsed run
/// of same-name tool calls (`Bash ×3`).
// P29 §4 — PreferenceKeys used by AgentStream to track the BOTTOM
// sentinel's position relative to the ScrollView's viewport. When
// the sentinel sits below the visible region, the jump-to-latest
// pill becomes visible. Both keys store a single CGFloat (last
// reporter wins).

private struct AgentStreamBottomMaxYKey: PreferenceKey {
    // Swift 6 strict-concurrency: PreferenceKey's `defaultValue` is
    // declared `{ get }`, so a stored `let` constant satisfies the
    // requirement without the "nonisolated global shared mutable
    // state" error a `var` would produce.
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct AgentStreamViewportMaxYKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct AgentStreamItem: Identifiable {
    enum Kind {
        case event(SmoothieEventWire)
        case toolStack(name: String, members: [SmoothieEventWire])
        case toolCard(use: SmoothieEventWire, result: SmoothieEventWire?)
        /// P29 §3 — `.fileEdit` events render via the new
        /// `FileChangesPanel` instead of a generic `.toolCard`. The
        /// panel pulls the diff out of the event's metadata and
        /// shows inline +/- rows.
        case fileChanges(event: SmoothieEventWire)
    }
    let kind: Kind
    let id: String

    /// Walk `events` and produce the visual rows:
    /// - `.fileEdit` becomes a standalone `.toolCard` (no result pairing).
    /// - A singleton `.toolUse` pairs with its immediately-following
    ///   `.toolResult` into one `.toolCard`.
    /// - 2+ consecutive same-name `.toolUse` events collapse into a
    ///   single `.toolStack` (rendered as a `ToolCallCard` with a ×N
    ///   stack badge).
    /// - Everything else passes through as `.event`.
    /// Divider events (a `.toolResult` carrying `metadata.divider`) are
    /// never absorbed into a tool run — they stay as standalone rows so
    /// `EventRow`'s divider renderer fires.
    static func collapse(_ events: [SmoothieEventWire]) -> [AgentStreamItem] {
        var out: [AgentStreamItem] = []
        var i = 0
        while i < events.count {
            let e = events[i]

            if e.type == .fileEdit {
                // P29 §3 — emit the inline FileChangesPanel item instead
                // of a generic .toolCard. The panel renders the real
                // before/after diff inline in the stream.
                out.append(AgentStreamItem(kind: .fileChanges(event: e), id: e.id))
                i += 1
                continue
            }

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
                } else if next.type == .toolResult && EventRow.dividerLabel(for: next) == nil {
                    run.append(next); j += 1
                } else {
                    break
                }
            }
            let useCount = run.filter { $0.type == .toolUse }.count
            if useCount >= 2 {
                out.append(AgentStreamItem(kind: .toolStack(name: name, members: run), id: e.id))
            } else {
                let use = run.first(where: { $0.type == .toolUse })!
                // Pair the tool_use with EVERY following tool_result up to
                // the next break. The prior implementation took only the
                // first result via `first(where:)` and dropped any 2nd+,
                // which manifested as missing output text for tools that
                // streamed multiple chunks (e.g. a Bash run with stdout +
                // stderr arriving as separate frames). Joining preserves
                // the full output for the user.
                let results = run.filter { $0.type == .toolResult }
                let combined: SmoothieEventWire?
                if results.isEmpty {
                    combined = nil
                } else if results.count == 1 {
                    combined = results[0]
                } else {
                    let joined = results.map(\.content).joined(separator: "\n\n──\n\n")
                    combined = SmoothieEventWire(
                        type: .toolResult,
                        content: joined,
                        metadata: results[0].metadata,
                        timestamp: results[0].timestamp
                    )
                }
                out.append(AgentStreamItem(kind: .toolCard(use: use, result: combined), id: use.id))
            }
            i = j
        }
        return out
    }
}

/// Card for a run of N same-name tool calls. Reuses `ToolCallCard` with
/// the stack-count badge so the visual surface is identical to a
/// singleton tool card — just with a `×N` chip in the header. Args are
/// borrowed from the first call in the run (representative); all
/// emitted results are joined and rendered inside the card's result
/// block.
private struct ToolStackRow: View {
    let name: String
    let members: [SmoothieEventWire]
    /// P29 §5 — propagated from AgentStream so the stacked tool
    /// card uses the same brand-color top stripe as its singleton
    /// peers.
    var cli: CLIWire? = nil
    let expandBinding: Binding<Bool>
    let resultExpandBinding: Binding<Bool>

    private var useCount: Int {
        members.filter { $0.type == .toolUse }.count
    }

    private var firstUse: SmoothieEventWire? {
        members.first(where: { $0.type == .toolUse })
    }

    private var combinedResult: String? {
        let results = members.filter { $0.type == .toolResult }.map { $0.content }
        guard !results.isEmpty else { return nil }
        return results.joined(separator: "\n\n──\n\n")
    }

    private var isSubagentStack: Bool { name == "Task" }

    private var stackIcon: String {
        if isSubagentStack { return "person.2.fill" }
        switch name {
        case "Bash":              return "terminal.fill"
        case "Read":              return "doc.text"
        case "Grep":              return "magnifyingglass"
        case "Glob":              return "asterisk"
        case "WebFetch",
             "WebSearch":         return "globe"
        default:                  return "wrench.adjustable"
        }
    }

    var body: some View {
        ToolCallCard(
            icon: stackIcon,
            name: name,
            status: combinedResult != nil ? .completed : .running,
            inputFields: firstUse.map {
                EventRow.inputFields(from: $0, hidingKeys: isSubagentStack ? ["subagent_type"] : [])
            } ?? [],
            result: combinedResult,
            stackCount: useCount,
            tint: isSubagentStack ? SmoothieColor.accent : SmoothieColor.textPrimary.opacity(0.85),
            subtitleBadge: isSubagentStack
                ? (firstUse.flatMap { EventRow.subagentType(from: $0) } ?? "subagent")
                : nil,
            emphasised: isSubagentStack,
            cli: cli,
            expanded: expandBinding,
            resultExpanded: resultExpandBinding
        )
    }
}

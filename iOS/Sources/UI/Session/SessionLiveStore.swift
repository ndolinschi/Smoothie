import SwiftUI
import WidgetKit

/// Observable backbone for one SessionView. Owns the SSE connection,
/// the event ring buffer, the visible session state machine, the queued
/// soft-mode-switch divider plumbing, and the widget-snapshot mirror.
/// Extracted from SessionView.swift in P24.d D1 — the previous inline
/// definition pushed that file to ~550 LOC and obscured the view layer
/// proper.
///
/// Threading: every mutating method runs on the MainActor. SSE callbacks
/// hop here via `Task { @MainActor in … }`. The Kotlin shared
/// framework is not touched directly — wire types are decoded by
/// `SSEClient` on its delegate queue and handed off as already-validated
/// `SmoothieEventWire` values.
@MainActor
@Observable
final class SessionLiveStore {
    private(set) var events: [SmoothieEventWire] = []
    private(set) var state: SessionStateWire
    /// Live SSE connection state — drives the connection banner. Starts at
    /// `.connecting` so the user sees feedback the moment SessionView mounts
    /// rather than a blank period before the first `urlSession` callback.
    private(set) var connection: SSEClient.State = .connecting
    /// True once we've seen at least one event arrive from the server — used
    /// by AgentStream to switch from "waiting for first reply…" placeholder
    /// to the real stream view.
    private(set) var hasReceivedEvent: Bool = false
    /// Surfaced inside the banner when reconnect attempts fail.
    private(set) var error: String?
    /// Per-tool-card expansion bookkeeping. The card itself can't own this
    /// state — it sits inside `LazyVStack` and gets recycled when scrolled
    /// off-screen, which would otherwise reset the expanded chevron every
    /// time. Keying by event id keeps the state stable across recycles for
    /// the lifetime of the session.
    var expandedCardIds: Set<String> = []
    var expandedResultIds: Set<String> = []
    /// Latest token-budget snapshot the daemon pushed via SSE
    /// `context_update` events. `nil` means the daemon hasn't told us
    /// yet (or this build is older than the daemon endpoint) — the
    /// status footer hides the percent ring in that case.
    private(set) var contextSnapshot: ContextSnapshotWire?
    /// Mode switch requested by the user. Flushed when state leaves
    /// `.thinking` so the divider appears AFTER the in-flight turn rather
    /// than interrupting it.
    private var pendingMode: String?

    /// P29 §8 — exposed read-only flag so the composer action strip can
    /// surface a `Plan` chip while a mode preamble is staged. The
    /// preamble itself is consumed by `consumePendingModePreamble()`
    /// on the next outgoing turn.
    var hasPendingModePreamble: Bool { pendingMode != nil }

    /// P29 §8 — drop the staged preamble without sending it. Backs the
    /// "Clear" button in the Plan chip's popover.
    func clearPendingModePreamble() {
        pendingMode = nil
    }

    private var sse: SSEClient?
    private var api: APIClient?
    /// True once any SSE handshake has completed. The daemon replays the
    /// full event backlog on EVERY new connection, so on re-connects the
    /// ring must be cleared first — otherwise each reconnect (manual, or
    /// the automatic one URLSession forces at the 10-minute resource
    /// timeout) appends a second copy of the entire history.
    private var hadConnection = false
    let session: SessionDescriptorWire

    /// Convenience flag — true once the SSE handshake has completed.
    var connected: Bool {
        if case .connected = connection { return true }
        return false
    }

    /// True once the session ring contains a content-bearing event —
    /// MESSAGE, THINKING, TOOL_USE, TOOL_RESULT, or FILE_EDIT. Non-
    /// content events (CONTEXT_UPDATE side-channel snapshots, UNKNOWN
    /// forward-compat slots, WAITING/DONE/ERROR/LIMIT state pings) do
    /// NOT flip this — they exist on a brand-new session that hasn't
    /// had any user input yet. SessionView uses this in place of the
    /// older `events.isEmpty` so the SuggestionsBar doesn't flicker
    /// when the daemon emits an early context_update / state ping.
    var hasUserContent: Bool {
        events.contains { event in
            switch event.type {
            case .message, .thinking, .toolUse, .toolResult, .fileEdit:
                return true
            case .contextUpdate, .unknown, .waiting, .done, .error, .limitReached:
                return false
            }
        }
    }

    init(session: SessionDescriptorWire) {
        self.session = session
        self.state = session.state
    }

    func connect(api: APIClient) {
        self.api = api
        guard sse == nil, let url = api.streamURL(sessionId: session.id),
              let bearer = api.store.current?.token else { return }
        let onEvent: @Sendable (SmoothieEventWire) -> Void = { [weak self] event in
            Task { @MainActor in self?.ingest(event) }
        }
        let onState: @Sendable (SSEClient.State) -> Void = { [weak self] state in
            Task { @MainActor in self?.update(connectionState: state) }
        }
        let client = SSEClient(url: url, bearer: bearer, onEvent: onEvent, onState: onState)
        sse = client
        client.start()
    }

    func disconnect() {
        sse?.stop()
        sse = nil
    }

    /// Decode the JSON snapshot the daemon stuffed into a
    /// `context_update` event's `metadata` payload and publish it as
    /// `contextSnapshot` for the status footer to read. Tolerant of
    /// missing / malformed payloads — a bad snapshot just leaves the
    /// previous good one in place rather than crashing the SSE stream.
    private func applyContextUpdate(_ event: SmoothieEventWire) {
        guard let metadata = event.metadata,
              let snapshotValue = metadata["snapshot"]
        else { return }
        // metadata is [String: AnyCodable] — round-trip via JSON to
        // decode the nested ContextSnapshotWire without writing a
        // bespoke decoder.
        do {
            let data = try JSONEncoder().encode(snapshotValue)
            let snapshot = try JSONDecoder().decode(ContextSnapshotWire.self, from: data)
            self.contextSnapshot = snapshot
        } catch {
            // Bad payload — silently keep the previous snapshot.
            _ = error
        }
    }

    /// Force a fresh SSE connection from scratch. Used by the
    /// ConnectionBanner's "Reconnect" button so the user can bypass the
    /// retry backoff after a transient blip, or take a manual stab at
    /// recovery after a `.gone` (which usually reproduces the gone state,
    /// but at least gives the user agency over the link).
    func reconnect() {
        guard let api else { return }
        // Reset transient surfaces so the banner doesn't show stale
        // "retrying in 7s" copy from the prior client.
        error = nil
        connection = .connecting
        disconnect()
        connect(api: api)
    }

    private func ingest(_ event: SmoothieEventWire) {
        // Side-channel: context_update events carry the latest token
        // budget snapshot in metadata and DO NOT belong in the visible
        // event ring. Decode, update the published snapshot, return.
        if event.type == .contextUpdate {
            applyContextUpdate(event)
            hasReceivedEvent = true
            return
        }
        // Streaming text — opencode-style adapters emit a MESSAGE event
        // per delta tagged with the same `partId` metadata. Replace any
        // existing MESSAGE event with the same partId in place so the
        // bubble grows in real time instead of producing N stacked
        // duplicates. The replacement reuses the original event's id
        // via `events[idx] = event` so SwiftUI's LazyVStack diffing
        // sees an in-place update.
        if event.type == .message,
           let partId = event.metadata?["partId"]?.stringValue,
           !partId.isEmpty,
           let idx = events.lastIndex(where: { $0.metadata?["partId"]?.stringValue == partId })
        {
            events[idx] = event
            hasReceivedEvent = true
            // Streaming deltas count as agent activity → keep the
            // session state in `.thinking` until the host sends DONE
            // or WAITING.
            state = .thinking
            return
        }
        events.append(event)
        hasReceivedEvent = true
        if events.count > 2000 {
            var cutCount = events.count - 2000
            // Extend the cut forward through any leading `.toolResult`
            // events — without this, naïve `removeFirst(N)` can leave a
            // toolResult at the new head without its paired toolUse,
            // which `AgentStream.collapse` then renders as a phantom
            // free-floating result block. By including those orphans in
            // the cut, the next-most-recent toolUse becomes the new
            // head of the ring.
            while cutCount < events.count, events[cutCount].type == .toolResult {
                cutCount += 1
            }
            let removed = events[..<cutCount]
            // Free any expand-state bookkeeping for cards that just left
            // the visible window so the per-id sets don't grow unbounded
            // over a very long session.
            for e in removed {
                expandedCardIds.remove(e.clientId)
                expandedResultIds.remove(e.clientId)
            }
            events.removeFirst(cutCount)
        }
        let priorState = state
        switch event.type {
        case .waiting:      state = .waiting
        case .done:         state = .done
        case .error:        state = .error
        case .limitReached: state = .limitReached
        case .message, .thinking, .toolUse, .toolResult, .fileEdit:
            state = .thinking
        case .contextUpdate:
            // Already handled via applyContextUpdate before reaching
            // this switch — including the case here just keeps the
            // exhaustive-switch compiler happy.
            break
        case .unknown:
            // Forward-compat: unrecognised event from a newer daemon —
            // don't move the state machine, just keep the event in the
            // ring so any subsequent recognised event flows through.
            break
        }
        if state != priorState {
            publishWidgetSnapshot()
            // Mode instructions are now lazy — the buffer is drained by
            // SessionView.sendMessage prepending the preamble to the
            // user's next outgoing turn (consumePendingModePreamble).
            // No SSE-driven auto-flush.
        }
    }

    /// Queue a soft mode switch. The divider is drawn immediately so the
    /// transcript marks the boundary, but the actual instruction text
    /// is buffered and prepended to the user's NEXT outgoing message
    /// (see `consumePendingModePreamble`). The previous behaviour fired
    /// off the "Switch to Plan mode…" prompt the moment the user
    /// flipped the toggle, which burned a turn and surprised the agent
    /// with an unexpected directive before any user intent had landed.
    func queueModeChange(_ mode: String) {
        pendingMode = mode

        let label = mode.lowercased() == "plan" ? "plan mode" : "code mode"
        // Mark the divider via metadata rather than the sentinel-prefix
        // hack we used in P17. The metadata flag is one we control;
        // a literal `__SMOOTHIE_DIVIDER__::` in the agent's stream
        // (e.g. the user asks "echo that string back to me") can no
        // longer hijack the divider renderer. EventRow checks the
        // metadata flag first, then falls back to the sentinel for
        // any events still buffered from before this push.
        let divider = SmoothieEventWire(
            type: .toolResult,
            content: label,
            metadata: ["divider": AnyCodable(label)],
            timestamp: Int64(Date.now.timeIntervalSince1970 * 1000)
        )
        events.append(divider)
    }

    /// Optimistically append a USER-authored MESSAGE event to the
    /// visible ring. The daemon doesn't echo the user's turn back as
    /// an event today (CLIs see it on stdin, agent reply comes via
    /// stream-json), so the iOS chat would otherwise jump straight
    /// from "Ready when you are" to the assistant's response with no
    /// trace of what the user typed. Marking it with `role: user`
    /// metadata lets EventRow render it as a right-aligned chat
    /// bubble distinct from agent prose.
    func appendUserMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let event = SmoothieEventWire(
            type: .message,
            content: trimmed,
            metadata: ["role": AnyCodable("user")],
            timestamp: Int64(Date.now.timeIntervalSince1970 * 1000)
        )
        events.append(event)
    }

    /// Called by SessionView's send path just before the user's text
    /// hits the daemon. Returns the buffered mode instruction (if any)
    /// so the caller can prepend it to the outgoing message. Clears the
    /// buffer so the same instruction isn't re-sent on the next turn.
    func consumePendingModePreamble() -> String? {
        guard let mode = pendingMode else { return nil }
        pendingMode = nil
        switch mode.lowercased() {
        case "plan":
            return "Switch to Plan mode. From now on, explore the code and present a plan before making any edits. Do not modify any files until I explicitly approve a step. Keep replies focused on planning."
        default:
            return "Switch back to Code mode. You may apply edits directly again."
        }
    }

    /// Mirror the most-recent session state into the App Group container for
    /// the Lock Screen / Home Screen widget. Called only when state actually
    /// transitions, so disk writes stay infrequent.
    private func publishWidgetSnapshot() {
        let snapshot = WidgetSnapshot(
            sessionId: session.id,
            projectName: session.projectName,
            cli: session.cli.snapshotCLI,
            state: state.snapshotState,
            lastEventAt: .now
        )
        WidgetSnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func update(connectionState: SSEClient.State) {
        connection = connectionState
        switch connectionState {
        case .connecting, .stopped: break
        case .connected:
            error = nil
            if hadConnection {
                // Fresh connection → the server is about to replay its
                // whole backlog. Drop the current ring (and its expand
                // bookkeeping) so the replay repopulates it instead of
                // duplicating every row.
                events.removeAll()
                expandedCardIds.removeAll()
                expandedResultIds.removeAll()
            }
            hadConnection = true
        case .retrying(let s):      error = "Reconnecting in \(s)s…"
        case .gone(let reason):
            // SSE landed on a terminal 404/401/410. Flip the visible
            // session state so the UI shows ERROR rather than the
            // previous (now-misleading) THINKING / WAITING. The user
            // sees the gone-reason in the connection banner AND a
            // matching error event row in the stream — both clear that
            // the daemon-side session is dead.
            state = .error
            error = reason
        }
    }
}

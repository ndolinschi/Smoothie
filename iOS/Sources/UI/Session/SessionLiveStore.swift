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
    /// Mode switch requested by the user. Flushed when state leaves
    /// `.thinking` so the divider appears AFTER the in-flight turn rather
    /// than interrupting it.
    private var pendingMode: String?

    private var sse: SSEClient?
    private var api: APIClient?
    let session: SessionDescriptorWire

    /// Convenience flag (kept for the existing StatusBadge call sites).
    var connected: Bool {
        if case .connected = connection { return true }
        return false
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
        case .unknown:
            // Forward-compat: unrecognised event from a newer daemon —
            // don't move the state machine, just keep the event in the
            // ring so any subsequent recognised event flows through.
            break
        }
        if state != priorState {
            publishWidgetSnapshot()
            // Drain a queued mode change once the turn has finished
            // thinking — the divider lands AFTER the visible work.
            if pendingMode != nil, state != .thinking {
                Task { await flushModeChange() }
            }
        }
    }

    /// Queue a soft mode switch. If the session is idle (any state other
    /// than `.thinking`) we flush immediately; otherwise the next
    /// `ingest(_:)` state transition will trigger the flush.
    func queueModeChange(_ mode: String) {
        pendingMode = mode
        if state != .thinking {
            Task { await flushModeChange() }
        }
    }

    private func flushModeChange() async {
        guard let mode = pendingMode else { return }
        pendingMode = nil

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

        guard let api else { return }
        let instruction: String
        switch mode.lowercased() {
        case "plan":
            instruction = "Switch to Plan mode. From now on, explore the code and present a plan before making any edits. Do not modify any files until I explicitly approve a step. Keep replies focused on planning."
        default:
            instruction = "Switch back to Code mode. You may apply edits directly again."
        }
        _ = try? await api.sendMessage(sessionId: session.id, content: instruction)
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
        case .connected:            error = nil
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

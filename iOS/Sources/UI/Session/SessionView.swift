import SwiftUI
import WidgetKit

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

    private func ingest(_ event: SmoothieEventWire) {
        events.append(event)
        hasReceivedEvent = true
        if events.count > 2000 {
            events.removeFirst(events.count - 2000)
        }
        let priorState = state
        switch event.type {
        case .waiting:      state = .waiting
        case .done:         state = .done
        case .error:        state = .error
        case .limitReached: state = .limitReached
        case .message, .thinking, .toolUse, .toolResult, .fileEdit:
            state = .thinking
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

struct SessionView: View {
    let session: SessionDescriptorWire
    @Environment(PairingStore.self) private var pairing
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var currentSession: SessionDescriptorWire
    @State private var store: SessionLiveStore?
    @State private var features: ProviderFeaturesWire?
    @State private var allAdapters: [AdapterInfoWire] = []
    @State private var confirmKill = false
    @State private var switchError: String?
    @State private var lastNotifiedState: SessionStateWire?
    @State private var showingModeSheet = false
    @State private var showingDiffSheet = false
    @State private var showingModelSheet = false

    enum SwitchTarget: Identifiable, Equatable {
        case model(String)
        case effort(String)
        case mode(String)
        case provider(CLIWire)

        var id: String {
            switch self {
            case .model(let s): return "model:\(s)"
            case .effort(let s): return "effort:\(s)"
            case .mode(let s): return "mode:\(s)"
            case .provider(let c): return "provider:\(c.rawValue)"
            }
        }

        var label: String {
            switch self {
            case .model(let s): return "model = \(s)"
            case .effort(let s): return "reasoning effort = \(s)"
            case .mode(let s): return "mode = \(s)"
            case .provider(let c): return "provider = \(c.displayName)"
            }
        }
    }

    /// Pairing id this SessionView was opened against. Captured at init
    /// so we can detect the user removing or switching pairings mid-
    /// session — SessionView dismisses itself in that case rather than
    /// continuing to drive a dead daemon.
    @State private var originPairingId: String?

    init(session: SessionDescriptorWire) {
        self.session = session
        _currentSession = State(initialValue: session)
    }

    private var toolbarSubtitle: String {
        let modeLabel = (currentSession.mode ?? "default")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        return "\(currentSession.cli.displayName) · \(modeLabel)"
    }

    /// Friendly model name (e.g. `sonnet` → `Claude Sonnet 4.6`). Falls
    /// back to the CLI's display name when the session has no explicit
    /// model set.
    private var modelChipLabel: String {
        if let model = currentSession.model, !model.isEmpty {
            return currentSession.cli.friendlyModelName(model)
        }
        return currentSession.cli.displayName
    }

    /// Lowercase mode token for the cloud chip below the model.
    private var modeChipLabel: String {
        (currentSession.mode ?? "default")
            .replacingOccurrences(of: "_", with: " ")
    }

    var body: some View {
        ZStack {
            SmoothieColor.bgPrimary.ignoresSafeArea()
            if let store {
                VStack(spacing: 8) {
                    ConnectionBanner(
                        connection: store.connection,
                        state: store.state,
                        hasReceivedEvent: store.hasReceivedEvent
                    )
                    .animation(.easeInOut(duration: 0.2), value: store.connected)
                    .animation(.easeInOut(duration: 0.2), value: store.hasReceivedEvent)
                    AgentStream(
                        events: store.events,
                        connection: store.connection,
                        state: store.state
                    )
                    if !store.events.isEmpty {
                        ActionChipsRow(
                            events: store.events,
                            onPlanTap: { showingModeSheet = true },
                            onDiffTap: { showingDiffSheet = true }
                        )
                    }
                    MessageInput(
                        session: currentSession,
                        features: features,
                        allAdapters: allAdapters,
                        isFreshSession: store.events.isEmpty,
                        sessionState: store.state,
                        onSend: { text, attachments in
                            let composed = attachments.composedMessage(with: text)
                            await sendMessage(composed, images: attachments.images)
                        },
                        onAbort: { Task { await abortTurn() } },
                        onSwitchModel: { m in await applyRestart(.model(m)) },
                        onSwitchEffort: { e in await applyRestart(.effort(e)) },
                        onSwitchMode: { applyMode($0) },
                        onSwitchProvider: { c in await applyRestart(.provider(c)) },
                        onTapMode: { showingModeSheet = true }
                    )
                }
            } else {
                ProgressView().tint(SmoothieColor.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(SmoothieColor.bgPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 4) {
                    Button {
                        showingModelSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(modelChipLabel)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(SmoothieColor.textPrimary)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(SmoothieColor.textSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 6) {
                        Button {
                            showingModeSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "cloud")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(SmoothieColor.textSecondary)
                                Text(modeChipLabel)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(SmoothieColor.textSecondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .overlay(
                                Capsule().strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        if let store, store.state != .done, store.state != .error {
                            StatusBadge(state: store.state, connected: store.connected)
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await handoffToTerminal() }
                    } label: {
                        Label("Open in Terminal on Mac", systemImage: "terminal")
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmKill = true
                    } label: {
                        Label("Kill session", systemImage: "stop.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SmoothieColor.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(SmoothieColor.bgCard, in: .circle)
                        .overlay(Circle().strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5))
                        .contentShape(Circle())
                }
            }
        }
        .sheet(isPresented: $showingModeSheet) {
            ModeSheet(
                session: currentSession,
                features: features,
                onPick: { applyMode($0) },
                onDismiss: { showingModeSheet = false }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(20)
        }
        .sheet(isPresented: $showingDiffSheet) {
            DiffSheet(
                events: store?.events ?? [],
                onSend: { body in await sendMessage(body) },
                onDismiss: { showingDiffSheet = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(20)
        }
        .sheet(isPresented: $showingModelSheet) {
            if let f = features {
                ModelPickerSheet(
                    currentModel: currentSession.model,
                    currentEffort: currentSession.reasoningEffort,
                    features: f,
                    onPickModel: { m in await applyRestart(.model(m)) },
                    onPickEffort: { e in await applyRestart(.effort(e)) }
                )
                .presentationDetents([.medium, .large])
                .presentationBackground(.clear)
            }
        }
        .onAppear {
            // Remember which pairing this session belongs to so we can
            // bail out if it gets removed or switched while we're still
            // pushed on the stack.
            if originPairingId == nil {
                originPairingId = pairing.activeId
            }
            connectStore()
            Task { await loadFeatures() }
        }
        .onDisappear {
            store?.disconnect()
        }
        .onChange(of: store?.state) { _, new in
            guard let new else { return }
            handlePotentialNotification(state: new)
        }
        .onChange(of: pairing.activeId) { _, new in
            // User removed the active Mac (or switched to a different
            // one). The current session lives on the OLD pairing's
            // daemon — keep driving it would 404. Tear down the live
            // store and pop back to HomeView.
            guard let origin = originPairingId else { return }
            if new == nil || new != origin {
                store?.disconnect()
                dismiss()
            }
        }
        .alert("Kill session?", isPresented: $confirmKill) {
            Button("Kill", role: .destructive) {
                Task { await killSession() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This terminates the agent process on your Mac.")
        }
        .alert("Couldn't switch", isPresented: Binding(
            get: { switchError != nil },
            set: { if !$0 { switchError = nil } }
        )) {
            Button("OK", role: .cancel) { switchError = nil }
        } message: {
            Text(switchError ?? "")
        }
    }

    // MARK: - Lifecycle

    private func connectStore() {
        guard store == nil else { return }
        let s = SessionLiveStore(session: currentSession)
        s.connect(api: APIClient(store: pairing))
        store = s
    }

    private func loadFeatures() async {
        let api = APIClient(store: pairing)
        do {
            let adapters = try await api.adapters()
            allAdapters = adapters
            features = adapters.first { $0.cli == currentSession.cli }?.features
        } catch {
            // non-fatal; ComposerMenu degrades gracefully
        }
    }

    /// Hand the active session off to the Mac's Terminal.app. The daemon
    /// kills its subprocess and runs `osascript` so the user can keep
    /// typing in Terminal. We disconnect the SSE first so late frames
    /// don't show up after we've moved on, then pop back to HomeView —
    /// the session shows up as `done` on the next refresh, and the user
    /// can resume from there.
    private func handoffToTerminal() async {
        let api = APIClient(store: pairing)
        store?.disconnect()
        do {
            _ = try await api.openTerminal(sessionId: currentSession.id)
        } catch {
            switchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            // Re-connect so the user isn't stranded on a dead SSE if the
            // handoff failed (e.g. user denied Terminal automation perm).
            store?.connect(api: api)
            return
        }
        dismiss()
    }

    private func handlePotentialNotification(state: SessionStateWire) {
        guard scenePhase != .active else {
            lastNotifiedState = state
            return
        }
        guard state != lastNotifiedState else { return }
        lastNotifiedState = state
        switch state {
        case .waiting:
            LocalNotifier.shared.notifyWaiting(projectName: currentSession.projectName, sessionId: currentSession.id)
        case .done:
            LocalNotifier.shared.notifyDone(projectName: currentSession.projectName, sessionId: currentSession.id)
        case .limitReached:
            LocalNotifier.shared.notifyLimitReached(projectName: currentSession.projectName, sessionId: currentSession.id)
        default:
            break
        }
    }

    /// Soft mode switch — no process restart, no confirmation dialog. The
    /// mode chip flips immediately and the live store renders a divider in
    /// the stream once the in-flight turn (if any) settles.
    private func applyMode(_ mode: String) {
        let normalised = mode.lowercased() == "default" ? nil : mode
        currentSession = currentSession.withMode(normalised)
        store?.queueModeChange(mode)
    }

    private func sendMessage(_ content: String, images: [StagedImage] = []) async {
        let api = APIClient(store: pairing)
        do {
            try await api.sendMessage(
                sessionId: currentSession.id,
                content: content,
                images: images
            )
        } catch {
            // SSE error event surfaces server-side failures
        }
    }

    private func killSession() async {
        let api = APIClient(store: pairing)
        _ = try? await api.killSession(sessionId: currentSession.id)
        dismiss()
    }

    private func abortTurn() async {
        let api = APIClient(store: pairing)
        _ = try? await api.abortSession(sessionId: currentSession.id)
    }

    // MARK: - Silent restart for setting changes

    /// Apply a model / effort / provider switch with the same silent UX as
    /// `applyMode`: no confirmation dialog, no full-screen spinner. The old
    /// process is terminated in the background while we create a fresh
    /// session with the new args; the composer chip updates immediately so
    /// the change feels instantaneous. Events from the old session stay
    /// visible until the new SSE stream takes over.
    private func applyRestart(_ target: SwitchTarget) async {
        let api = APIClient(store: pairing)

        let cli: CLIWire = {
            if case .provider(let c) = target { return c }
            return currentSession.cli
        }()
        let providerChanged = cli != currentSession.cli
        let model: String? = {
            if case .model(let m) = target { return m }
            return providerChanged ? nil : currentSession.model
        }()
        let effort: String? = {
            if case .effort(let e) = target { return e }
            return providerChanged ? nil : currentSession.reasoningEffort
        }()
        let mode: String? = {
            if case .mode(let m) = target { return m }
            return providerChanged ? nil : currentSession.mode
        }()

        // Snapshot the previous store so we can resume it on failure (don't
        // strand the user on a stopped stream if create fails).
        let previousStore = store
        let oldId = currentSession.id

        // Stop the old SSE FIRST so late URLSession callbacks can't slip
        // events into a store we're about to replace. We previously did
        // this in the wrong order; events that arrived during the
        // await-createSession window were attributed to the old store and
        // then discarded, which was OK but caused brief duplicate rows on
        // slower networks.
        previousStore?.disconnect()
        Task.detached { _ = try? await api.killSession(sessionId: oldId) }

        do {
            let req = CreateSessionRequestWire(
                projectPath: currentSession.projectPath,
                cli: cli,
                model: model,
                reasoningEffort: effort,
                mode: mode
            )
            let new = try await api.createSession(req)
            currentSession = new
            let s = SessionLiveStore(session: new)
            s.connect(api: api)
            store = s
            await loadFeatures()
        } catch {
            switchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            // Failure: reconnect the previous session's SSE so the user
            // can keep typing without losing the live link.
            previousStore?.connect(api: api)
        }
    }
}

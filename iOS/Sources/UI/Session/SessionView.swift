import SwiftUI
import WidgetKit

@MainActor
@Observable
final class SessionLiveStore {
    private(set) var events: [SmoothieEventWire] = []
    private(set) var state: SessionStateWire
    private(set) var connected: Bool = false
    private(set) var error: String?
    /// Mode switch requested by the user. Flushed when state leaves
    /// `.thinking` so the divider appears AFTER the in-flight turn rather
    /// than interrupting it.
    private var pendingMode: String?

    private var sse: SSEClient?
    private var api: APIClient?
    let session: SessionDescriptorWire

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
        let divider = SmoothieEventWire(
            type: .toolResult,
            content: "__SMOOTHIE_DIVIDER__::\(label)",
            metadata: nil,
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
        switch connectionState {
        case .connecting:        connected = false
        case .connected:         connected = true; error = nil
        case .retrying(let s):   connected = false; error = "Reconnecting in \(s)s…"
        case .stopped:           connected = false
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
    @State private var switching: SwitchTarget?
    @State private var restarting = false
    @State private var switchError: String?
    @State private var lastNotifiedState: SessionStateWire?
    @State private var showingModeSheet = false
    @State private var showingDiffSheet = false

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

    var body: some View {
        ZStack {
            SmoothieColor.bgPrimary.ignoresSafeArea()
            if restarting {
                VStack(spacing: 12) {
                    ProgressView().tint(SmoothieColor.textSecondary)
                    Text("Restarting session…")
                        .font(.system(size: 13))
                        .foregroundStyle(SmoothieColor.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let store {
                VStack(spacing: 8) {
                    AgentStream(events: store.events)
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
                        onSend: { text, attachments in
                            let composed = attachments.composedMessage(with: text)
                            await sendMessage(composed)
                        },
                        onSwitchModel: { switching = .model($0) },
                        onSwitchEffort: { switching = .effort($0) },
                        onSwitchMode: { applyMode($0) },
                        onSwitchProvider: { switching = .provider($0) },
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
                VStack(spacing: 2) {
                    Text(currentSession.projectName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SmoothieColor.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(toolbarSubtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(SmoothieColor.textSecondary)
                            .lineLimit(1)
                        if let store, store.state != .done, store.state != .error {
                            StatusBadge(state: store.state, connected: store.connected)
                        }
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        switching = .model(currentSession.model ?? "")
                    } label: {
                        Label("Switch model…", systemImage: "cube")
                    }
                    Button(role: .destructive) {
                        confirmKill = true
                    } label: {
                        Label("Kill session", systemImage: "stop.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SmoothieColor.textPrimary)
                        .frame(width: SmoothieMetrics.topCircle, height: SmoothieMetrics.topCircle)
                        .contentShape(Rectangle())
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
        .onAppear {
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
        .alert("Kill session?", isPresented: $confirmKill) {
            Button("Kill", role: .destructive) {
                Task { await killSession() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This terminates the agent process on your Mac.")
        }
        .confirmationDialog(
            "Restart session?",
            isPresented: Binding(
                get: { switching != nil },
                set: { if !$0 { switching = nil } }
            ),
            presenting: switching
        ) { target in
            Button("Restart with \(target.label)", role: .destructive) {
                Task { await restart(with: target) }
            }
            Button("Cancel", role: .cancel) { switching = nil }
        } message: { target in
            Text("Changing \(target.label) starts a fresh \(currentSession.cli.displayName) process in the same project. The current conversation will be terminated.")
        }
        .alert("Couldn't restart", isPresented: Binding(
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

    private func sendMessage(_ content: String) async {
        let api = APIClient(store: pairing)
        do {
            try await api.sendMessage(sessionId: currentSession.id, content: content)
        } catch {
            // SSE error event surfaces server-side failures
        }
    }

    private func killSession() async {
        let api = APIClient(store: pairing)
        _ = try? await api.killSession(sessionId: currentSession.id)
        dismiss()
    }

    // MARK: - Restart-on-change

    private func restart(with target: SwitchTarget) async {
        let api = APIClient(store: pairing)
        switching = nil
        restarting = true
        store?.disconnect()
        store = nil

        _ = try? await api.killSession(sessionId: currentSession.id)

        let cli: CLIWire = {
            if case .provider(let c) = target { return c }
            return currentSession.cli
        }()
        let providerChanged = cli != currentSession.cli
        let model: String? = {
            if case .model(let m) = target { return m }
            // Drop incompatible model when switching providers
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
            // Refetch features for the (possibly new) provider so the
            // composer rebuilds its sections.
            await loadFeatures()
        } catch {
            switchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            // Best-effort: revert by reconnecting to the same descriptor
            // (the underlying process is dead; user can dismiss and start over)
            dismiss()
        }
        restarting = false
    }
}

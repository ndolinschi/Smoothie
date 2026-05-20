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

        // Kill the old process in the background — we don't wait.
        let oldId = currentSession.id
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
            // Atomically swap. Until this point the user keeps seeing the
            // previous session's events; the new SSE picks up immediately.
            store?.disconnect()
            currentSession = new
            let s = SessionLiveStore(session: new)
            s.connect(api: api)
            store = s
            await loadFeatures()
        } catch {
            switchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

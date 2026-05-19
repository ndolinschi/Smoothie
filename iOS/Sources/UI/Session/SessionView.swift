import SwiftUI

@MainActor
@Observable
final class SessionLiveStore {
    private(set) var events: [SmoothieEventWire] = []
    private(set) var state: SessionStateWire
    private(set) var connected: Bool = false
    private(set) var error: String?

    private var sse: SSEClient?
    let session: SessionDescriptorWire

    init(session: SessionDescriptorWire) {
        self.session = session
        self.state = session.state
    }

    func connect(api: APIClient) {
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
        switch event.type {
        case .waiting:      state = .waiting
        case .done:         state = .done
        case .error:        state = .error
        case .limitReached: state = .limitReached
        case .message, .thinking, .toolUse, .toolResult, .fileEdit:
            state = .thinking
        }
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
    @State private var confirmKill = false
    @State private var switching: SwitchTarget?
    @State private var restarting = false
    @State private var switchError: String?
    @State private var lastNotifiedState: SessionStateWire?

    enum SwitchTarget: Identifiable, Equatable {
        case model(String)
        case effort(String)
        case mode(String)

        var id: String {
            switch self {
            case .model(let s): return "model:\(s)"
            case .effort(let s): return "effort:\(s)"
            case .mode(let s): return "mode:\(s)"
            }
        }

        var label: String {
            switch self {
            case .model(let s): return "model = \(s)"
            case .effort(let s): return "reasoning effort = \(s)"
            case .mode(let s): return "mode = \(s)"
            }
        }
    }

    init(session: SessionDescriptorWire) {
        self.session = session
        _currentSession = State(initialValue: session)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if restarting {
                VStack(spacing: 12) {
                    ProgressView().tint(.white.opacity(0.6))
                    Text("Restarting session…")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let store {
                VStack(spacing: 0) {
                    AgentStream(events: store.events)
                    MessageInput(
                        session: currentSession,
                        features: features,
                        onSend: { text, attachments in
                            let composed = attachments.composedMessage(with: text)
                            await sendMessage(composed)
                        },
                        onSwitchModel: { switching = .model($0) },
                        onSwitchEffort: { switching = .effort($0) },
                        onSwitchMode: { switching = .mode($0) }
                    )
                }
            } else {
                ProgressView().tint(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 3) {
                    Text(currentSession.projectName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    if let store {
                        StatusBadge(state: store.state, connected: store.connected)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { confirmKill = true } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.7))
                }
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

        let model: String? = {
            if case .model(let m) = target { return m }
            return currentSession.model
        }()
        let effort: String? = {
            if case .effort(let e) = target { return e }
            return currentSession.reasoningEffort
        }()
        let mode: String? = {
            if case .mode(let m) = target { return m }
            return currentSession.mode
        }()

        do {
            let req = CreateSessionRequestWire(
                projectPath: currentSession.projectPath,
                cli: currentSession.cli,
                model: model,
                reasoningEffort: effort,
                mode: mode
            )
            let new = try await api.createSession(req)
            currentSession = new
            let s = SessionLiveStore(session: new)
            s.connect(api: api)
            store = s
        } catch {
            switchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            // Best-effort: revert by reconnecting to the same descriptor
            // (the underlying process is dead; user can dismiss and start over)
            dismiss()
        }
        restarting = false
    }
}

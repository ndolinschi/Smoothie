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
    @State private var store: SessionLiveStore?
    @State private var confirmKill = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let store {
                VStack(spacing: 0) {
                    AgentStream(events: store.events)
                    MessageInput(state: store.state) { content in
                        await sendMessage(content: content, store: store)
                    }
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
                    Text(session.projectName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    if let store {
                        StatusBadge(state: store.state, connected: store.connected)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    confirmKill = true
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .onAppear {
            guard store == nil else { return }
            let s = SessionLiveStore(session: session)
            s.connect(api: APIClient(store: pairing))
            store = s
        }
        .onDisappear {
            store?.disconnect()
        }
        .alert("Kill session?", isPresented: $confirmKill) {
            Button("Kill", role: .destructive) {
                Task { await killSession() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This terminates the agent process on your Mac.")
        }
    }

    private func sendMessage(content: String, store: SessionLiveStore) async {
        let api = APIClient(store: pairing)
        do {
            try await api.sendMessage(sessionId: session.id, content: content)
        } catch {
            // No-op — the SSE error event surfaces server-side failures
        }
    }

    private func killSession() async {
        let api = APIClient(store: pairing)
        _ = try? await api.killSession(sessionId: session.id)
        dismiss()
    }
}

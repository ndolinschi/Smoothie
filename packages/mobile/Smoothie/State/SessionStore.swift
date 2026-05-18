import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class SessionStore {
    let session: SessionDTO
    private let api: API
    private(set) var events: [SmoothieEvent] = []
    private(set) var state: SessionState
    private(set) var connected: Bool = false
    private(set) var lastError: String?

    private var sse: SSEClient?

    init(session: SessionDTO, api: API) {
        self.session = session
        self.api = api
        self.state = session.state
    }

    func connect() {
        guard sse == nil, let url = api.streamURL(sessionId: session.id) else { return }
        let client = SSEClient(
            onOpen: { [weak self] in
                Task { @MainActor in self?.connected = true }
            },
            onEvent: { [weak self] type, data in
                guard let evt = Self.decode(type: type, data: data) else { return }
                Task { @MainActor in self?.ingest(evt) }
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.connected = false
                    if let e = error, (e as? URLError)?.code != .cancelled {
                        self?.lastError = e.localizedDescription
                    }
                }
            }
        )
        sse = client
        client.start(url: url)
    }

    func disconnect() {
        sse?.cancel()
        sse = nil
        connected = false
    }

    func sendMessage(_ content: String) async {
        do {
            try await api.sendMessage(sessionId: session.id, content: content)
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func kill() async {
        disconnect()
        _ = try? await api.killSession(sessionId: session.id)
    }

    private func ingest(_ event: SmoothieEvent) {
        events.append(event)
        if events.count > 2000 {
            events.removeFirst(events.count - 2000)
        }
        switch event.type {
        case .waiting:  state = .waiting
        case .done:     state = .done
        case .error:    state = .error
        case .message, .thinking, .tool_use, .file_edit:
            state = .thinking
        }
        maybeNotify(after: event)
    }

    private func maybeNotify(after event: SmoothieEvent) {
        guard UIApplication.shared.applicationState != .active else { return }
        switch event.type {
        case .waiting:
            LocalNotifier.shared.notifyWaiting(projectName: session.projectName, sessionId: session.id)
        case .done:
            LocalNotifier.shared.notifyDone(projectName: session.projectName, sessionId: session.id)
        default:
            break
        }
    }

    nonisolated private static func decode(type: String, data: String) -> SmoothieEvent? {
        guard let raw = data.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SmoothieEvent.self, from: raw)
    }
}

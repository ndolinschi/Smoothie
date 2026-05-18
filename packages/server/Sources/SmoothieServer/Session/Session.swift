import Foundation

/// One running CLI agent session. Owns its adapter, an in-memory event log,
/// and the set of currently subscribed SSE consumers.
actor Session {
    let id: UUID
    let projectPath: String
    let projectName: String
    let cli: CLIType
    let createdAt: Date

    private let adapter: any AgentAdapter
    private(set) var events: [SmoothieEvent] = []
    private var subscribers: [UUID: AsyncStream<SmoothieEvent>.Continuation] = [:]

    static let eventCap = 5000

    init(projectPath: String, cli: CLIType, adapter: any AgentAdapter) {
        self.id = UUID()
        self.projectPath = projectPath
        self.projectName = (projectPath as NSString).lastPathComponent
        self.cli = cli
        self.createdAt = Date()
        self.adapter = adapter
        Task { await self.consumeEvents() }
    }

    var state: SessionState { adapter.currentState() }

    func send(_ content: String) async throws {
        try await adapter.send(content)
    }

    func kill() async {
        await adapter.terminate()
    }

    func snapshot() -> SessionDTO {
        SessionDTO(
            id: id.uuidString,
            projectPath: projectPath,
            projectName: projectName,
            cli: cli,
            state: state,
            createdAt: createdAt.timeIntervalSince1970
        )
    }

    /// Subscribe to live events. The returned stream replays buffered events
    /// first, then yields new ones until the session ends or the subscriber
    /// terminates.
    func subscribe() -> AsyncStream<SmoothieEvent> {
        let subscriberID = UUID()
        let (stream, cont) = AsyncStream<SmoothieEvent>.makeStream(bufferingPolicy: .unbounded)

        // Replay buffer
        for event in events {
            cont.yield(event)
        }
        subscribers[subscriberID] = cont

        cont.onTermination = { [weak self, subscriberID] _ in
            guard let self else { return }
            Task { await self.removeSubscriber(subscriberID) }
        }
        return stream
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    private func consumeEvents() async {
        for await event in adapter.events {
            events.append(event)
            if events.count > Self.eventCap {
                events.removeFirst(events.count - Self.eventCap)
            }
            for (_, cont) in subscribers {
                cont.yield(event)
            }
        }
        for (_, cont) in subscribers {
            cont.finish()
        }
        subscribers.removeAll()
    }
}

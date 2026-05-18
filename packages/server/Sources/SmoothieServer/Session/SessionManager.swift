import Foundation

actor SessionManager {
    private var sessions: [UUID: Session] = [:]

    func create(projectPath: String, cli: CLIType, systemPromptText: String?) async throws -> Session {
        let config = AdapterStartConfig(projectPath: projectPath, systemPromptText: systemPromptText)
        let adapter = try await AdapterRegistry.make(cli: cli, config: config)
        let session = Session(projectPath: projectPath, cli: cli, adapter: adapter)
        sessions[session.id] = session
        return session
    }

    func get(_ id: UUID) -> Session? {
        sessions[id]
    }

    func list() async -> [SessionDTO] {
        var out: [SessionDTO] = []
        for session in sessions.values {
            out.append(await session.snapshot())
        }
        return out.sorted { $0.createdAt > $1.createdAt }
    }

    func terminate(_ id: UUID) async -> Bool {
        guard let session = sessions[id] else { return false }
        await session.kill()
        sessions.removeValue(forKey: id)
        return true
    }

    func terminateAll() async {
        for (_, session) in sessions {
            await session.kill()
        }
        sessions.removeAll()
    }
}

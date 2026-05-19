import Foundation
import Observation
import Shared

/// id → ProcessHost. Owns the subprocess lifecycle in tandem with Kotlin
/// SessionManager. When a Session is created, the registry spawns a host;
/// when removed, it terminates it.
@MainActor
@Observable
final class ProcessRegistry {
    private var hosts: [String: ProcessHost] = [:]
    private(set) var activeCount: Int = 0

    let manager: SessionManager
    let registry: AdapterRegistry
    let prefs: Preferences

    init(manager: SessionManager, registry: AdapterRegistry, prefs: Preferences) {
        self.manager = manager
        self.registry = registry
        self.prefs = prefs
    }

    enum SpawnError: LocalizedError {
        case adapterMissing(String)
        case pathForbidden(String)
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .adapterMissing(let s): return "Adapter not available: \(s)"
            case .pathForbidden(let s):  return "Project path not allowed: \(s)"
            case .launchFailed(let s):   return "Couldn't launch: \(s)"
            }
        }
    }

    @discardableResult
    func spawn(request: CreateSessionRequest) async throws -> SessionDescriptor {
        guard prefs.isPathAllowed(request.projectPath) else {
            throw SpawnError.pathForbidden(request.projectPath)
        }

        // Snap the request through Preferences so it gets the default model if
        // the request omitted one and the user has set a preference.
        let effective = prefs.applyDefaults(to: request)

        // Resolve the executable path.
        guard let info = registry.all().first(where: { $0.cli == effective.cli }), info.installed,
              let exec = which(effective.cli.executableName) else {
            throw SpawnError.adapterMissing(effective.cli.displayName)
        }

        // Kotlin: create the session. Kotlin suspend funs export as
        // `async throws` to Swift even when they never actually throw, so we
        // tolerate failure here as a launch failure.
        let session: Session
        do {
            session = try await manager.create(request: effective)
        } catch {
            throw SpawnError.launchFailed(error.localizedDescription)
        }

        // Resolve adapter parser for launch args / env.
        guard let parser = registry.parserFor(cli: effective.cli) else {
            throw SpawnError.adapterMissing(effective.cli.displayName)
        }

        let systemPrompt = SafetyHost.shared.assembledSystemPrompt(for: effective.cli)
        let args = parser.launchArguments(request: effective, systemPromptText: systemPrompt)
        let envMap = Self.mapFromKotlin(parser.launchEnvironment())

        do {
            let host = try ProcessHost(
                session: session,
                executable: exec,
                arguments: args,
                cwd: effective.projectPath,
                environment: envMap
            )
            try host.start()
            hosts[session.id] = host
            activeCount = hosts.count
        } catch {
            try? await session.markError(message: "spawn failed: \(error.localizedDescription)")
            _ = try? await manager.remove(id: session.id)
            throw SpawnError.launchFailed(error.localizedDescription)
        }

        return try await session.descriptor()
    }

    func host(forSessionId id: String) -> ProcessHost? {
        hosts[id]
    }

    @discardableResult
    func terminate(id: String) async -> Bool {
        guard let host = hosts.removeValue(forKey: id) else { return false }
        host.terminate()
        _ = try? await manager.remove(id: id)
        activeCount = hosts.count
        return true
    }

    func terminateAll() async {
        for (id, host) in hosts {
            host.terminate()
            _ = try? await manager.remove(id: id)
        }
        hosts.removeAll()
        activeCount = 0
    }

    // MARK: - Helpers

    private func which(_ binary: String) -> String? {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/\(binary)",
            "/opt/homebrew/bin/\(binary)",
            "/usr/local/bin/\(binary)",
            "/usr/bin/\(binary)",
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) { return p }
        return nil
    }

    private static func mapFromKotlin(_ kotlin: [String: String]) -> [String: String] {
        // Identity for now — kotlin maps surface as Swift dictionaries.
        return kotlin
    }
}

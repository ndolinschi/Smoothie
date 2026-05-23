import Foundation
import Observation
import Shared

/// id → ProcessHost. Owns the subprocess lifecycle in tandem with Kotlin
/// SessionManager. When a Session is created, the registry spawns a host;
/// when removed, it terminates it.
@MainActor
@Observable
final class ProcessRegistry {
    private var hosts: [String: any SessionHost] = [:]
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

        // Track the partially-constructed host outside the `do` so the
        // catch block can tear it down — previously a failed `start()`
        // (e.g. an OpenCodeServeHost that spawned `opencode serve` but
        // couldn't open the SSE) would leave the child process orphaned
        // and re-parented to launchd. We hit this with ~13 zombie
        // `opencode serve` workers across debug sessions.
        var partialHost: (any SessionHost)?

        do {
            let host: any SessionHost
            if effective.cli == CLIType.gemini, let geminiParser = parser as? GeminiAdapter {
                host = GeminiOneshotHost(
                    session: session,
                    parser: geminiParser,
                    executable: exec,
                    cwd: effective.projectPath,
                    baseArgs: args,
                    env: envMap
                )
            } else if effective.cli == CLIType.openCode {
                host = OpenCodeServeHost(
                    session: session,
                    executable: exec,
                    cwd: effective.projectPath
                )
            } else if effective.cli == CLIType.antigravity {
                // If the request carries a providerSessionId (Terminal
                // session resume), seed the host's continue-mode flag so
                // the first turn already adds `-c`.
                let resume = (effective.providerSessionId?.isEmpty == false)
                host = AntigravityOneshotHost(
                    session: session,
                    executable: exec,
                    cwd: effective.projectPath,
                    baseArgs: args,
                    env: envMap,
                    resumeExisting: resume
                )
            } else {
                host = try ProcessHost(
                    session: session,
                    executable: exec,
                    arguments: args,
                    cwd: effective.projectPath,
                    environment: envMap
                )
            }
            partialHost = host
            try host.start()
            hosts[session.id] = host
            activeCount = hosts.count

            // Inject a single WAITING event to flip the session state
            // out of .starting (otherwise iOS sits on "Agent is warming
            // up…" forever — every CLI we wrap is ready for stdin
            // immediately after spawn). Prior versions also injected a
            // THINKING event with text like "Spawning Claude Code in
            // Smoothie…" — that turned out to look broken (typing pulse
            // animating with no actual agent activity) and added noise
            // to the conversation history. The empty stream + .waiting
            // state now triggers iOS's `EmptyStreamPlaceholder` which
            // renders the cleaner "Ready when you are" card.
            let readyEvent = SmoothieEvent(
                type: .waiting,
                content: "",
                metadata: nil,
                timestamp: Int64(Date().timeIntervalSince1970 * 1000)
            )
            try? await session.injectEvent(event: readyEvent)
        } catch {
            partialHost?.terminate()
            try? await session.markError(message: "spawn failed: \(error.localizedDescription)")
            _ = try? await manager.remove(id: session.id)
            throw SpawnError.launchFailed(error.localizedDescription)
        }

        return try await session.descriptor()
    }

    func host(forSessionId id: String) -> (any SessionHost)? {
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

    /// Synchronous SIGTERM to every spawned child. Used from
    /// `applicationWillTerminate` where AppKit doesn't wait for our async
    /// Task to finish — async cleanup would race with process exit and leak
    /// children to launchd (we hit this with stale `opencode serve` workers
    /// piling up). The Kotlin SessionManager bookkeeping isn't touched here
    /// because the daemon is shutting down anyway; the next start probes
    /// fresh state.
    func terminateAllSync() {
        for host in hosts.values {
            host.terminate()
        }
    }

    // MARK: - Helpers

    private func which(_ binary: String) -> String? {
        // Search the user's PATH first so installs under non-standard
        // prefixes (~/.cargo/bin, ~/.bun/bin, ~/.pyenv/shims, etc.) are
        // detected without a hardcoded candidate list. Then fall back to
        // the curated list for cases where the daemon was launched
        // without a PATH inherited (e.g. via launchd plist).
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":", omittingEmptySubsequences: true) {
                let candidate = "\(dir)/\(binary)"
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        let curated = [
            "\(NSHomeDirectory())/.local/bin/\(binary)",
            "\(NSHomeDirectory())/.cargo/bin/\(binary)",
            "\(NSHomeDirectory())/.bun/bin/\(binary)",
            "\(NSHomeDirectory())/.cursor/bin/\(binary)",
            "/opt/homebrew/bin/\(binary)",
            "/usr/local/bin/\(binary)",
            "/usr/bin/\(binary)",
        ]
        for p in curated where FileManager.default.isExecutableFile(atPath: p) { return p }
        return nil
    }

    private static func mapFromKotlin(_ kotlin: [String: String]) -> [String: String] {
        // Identity for now — kotlin maps surface as Swift dictionaries.
        return kotlin
    }
}

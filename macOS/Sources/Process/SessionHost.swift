import Foundation
import Shared

/// Common surface that any provider's process / transport host needs to
/// expose so ProcessRegistry can hold it in one dictionary. ProcessHost
/// drives Claude over piped stdio; GeminiOneshotHost spawns a fresh
/// `gemini -p` process per turn; OpenCodeServeHost talks HTTP to a long-
/// running `opencode serve` child.
@MainActor
protocol SessionHost: AnyObject {
    var session: Session { get }
    var isRunning: Bool { get }
    func start() throws
    func write(_ content: String) async throws
    /// Cancel the in-flight turn without killing the session entirely. Each
    /// host best-effort: ProcessHost (Claude) sends SIGINT so the agent can
    /// interrupt cleanly; GeminiOneshotHost terminates the current one-shot
    /// spawn (next write respawns); OpenCodeServeHost POSTs the opencode
    /// `/abort` endpoint and keeps the long-running server up.
    func abort() async
    func terminate()
}

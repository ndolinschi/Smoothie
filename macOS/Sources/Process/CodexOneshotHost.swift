import Foundation
import Shared

/// OpenAI Codex CLI driver. Same one-shot-per-turn shape as
/// `GeminiOneshotHost` — Codex's non-interactive mode is
/// `codex exec --json "<prompt>"`, which emits a JSONL stream on stdout
/// and exits. We spawn fresh per `write(_:)` and pipe stdout through
/// `session.ingestText` so the `CodexAdapter` line-parses it into
/// SmoothieEvents in real time.
///
/// Multi-turn memory: Codex's `exec` mode is stateless on its own. The
/// CLI threads conversations server-side keyed by `--thread <id>`. We
/// capture the `thread_id` from the first `thread.started` event the
/// parser sees and inject it on subsequent turns. Until then, each
/// turn is independent.
@MainActor
final class CodexOneshotHost: SessionHost {
    let session: Session
    private let executable: String
    private let cwd: String
    private let baseArgs: [String]
    private let env: [String: String]

    private var current: Process?
    private var currentStdout: Pipe?
    /// Persisted across turns so the second `codex exec` carries
    /// `--thread <id>` and the agent has context.
    private var threadId: String?
    private var stdoutLines = StdoutLineBuffer()
    private var stderr = BoundedStderr()

    /// `codex exec` has no system-prompt flag, so the safety/system prompt
    /// is prepended to the first turn's prompt text; the server-side thread
    /// carries it across `--thread` turns.
    private var promptInjector: SystemPromptInjector

    var isRunning: Bool { current?.isRunning ?? false }

    init(
        session: Session,
        executable: String,
        cwd: String,
        baseArgs: [String],
        env: [String: String],
        systemPrompt: String? = nil
    ) {
        self.session = session
        self.executable = executable
        self.cwd = cwd
        self.baseArgs = baseArgs
        self.env = env
        self.promptInjector = SystemPromptInjector(prompt: systemPrompt)
    }

    func start() throws {
        // No-op — Codex one-shot hosts spawn on the first write.
    }

    func write(_ content: String) async throws {
        if let current, current.isRunning {
            // Avoid stacking spawns. The previous turn must finish first.
            return
        }

        try? await session.noteUserMessageSent()

        var args = baseArgs
        if let threadId, !threadId.isEmpty {
            args.append(contentsOf: ["--thread", threadId])
        }
        args.append(promptInjector.decorate(content))

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)

        var procEnv = ProcessInfo.processInfo.environment
        for (k, v) in env { procEnv[k] = v }
        proc.environment = procEnv

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        stdoutLines = StdoutLineBuffer()
        stderr = BoundedStderr()

        let weakSelfRef = WeakHostRef(self)
        stdoutPipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            if data.isEmpty { return }
            Task { @MainActor in await weakSelfRef.value?.handleStdout(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            if data.isEmpty { return }
            Task { @MainActor in weakSelfRef.value?.handleStderr(data) }
        }
        proc.terminationHandler = { p in
            let code = p.terminationStatus
            Task { @MainActor in await weakSelfRef.value?.handleTermination(code: code) }
        }

        self.current = proc
        self.currentStdout = stdoutPipe
        try proc.run()
    }

    func terminate() {
        guard let proc = current else { return }
        SubprocessLifecycle.terminateWithGrace(proc)
    }

    /// Cancel the in-flight `codex exec` spawn. The Smoothie session
    /// is kept; the next `write(_:)` respawns with `--thread <id>` so
    /// the agent picks up where it left off.
    func abort() async {
        guard let proc = current, proc.isRunning else { return }
        proc.terminate()
    }

    // MARK: - Internals

    private func handleStdout(_ data: Data) async {
        let lines = stdoutLines.feed(data)
        guard !lines.isEmpty else { return }
        let text = lines.map { $0 + "\n" }.joined()
        // Best-effort thread id capture before passing to the K/N parser —
        // looks for `"thread_id":"..."` in the raw JSONL so turns stitch
        // together across one-shot spawns.
        if threadId == nil, let id = Self.extractThreadId(from: text) {
            threadId = id
            session.setProviderSessionId(id: id)
        }
        _ = try? await session.ingestText(text: text)
    }

    /// Pull the `thread_id` out of a `thread.started` event without
    /// double-parsing the whole JSONL stream. The format is stable
    /// enough that a regex match is fine here — the K/N parser does
    /// the structural work for the rest of the events.
    private static func extractThreadId(from text: String) -> String? {
        let pattern = #""thread_id"\s*:\s*"([^"]+)""#
        guard let range = text.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        let match = String(text[range])
        // Pull the captured group out manually since Swift's range-based
        // regex doesn't surface groups directly.
        guard let colon = match.range(of: ":"),
              let firstQuote = match.range(of: "\"", options: [], range: colon.upperBound..<match.endIndex)
        else { return nil }
        let after = match.index(after: firstQuote.lowerBound)
        guard let secondQuote = match.range(of: "\"", options: [], range: after..<match.endIndex)
        else { return nil }
        return String(match[after..<secondQuote.lowerBound])
    }

    private func handleStderr(_ data: Data) {
        stderr.append(data)
    }

    private func handleTermination(code: Int32) async {
        if let stdout = currentStdout {
            let leftover = stdout.fileHandleForReading.availableData
            if !leftover.isEmpty { await handleStdout(leftover) }
            if let tail = stdoutLines.drain(), !tail.isEmpty {
                _ = try? await session.ingestText(text: tail + "\n")
            }
            stdout.fileHandleForReading.readabilityHandler = nil
        }

        if code != 0 {
            let detail = stderr.text.isEmpty ? "" : "\n\(stderr.text)"
            try? await session.markError(message: "codex exited with code \(code)\(detail)")
        }
        // On clean exit the parser has already emitted a turn.completed →
        // WAITING event, so no extra state flip needed here.

        self.current = nil
        self.currentStdout = nil
    }
}

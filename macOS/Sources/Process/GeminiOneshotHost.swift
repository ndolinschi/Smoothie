import Foundation
import Shared

/// Gemini's CLI doesn't keep a long-running session — every turn is a fresh
/// `gemini -p "<text>"` invocation. We bridge that into the same Smoothie
/// session UX by spawning a new process per `write(_:)` and using
/// `--resume <session_id>` from the second turn onward so the agent keeps
/// memory across turns.
///
/// The Kotlin GeminiAdapter captures the `session_id` it sees in the first
/// `init` event; we read it after the process exits and thread it back as
/// `--resume` on the next spawn.
@MainActor
final class GeminiOneshotHost: SessionHost {
    let session: Session
    private let parser: GeminiAdapter
    private let executable: String
    private let cwd: String
    private let baseArgs: [String]
    private let env: [String: String]

    private var current: Process?
    private var currentStdout: Pipe?
    private var resumeSessionId: String?
    private var stdoutLines = StdoutLineBuffer()
    private var stderr = BoundedStderr()

    /// Gemini's CLI has no `--append-system-prompt`, so the safety/system
    /// prompt is prepended to the first turn's `-p` text; conversation
    /// memory carries it across `--resume` turns.
    private var promptInjector: SystemPromptInjector

    var isRunning: Bool { current?.isRunning ?? false }

    init(
        session: Session,
        parser: GeminiAdapter,
        executable: String,
        cwd: String,
        baseArgs: [String],
        env: [String: String],
        systemPrompt: String? = nil
    ) {
        self.session = session
        self.parser = parser
        self.executable = executable
        self.cwd = cwd
        self.baseArgs = baseArgs
        self.env = env
        // A resumed conversation (Terminal take-back) already received the
        // prompt on its original first turn — don't re-send.
        self.promptInjector = SystemPromptInjector(
            prompt: systemPrompt,
            alreadySent: baseArgs.contains("--resume")
        )
    }

    func start() throws {
        // No-op — Gemini one-shot hosts spawn on the first write.
    }

    func write(_ content: String) async throws {
        if let current, current.isRunning {
            // Avoid stacking spawns. The previous turn must finish first.
            return
        }

        try? await session.noteUserMessageSent()

        var args = baseArgs
        if let resumeSessionId {
            args.append(contentsOf: ["--resume", resumeSessionId])
        }
        args.append(contentsOf: ["-p", promptInjector.decorate(content)])

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

    /// Abort the in-flight one-shot spawn. The Smoothie session is kept;
    /// the next `write(_:)` will respawn `gemini -p` with `--resume` so the
    /// agent picks up where it left off.
    func abort() async {
        guard let proc = current, proc.isRunning else { return }
        proc.terminate()
    }

    // MARK: - Internals

    private func handleStdout(_ data: Data) async {
        let lines = stdoutLines.feed(data)
        guard !lines.isEmpty else { return }
        _ = try? await session.ingestText(text: lines.map { $0 + "\n" }.joined())
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

        // Capture resume id so the next turn keeps Gemini's conversation memory.
        if let captured = parser.lastSessionId, !captured.isEmpty {
            self.resumeSessionId = captured
        }

        if code != 0 {
            let detail = stderr.text.isEmpty ? "" : "\n\(stderr.text)"
            try? await session.markError(message: "gemini exited with code \(code)\(detail)")
        }
        // On a clean exit the K/N parser has already emitted a WAITING event
        // (mapped from gemini's `result.status == success`), so no explicit
        // state flip needed here.

        self.current = nil
        self.currentStdout = nil
    }
}

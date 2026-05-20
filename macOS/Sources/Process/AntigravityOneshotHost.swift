import Foundation
import Shared

/// Antigravity's `agy` CLI is one-shot per turn — same pattern as Gemini,
/// but the stdout payload is plain markdown rather than stream-json. So we
/// don't pipe the bytes through a Kotlin line parser; we buffer the whole
/// process output, then inject a single MESSAGE event (plus WAITING) into
/// the Smoothie Session when the process exits.
///
/// Multi-turn memory is preserved by setting the same project cwd on every
/// spawn and passing `-c` (continue most recent conversation) from the
/// second turn onward. Antigravity keeps the conversation thread keyed by
/// working directory under `~/Library/Application Support/Antigravity/`,
/// so as long as we don't mix multiple Smoothie sessions on the same
/// folder, `-c` Just Works.
///
/// Auth: `agy` requires the user to have signed in once via the desktop
/// Antigravity.app (OAuth via browser). We do NOT try to surface a sign-in
/// flow from the daemon — if `agy -p` returns a "not signed in" error we
/// route it to `markError(_)` so the iOS UI shows the message and the user
/// can fix it by running `agy` once in Terminal.
@MainActor
final class AntigravityOneshotHost: SessionHost {
    let session: Session
    private let executable: String
    private let cwd: String
    private let baseArgs: [String]
    private let env: [String: String]

    private var current: Process?
    private var currentStdout: Pipe?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private let stderrCap = 8 * 1024

    /// Antigravity tracks the conversation per-cwd internally; we just need
    /// to flip to `-c` after the first successful spawn so the agent gets
    /// memory across turns.
    private var hasCompletedFirstTurn = false

    var isRunning: Bool { current?.isRunning ?? false }

    init(
        session: Session,
        executable: String,
        cwd: String,
        baseArgs: [String],
        env: [String: String]
    ) {
        self.session = session
        self.executable = executable
        self.cwd = cwd
        self.baseArgs = baseArgs
        self.env = env
    }

    func start() throws {
        // No-op — Antigravity one-shot hosts spawn on the first write.
    }

    func write(_ content: String) async throws {
        if let current, current.isRunning {
            // Avoid stacking spawns. The previous turn must finish first.
            return
        }

        try? await session.noteUserMessageSent()

        var args = baseArgs
        if hasCompletedFirstTurn {
            args.append("-c")
        }
        args.append(contentsOf: ["-p", content])

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

        stdoutBuffer.removeAll(keepingCapacity: true)
        stderrBuffer.removeAll(keepingCapacity: true)

        let weakSelfRef = WeakAntigravityBox(self)
        stdoutPipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            if data.isEmpty { return }
            Task { @MainActor in weakSelfRef.value?.appendStdout(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            if data.isEmpty { return }
            Task { @MainActor in weakSelfRef.value?.appendStderr(data) }
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
        guard let proc = current, proc.isRunning else { return }
        proc.terminate()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
            }
        }
    }

    /// Cancel the in-flight one-shot spawn. The next `write(_:)` respawns
    /// `agy` with `-c` so the conversation thread is preserved.
    func abort() async {
        guard let proc = current, proc.isRunning else { return }
        proc.terminate()
    }

    // MARK: - Internals

    private func appendStdout(_ data: Data) {
        stdoutBuffer.append(data)
    }

    private func appendStderr(_ data: Data) {
        stderrBuffer.append(data)
        if stderrBuffer.count > stderrCap {
            stderrBuffer.removeFirst(stderrBuffer.count - stderrCap)
        }
    }

    private func handleTermination(code: Int32) async {
        if let stdout = currentStdout {
            let leftover = stdout.fileHandleForReading.availableData
            if !leftover.isEmpty { stdoutBuffer.append(leftover) }
            stdout.fileHandleForReading.readabilityHandler = nil
        }

        let stdoutText = String(data: stdoutBuffer, encoding: .utf8) ?? ""
        let stderrText = String(data: stderrBuffer, encoding: .utf8) ?? ""

        if code == 0 {
            let trimmed = stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            if !trimmed.isEmpty {
                let message = SmoothieEvent(
                    type: .message,
                    content: trimmed,
                    metadata: nil,
                    timestamp: now
                )
                try? await session.injectEvent(event: message)
            }
            // Flip to `-c` for subsequent turns so Antigravity threads the
            // conversation. We only set the flag after a successful turn so a
            // first-turn auth failure doesn't strand the host in "continue
            // mode" with no thread to resume.
            hasCompletedFirstTurn = true
            let waiting = SmoothieEvent(
                type: .waiting,
                content: "",
                metadata: nil,
                timestamp: now
            )
            try? await session.injectEvent(event: waiting)
        } else {
            // Stderr usually has the actionable message ("not signed in",
            // "quota exhausted", etc.); fall back to stdout if stderr is
            // empty (some agy errors print to stdout).
            let detail = stderrText.isEmpty ? stdoutText : stderrText
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = trimmed.isEmpty
                ? "agy exited with code \(code)"
                : "agy exited with code \(code)\n\(trimmed)"
            try? await session.markError(message: message)
        }

        self.current = nil
        self.currentStdout = nil
    }
}

@MainActor
private final class WeakAntigravityBox {
    weak var value: AntigravityOneshotHost?
    init(_ value: AntigravityOneshotHost) { self.value = value }
}

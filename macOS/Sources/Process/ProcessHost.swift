import Foundation
import Shared

/// Wraps one CLI subprocess. Owns Foundation.Process + three Pipes,
/// pumps stdout bytes into the matched Kotlin Session.ingestText(),
/// and surfaces termination back to Kotlin so the SessionState
/// transitions to .done / .error.
@MainActor
final class ProcessHost: SessionHost {
    let session: Session
    private let process: Process
    private let stdinPipe: Pipe
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe

    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private let stderrCap = 8 * 1024

    init(
        session: Session,
        executable: String,
        arguments: [String],
        cwd: String,
        environment: [String: String]
    ) throws {
        self.session = session

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)

        var env = ProcessInfo.processInfo.environment
        for (k, v) in environment { env[k] = v }
        proc.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        self.process = proc
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
    }

    var isRunning: Bool { process.isRunning }
    var pid: Int32 { process.processIdentifier }

    func start() throws {
        let weakSelfRef = WeakBox(self)
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
        process.terminationHandler = { proc in
            let code = proc.terminationStatus
            Task { @MainActor in await weakSelfRef.value?.handleTermination(code: code) }
        }
        try process.run()
    }

    func resume() throws {
        // Convenience for future restart flows
        try process.run()
    }

    func write(_ content: String) async throws {
        guard process.isRunning else { return }
        try? await session.noteUserMessageSent()
        let payload = session.encodeUserMessage(content: content)
        let data = Data(payload.utf8)
        try stdinPipe.fileHandleForWriting.write(contentsOf: data)
    }

    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
        // SIGKILL grace
        let p = process
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if p.isRunning {
                kill(p.processIdentifier, SIGKILL)
            }
        }
    }

    /// Try to interrupt the current turn without killing the session.
    /// Claude Code handles SIGINT by stopping the active generation but
    /// keeping the stream-json loop alive, so subsequent writes still
    /// reach the same process.
    func abort() async {
        guard process.isRunning else { return }
        kill(process.processIdentifier, SIGINT)
    }

    // MARK: - Internals

    private func handleStdout(_ data: Data) async {
        stdoutBuffer.append(data)
        // Try to decode the whole buffer; if a multi-byte char straddles a
        // chunk boundary, decoding fails and we leave it for the next chunk.
        if let text = String(data: stdoutBuffer, encoding: .utf8) {
            stdoutBuffer.removeAll(keepingCapacity: true)
            _ = try? await session.ingestText(text: text)
        }
    }

    private func handleStderr(_ data: Data) {
        stderrBuffer.append(data)
        if stderrBuffer.count > stderrCap {
            let overflow = stderrBuffer.count - stderrCap
            stderrBuffer.removeFirst(overflow)
        }
    }

    private func handleTermination(code: Int32) async {
        // Flush any buffered stdout one last time
        let leftover = stdoutPipe.fileHandleForReading.availableData
        if !leftover.isEmpty {
            await handleStdout(leftover)
        }
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        if code == 0 {
            try? await session.markDone()
        } else {
            let stderrText = String(data: stderrBuffer, encoding: .utf8) ?? ""
            let detail = stderrText.isEmpty ? "" : "\n\(stderrText)"
            try? await session.markError(message: "process exited with code \(code)\(detail)")
        }
    }
}

/// Small holder so `readabilityHandler` closures (non-isolated) can hop back
/// to MainActor without retaining ProcessHost strongly.
@MainActor
private final class WeakBox {
    weak var value: ProcessHost?
    init(_ value: ProcessHost) { self.value = value }
}

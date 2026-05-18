import Foundation

/// Bidirectional pipe-based child process. Stdin/stdout/stderr are attached to
/// `Foundation.Pipe`s so we can stream JSONL on stdin and read JSONL responses
/// on stdout without the echo/canonical-mode artefacts a PTY introduces.
///
/// `claude -p --output-format stream-json` is designed for non-interactive use,
/// so a plain pipe is the correct transport for it.
final class PipedProcess: @unchecked Sendable {
    private let process: Process
    private let stdinPipe: Pipe
    private let stdoutPipe: Pipe
    private let stderrPipe: Pipe

    private let exitContinuation: AsyncStream<Int32>.Continuation
    let exitStream: AsyncStream<Int32>

    private let writeLock = NSLock()
    private var terminated = false
    private var stdinClosed = false

    var pid: Int32 { process.processIdentifier }

    init(executable: String, args: [String], cwd: String, env: [String: String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        process.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe

        var cont: AsyncStream<Int32>.Continuation!
        self.exitStream = AsyncStream<Int32> { c in cont = c }
        self.exitContinuation = cont

        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.exitContinuation.yield(proc.terminationStatus)
            self.exitContinuation.finish()
        }

        try process.run()
    }

    /// Stream stdout as chunks.
    func read() -> AsyncStream<Data> {
        let handle = stdoutPipe.fileHandleForReading
        return AsyncStream<Data> { continuation in
            handle.readabilityHandler = { fh in
                let data = fh.availableData
                if data.isEmpty {
                    fh.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
            continuation.onTermination = { _ in
                handle.readabilityHandler = nil
            }
        }
    }

    /// Stream stderr as chunks.
    func readStderr() -> AsyncStream<Data> {
        let handle = stderrPipe.fileHandleForReading
        return AsyncStream<Data> { continuation in
            handle.readabilityHandler = { fh in
                let data = fh.availableData
                if data.isEmpty {
                    fh.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
            continuation.onTermination = { _ in
                handle.readabilityHandler = nil
            }
        }
    }

    /// Write to stdin. Safe across threads.
    func write(_ data: Data) throws {
        writeLock.lock(); defer { writeLock.unlock() }
        guard !terminated, !stdinClosed else {
            throw PipedProcessError.closed
        }
        do {
            try stdinPipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            throw PipedProcessError.writeFailed(error.localizedDescription)
        }
    }

    /// Close stdin (useful for one-shot programs that exit on EOF).
    func closeStdin() {
        writeLock.lock(); defer { writeLock.unlock() }
        guard !stdinClosed else { return }
        stdinClosed = true
        try? stdinPipe.fileHandleForWriting.close()
    }

    func terminate() {
        writeLock.lock()
        let wasTerminated = terminated
        terminated = true
        let alreadyClosed = stdinClosed
        stdinClosed = true
        writeLock.unlock()

        guard !wasTerminated else { return }

        if !alreadyClosed {
            try? stdinPipe.fileHandleForWriting.close()
        }
        if process.isRunning {
            process.terminate()
        }
        // SIGKILL after grace period
        let p = process
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
    }
}

enum PipedProcessError: Error, CustomStringConvertible {
    case closed
    case writeFailed(String)

    var description: String {
        switch self {
        case .closed: return "process stdin closed"
        case .writeFailed(let m): return "write failed: \(m)"
        }
    }
}

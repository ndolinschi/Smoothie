import Foundation

/// Shared building blocks for the subprocess-backed `SessionHost`s. Before
/// this, every host (ProcessHost, the four one-shot hosts, the ACP host)
/// hand-rolled the same four things — a weak self box for pipe handlers, a
/// terminate-with-SIGKILL-grace dance, a capped stderr buffer, and a
/// once-only system-prompt prepend — and two of them decoded stdout in a
/// way that corrupted UTF-8 split across pipe reads. Centralising them
/// fixes that bug in one place and removes the copy-paste.

/// Holds a host weakly so a `Pipe.readabilityHandler` closure (which runs
/// off the MainActor) can hop back without keeping the host alive past
/// process exit. Replaces the six near-identical `WeakXxxBox` types.
@MainActor
final class WeakHostRef<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

/// Accumulates raw stdout `Data` and yields only complete UTF-8 lines.
/// Mirrors the Kotlin `LineByteBuffer`: a multi-byte codepoint split
/// across two `availableData` reads must not be decoded until both halves
/// arrive, or it corrupts. Hosts that line-parse (Claude, Gemini, Codex,
/// Cursor) feed bytes here and decode per line; Antigravity buffers the
/// whole output and decodes once at exit, so it doesn't need this.
struct StdoutLineBuffer {
    private var bytes = Data()

    /// Append `data` and return every newly-completed line (no trailing
    /// `\n`), each decoded as UTF-8. The trailing partial line is retained.
    mutating func feed(_ data: Data) -> [String] {
        bytes.append(data)
        var lines: [String] = []
        var searchStart = bytes.startIndex
        while let nl = bytes[searchStart...].firstIndex(of: 0x0A) {
            let lineData = bytes[searchStart..<nl]
            lines.append(String(decoding: lineData, as: UTF8.self))
            searchStart = bytes.index(after: nl)
        }
        if searchStart > bytes.startIndex {
            bytes.removeSubrange(bytes.startIndex..<searchStart)
        }
        return lines
    }

    /// Decode and clear whatever bytes remain (used at process exit to
    /// flush a final line that arrived without a trailing newline).
    mutating func drain() -> String? {
        guard !bytes.isEmpty else { return nil }
        let s = String(decoding: bytes, as: UTF8.self)
        bytes.removeAll(keepingCapacity: false)
        return s
    }
}

/// A fixed-capacity tail buffer for a child's stderr. Keeps the most recent
/// `cap` bytes so an error message survives without unbounded growth.
struct BoundedStderr {
    private(set) var data = Data()
    let cap: Int

    init(cap: Int = 8 * 1024) { self.cap = cap }

    mutating func append(_ chunk: Data) {
        data.append(chunk)
        if data.count > cap {
            data.removeFirst(data.count - cap)
        }
    }

    var text: String { String(decoding: data, as: UTF8.self) }
}

/// One-shot prepend of the assembled safety/system prompt to the first
/// outgoing turn. CLIs without an `--append-system-prompt` flag rely on
/// this; resumed conversations already carry it, so callers seed `sent`.
struct SystemPromptInjector {
    private let prompt: String?
    private(set) var sent: Bool

    init(prompt: String?, alreadySent: Bool = false) {
        self.prompt = prompt
        self.sent = alreadySent
    }

    /// Returns the content to actually send: on the first call it prepends
    /// the prompt (if any) and flips `sent`; afterwards it's a passthrough.
    mutating func decorate(_ content: String) -> String {
        guard !sent else { return content }
        sent = true
        guard let prompt, !prompt.isEmpty else { return content }
        return prompt + "\n\n---\n\n" + content
    }
}

enum SubprocessLifecycle {
    /// Terminate a process with a SIGTERM, then SIGKILL after a grace
    /// period if it's still alive. Replaces the identical block copied
    /// into every host's `terminate()`.
    @MainActor
    static func terminateWithGrace(_ process: Process, grace: Duration = .seconds(2)) {
        guard process.isRunning else { return }
        process.terminate()
        Task { @MainActor in
            try? await Task.sleep(for: grace)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }
}

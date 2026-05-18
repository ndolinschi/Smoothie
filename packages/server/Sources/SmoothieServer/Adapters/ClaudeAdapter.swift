import Foundation

/// Adapter for Anthropic's `claude` CLI. Drives Claude in programmatic stream-json
/// mode through a PTY so it always sees a TTY. Input is JSONL on stdin; output is
/// JSONL on stdout (possibly interleaved with ANSI from the terminal layer, which
/// we strip before parsing).
final class ClaudeAdapter: AgentAdapter, @unchecked Sendable {
    let cli: CLIType = .claude
    let events: AsyncStream<SmoothieEvent>

    private let pty: PTYProcess
    private let eventContinuation: AsyncStream<SmoothieEvent>.Continuation

    private let stateLock = NSLock()
    private var _state: SessionState = .starting
    private var _terminated = false

    private init(pty: PTYProcess) {
        self.pty = pty
        let (s, c) = AsyncStream<SmoothieEvent>.makeStream(bufferingPolicy: .unbounded)
        self.events = s
        self.eventContinuation = c
    }

    static func make(config: AdapterStartConfig) async throws -> any AgentAdapter {
        let executable = try findExecutable("claude")
        var args: [String] = [
            "-p",
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--add-dir", config.projectPath
        ]
        if let promptText = config.systemPromptText, !promptText.isEmpty {
            args.append(contentsOf: ["--append-system-prompt", promptText])
        }

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLUMNS"] = "200"
        env["LINES"] = "40"

        let pty = try PTYProcess(
            executable: executable,
            args: args,
            cwd: config.projectPath,
            env: env
        )
        let adapter = ClaudeAdapter(pty: pty)
        adapter.startReader()
        return adapter
    }

    func currentState() -> SessionState {
        stateLock.lock(); defer { stateLock.unlock() }
        return _state
    }

    func send(_ content: String) async throws {
        guard !isTerminated() else { throw AdapterError.io("adapter terminated") }
        let payload: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": [
                    ["type": "text", "text": content]
                ]
            ]
        ]
        var data = try JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes])
        data.append(0x0A) // \n
        try pty.write(data)
        setState(.thinking)
    }

    func terminate() async {
        let already = beginTerminate()
        guard !already else { return }
        pty.terminate()
        setState(.done)
        eventContinuation.finish()
    }

    private func beginTerminate() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        if _terminated { return true }
        _terminated = true
        return false
    }

    // MARK: - Reader

    private func startReader() {
        let stream = pty.read()
        let cont = self.eventContinuation
        Task.detached { [weak self] in
            var buffer = ""
            for await chunk in stream {
                guard let self else { break }
                let text = AdapterUtils.stripANSI(String(decoding: chunk, as: UTF8.self))
                buffer.append(text)
                while let nl = buffer.firstIndex(of: "\n") {
                    let line = String(buffer[buffer.startIndex..<nl])
                    buffer.removeSubrange(buffer.startIndex...nl)
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty { continue }
                    self.handleLine(trimmed)
                }
            }
            // PTY closed
            if let self, !self.isTerminated() {
                self.setState(.done)
                cont.yield(SmoothieEvent(type: .done, content: "session ended"))
                cont.finish()
            }
        }

        // Also monitor exit code
        let exitStream = pty.exitStream
        Task.detached { [weak self] in
            for await code in exitStream {
                if code != 0, let self, !self.isTerminated() {
                    self.setState(.error)
                    self.eventContinuation.yield(SmoothieEvent(
                        type: .error,
                        content: "claude exited with code \(code)"
                    ))
                }
            }
        }
    }

    private func handleLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else {
            return
        }

        switch type {
        case "system":
            if let subtype = obj["subtype"] as? String, subtype == "init" {
                yield(.thinking, content: "starting")
            }
        case "assistant":
            guard let message = obj["message"] as? [String: Any],
                  let contentBlocks = message["content"] as? [[String: Any]] else {
                return
            }
            for block in contentBlocks {
                let blockType = (block["type"] as? String) ?? ""
                switch blockType {
                case "text":
                    let text = (block["text"] as? String) ?? ""
                    if !text.isEmpty { yield(.message, content: text) }
                case "thinking":
                    let text = (block["thinking"] as? String) ?? ""
                    if !text.isEmpty { yield(.thinking, content: text) }
                case "tool_use":
                    let name = (block["name"] as? String) ?? "tool"
                    let input = block["input"] as? [String: Any]
                    var meta: [String: AnyCodable] = ["name": AnyCodable(name)]
                    if let path = input?["file_path"] as? String {
                        meta["path"] = AnyCodable(path)
                        yield(.file_edit, content: path, metadata: meta)
                    } else if let path = input?["path"] as? String {
                        meta["path"] = AnyCodable(path)
                        yield(.tool_use, content: name, metadata: meta)
                    } else {
                        yield(.tool_use, content: name, metadata: meta)
                    }
                default:
                    break
                }
            }
        case "user":
            // echo of the user message — ignore
            break
        case "result":
            let subtype = (obj["subtype"] as? String) ?? "unknown"
            if subtype == "success" {
                setState(.waiting)
                yield(.waiting, content: "")
            } else {
                let err = (obj["result"] as? String) ?? "result: \(subtype)"
                setState(.error)
                yield(.error, content: err)
            }
        case "stream_event":
            // partial message chunks — skip for MVP (we already get whole messages)
            break
        default:
            break
        }
    }

    private func yield(_ type: EventType, content: String, metadata: [String: AnyCodable]? = nil) {
        if isTerminated() { return }
        eventContinuation.yield(SmoothieEvent(type: type, content: content, metadata: metadata))
    }

    private func setState(_ new: SessionState) {
        stateLock.lock(); _state = new; stateLock.unlock()
    }

    private func isTerminated() -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return _terminated
    }

    private static func findExecutable(_ name: String) throws -> String {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        throw AdapterError.launchFailed("\(name) not found")
    }
}

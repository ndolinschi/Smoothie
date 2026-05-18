import Foundation

/// Adapter for the `opencode` CLI. Spawns `opencode serve` with `cwd` set to the
/// project directory, then talks to it over HTTP. Events arrive via the
/// `/event` SSE stream and are mapped to `SmoothieEvent`.
final class OpenCodeAdapter: AgentAdapter, @unchecked Sendable {
    let cli: CLIType = .opencode
    let events: AsyncStream<SmoothieEvent>

    private let eventContinuation: AsyncStream<SmoothieEvent>.Continuation
    private let serverProcess: Process
    private let baseURL: URL
    private let sessionID: String
    private let urlSession: URLSession
    private var sseClient: SSEClient?
    private var sseDataBuffer: String = ""
    private let sseBufferLock = NSLock()

    private let stateLock = NSLock()
    private var _state: SessionState = .starting
    private var _terminated = false

    private init(serverProcess: Process, baseURL: URL, sessionID: String) {
        self.serverProcess = serverProcess
        self.baseURL = baseURL
        self.sessionID = sessionID

        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = .infinity
        cfg.httpMaximumConnectionsPerHost = 4
        self.urlSession = URLSession(configuration: cfg)

        let (s, c) = AsyncStream<SmoothieEvent>.makeStream(bufferingPolicy: .unbounded)
        self.events = s
        self.eventContinuation = c
    }

    static func make(config: AdapterStartConfig) async throws -> any AgentAdapter {
        let (process, baseURL) = try await spawnServer(cwd: config.projectPath)

        let createBody = try JSONSerialization.data(withJSONObject: [
            "directory": config.projectPath
        ])
        let createURL = URL(string: "\(baseURL.absoluteString)/session")!
        let sessionID: String
        do {
            sessionID = try await postJSON(url: createURL, body: createBody, keyPath: "id")
        } catch {
            process.terminate()
            throw error
        }

        let adapter = OpenCodeAdapter(serverProcess: process, baseURL: baseURL, sessionID: sessionID)
        adapter.startSSE()

        if let promptText = config.systemPromptText, !promptText.isEmpty {
            // Best-effort: send as the first user message tagged as system context.
            // opencode doesn't expose a system-prompt API; we prepend instructions.
            Task.detached { [weak adapter] in
                try? await Task.sleep(nanoseconds: 200_000_000)
                try? await adapter?.send("[smoothie-context]\n\(promptText)")
            }
        }

        return adapter
    }

    func currentState() -> SessionState {
        stateLock.lock(); defer { stateLock.unlock() }
        return _state
    }

    func send(_ content: String) async throws {
        guard !isTerminated() else { throw AdapterError.io("adapter terminated") }
        let body = try JSONSerialization.data(withJSONObject: [
            "parts": [["type": "text", "text": content]]
        ])
        guard let url = URL(string: "\(baseURL.absoluteString)/session/\(sessionID)/message") else {
            throw AdapterError.protocolError("Bad URL for send")
        }
        _ = try await Self.postRaw(url: url, body: body)
        setState(.thinking)
    }

    func terminate() async {
        let already = beginTerminate()
        guard !already else { return }

        sseClient?.cancel()
        // Best-effort delete; ignore failures
        if let url = URL(string: "\(baseURL.absoluteString)/session/\(sessionID)") {
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            req.timeoutInterval = 2
            _ = try? await urlSession.data(for: req)
        }
        if serverProcess.isRunning {
            serverProcess.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [serverProcess] in
                if serverProcess.isRunning { kill(serverProcess.processIdentifier, SIGKILL) }
            }
        }
        setState(.done)
        eventContinuation.finish()
    }

    // MARK: - SSE

    private func startSSE() {
        guard let url = URL(string: "\(baseURL.absoluteString)/event") else { return }
        let sid = self.sessionID

        let client = SSEClient(
            onLine: { [weak self] line in
                self?.handleSSELine(line, sessionID: sid)
            },
            onError: { [weak self] error in
                if let err = error, (err as? URLError)?.code != .cancelled {
                    self?.eventContinuation.yield(SmoothieEvent(
                        type: .error,
                        content: "SSE stream ended: \(err.localizedDescription)"
                    ))
                }
            }
        )
        self.sseClient = client
        client.start(url: url)
    }

    private func handleSSELine(_ line: String, sessionID: String) {
        sseBufferLock.lock()
        if line.isEmpty {
            let pending = sseDataBuffer
            sseDataBuffer = ""
            sseBufferLock.unlock()
            if !pending.isEmpty {
                handleEvent(rawJSON: pending, sessionID: sessionID)
            }
            return
        }
        if line.hasPrefix("data:") {
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if !sseDataBuffer.isEmpty { sseDataBuffer.append("\n") }
            sseDataBuffer.append(payload)
        }
        sseBufferLock.unlock()
    }

    private func handleEvent(rawJSON: String, sessionID: String) {
        guard let data = rawJSON.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let typeRaw = any["type"] as? String,
              let props = any["properties"] as? [String: Any] else {
            return
        }

        // All session-scoped events carry sessionID in properties.
        if let sid = props["sessionID"] as? String, sid != sessionID {
            return
        }

        switch typeRaw {
        case "session.status":
            if let status = props["status"] as? [String: Any],
               let t = status["type"] as? String {
                switch t {
                case "busy":
                    setState(.thinking)
                    yield(.thinking, content: "")
                case "idle":
                    setState(.waiting)
                    yield(.waiting, content: "")
                default: break
                }
            }
        case "session.idle":
            setState(.waiting)
            yield(.waiting, content: "")
        case "session.error":
            let errMsg: String
            if let err = props["error"] as? [String: Any] {
                if let d = err["data"] as? [String: Any], let m = d["message"] as? String {
                    errMsg = m
                } else if let m = err["message"] as? String {
                    errMsg = m
                } else {
                    errMsg = String(describing: err)
                }
            } else {
                errMsg = "Unknown error"
            }
            setState(.error)
            yield(.error, content: errMsg)
        case "message.part.updated":
            guard let part = props["part"] as? [String: Any],
                  let partType = part["type"] as? String else { return }
            switch partType {
            case "text":
                let text = (part["text"] as? String) ?? ""
                if !text.isEmpty { yield(.message, content: text) }
            case "tool", "tool_use":
                let toolName = (part["tool"] as? String) ?? (part["name"] as? String) ?? "tool"
                yield(.tool_use, content: toolName, metadata: metadataFrom(part))
            case "tool_result":
                let summary = (part["text"] as? String) ?? "tool_result"
                yield(.tool_use, content: summary, metadata: metadataFrom(part))
            default:
                break
            }
        case "session.diff":
            if let diffs = props["diff"] as? [[String: Any]] {
                for d in diffs {
                    let path = (d["path"] as? String) ?? "(unknown)"
                    yield(.file_edit, content: path, metadata: ["path": AnyCodable(path)])
                }
            }
        default:
            break
        }
    }

    private func metadataFrom(_ dict: [String: Any]) -> [String: AnyCodable]? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let decoded = try? JSONDecoder().decode([String: AnyCodable].self, from: data) else {
            return nil
        }
        return decoded
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

    private func beginTerminate() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        if _terminated { return true }
        _terminated = true
        return false
    }

    // MARK: - Server spawning

    private static func spawnServer(cwd: String) async throws -> (Process, URL) {
        let executableURL = try findExecutable("opencode")
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["serve", "--hostname", "127.0.0.1", "--port", "0", "--print-logs"]
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)

        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = stdoutPipe

        try process.run()

        let url = try await waitForServerURL(pipes: [stderrPipe, stdoutPipe], timeout: 15.0)
        installDrainHandlers(pipes: [stderrPipe, stdoutPipe])
        return (process, url)
    }

    private static func waitForServerURL(pipes: [Pipe], timeout: TimeInterval) async throws -> URL {
        let pattern = try NSRegularExpression(pattern: "http://[0-9.]+:[0-9]+")

        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var accumulated = ""
            var done = false
        }
        let box = Box()

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            for pipe in pipes {
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty { return }
                    guard let text = String(data: data, encoding: .utf8) else { return }
                    box.lock.lock()
                    if box.done { box.lock.unlock(); return }
                    box.accumulated += text
                    let range = NSRange(box.accumulated.startIndex..., in: box.accumulated)
                    if let match = pattern.firstMatch(in: box.accumulated, range: range),
                       let r = Range(match.range, in: box.accumulated),
                       let url = URL(string: String(box.accumulated[r])) {
                        box.done = true
                        box.lock.unlock()
                        cont.resume(returning: url)
                        return
                    }
                    box.lock.unlock()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                box.lock.lock()
                let alreadyDone = box.done
                if !alreadyDone { box.done = true }
                box.lock.unlock()
                if !alreadyDone {
                    for p in pipes { p.fileHandleForReading.readabilityHandler = nil }
                    cont.resume(throwing: AdapterError.launchFailed("opencode serve did not announce a listen URL within \(timeout)s"))
                }
            }
        }
    }

    /// Keep pipes drained so opencode doesn't block writing to stderr/stdout.
    private static func installDrainHandlers(pipes: [Pipe]) {
        for pipe in pipes {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                _ = handle.availableData
            }
        }
    }

    private static func findExecutable(_ name: String) throws -> URL {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw AdapterError.launchFailed("\(name) not found on PATH")
    }

    // MARK: - HTTP helpers

    private static func postJSON(url: URL, body: Data, keyPath: String) async throws -> String {
        let data = try await postRaw(url: url, body: body)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = json[keyPath] as? String else {
            throw AdapterError.protocolError("Missing '\(keyPath)' in response: \(String(data: data, encoding: .utf8) ?? "<binary>")")
        }
        return value
    }

    private static func postRaw(url: URL, body: Data) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw AdapterError.protocolError("HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        }
        return data
    }
}

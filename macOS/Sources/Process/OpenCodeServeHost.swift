import Foundation
import Shared

/// OpenCode ships its own backend (`opencode serve`) which we drive over
/// HTTP + SSE rather than pipes. The host:
///
/// 1. Spawns `opencode serve --port 0 --print-logs` in the project's cwd.
/// 2. Watches stderr for `opencode server listening on http://127.0.0.1:<port>`
///    to capture the bound port.
/// 3. Creates an OpenCode session via `POST /session` and subscribes to
///    `/global/event` over SSE for that session's updates.
/// 4. `write(_:)` POSTs `/session/{id}/prompt_async` with a
///    `parts:[{type:"text",text:...}]` body. The response returns 200
///    immediately; assistant output streams in via the SSE feed.
/// 5. `terminate()` aborts the active turn and tears down the child process.
@MainActor
final class OpenCodeServeHost: NSObject, SessionHost {
    let session: Session
    private let executable: String
    private let cwd: String

    private var process: Process?
    private var logStdout: Pipe?
    private var logStderr: Pipe?
    private var logBuffer = Data()

    private var port: Int?
    private var ocSessionId: String?
    private var pendingWrites: [String] = []   // queued while not ready

    private var sseSession: URLSession?
    private var sseTask: URLSessionDataTask?
    private var sseLineBuffer = ""

    /// Buffered text content per message part. Some opencode versions emit
    /// per-token deltas (`properties.delta`) and others emit a cumulative
    /// `part.text` snapshot — we handle both. P30.c — was flushed only on
    /// `session.idle` which produced the "no streaming, then a full reply
    /// dumps" delay the user complained about. Now we emit a MESSAGE event
    /// on every part update with the running buffer, tagged with the part
    /// id in metadata so iOS coalesces consecutive same-part events into
    /// one bubble (see `SessionLiveStore.ingest`).
    private var textBuffers: [String: String] = [:]
    /// Tool / file parts we've already emitted, keyed by `part.id`, so
    /// repeated `message.part.updated` events for the same tool call don't
    /// produce duplicate TOOL_USE rows.
    private var emittedToolParts: Set<String> = []

    /// Deadman timer that fires `markError` if `opencode serve` never
    /// prints the "listening on" log line. Without this we used to hang
    /// at `.starting` forever — common cause is the user hasn't run
    /// `opencode auth login` yet, in which case the server exits silently.
    private var portTimeoutTask: Task<Void, Never>?

    var isRunning: Bool { process?.isRunning ?? false }

    /// Assembled Smoothie safety/system prompt. The opencode server has
    /// no per-session system-prompt parameter on the endpoints we drive,
    /// so it's prepended to the first prompt's text instead.
    private let systemPrompt: String?
    private var sentSystemPrompt = false

    init(session: Session, executable: String, cwd: String, systemPrompt: String? = nil) {
        self.session = session
        self.executable = executable
        self.cwd = cwd
        self.systemPrompt = systemPrompt
        super.init()
    }

    func start() throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = ["serve", "--port", "0", "--print-logs"]
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        let weakSelfRef = WeakOCBox(self)
        outPipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            if data.isEmpty { return }
            Task { @MainActor in weakSelfRef.value?.handleLog(data) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            if data.isEmpty { return }
            Task { @MainActor in weakSelfRef.value?.handleLog(data) }
        }
        proc.terminationHandler = { p in
            let code = p.terminationStatus
            Task { @MainActor in await weakSelfRef.value?.handleTermination(code: code) }
        }

        self.process = proc
        self.logStdout = outPipe
        self.logStderr = errPipe
        try proc.run()

        // 10s deadman timer: if opencode serve hasn't printed the
        // "listening on" line by now AND we haven't created an opencode
        // session, surface a clear error to the iOS app instead of leaving
        // it stuck in `.starting`.
        let weakRef = WeakOCBox(self)
        portTimeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard let self = weakRef.value else { return }
            if self.port == nil && self.ocSessionId == nil {
                try? await self.session.markError(message:
                    "OpenCode server didn't bind a port within 10s. " +
                    "Run `opencode auth login` and confirm a model is configured, then try again.")
                self.terminate()
            }
        }
    }

    func write(_ content: String) async throws {
        try? await session.noteUserMessageSent()
        var outgoing = content
        if !sentSystemPrompt {
            sentSystemPrompt = true
            if let systemPrompt, !systemPrompt.isEmpty {
                outgoing = systemPrompt + "\n\n---\n\n" + content
            }
        }
        guard let port, let id = ocSessionId else {
            // Queue until the server is ready.
            pendingWrites.append(outgoing)
            return
        }
        try await postPrompt(port: port, sessionID: id, content: outgoing)
    }

    func terminate() {
        portTimeoutTask?.cancel()
        portTimeoutTask = nil
        if let port, let id = ocSessionId, let url = abortURL(port: port, sessionId: id) {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            Task.detached { _ = try? await URLSession.shared.data(for: req) }
        }
        sseTask?.cancel()
        sseSession?.invalidateAndCancel()
        sseTask = nil
        sseSession = nil

        guard let proc = process, proc.isRunning else { return }
        proc.terminate()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
            }
        }
    }

    /// Abort just the in-flight turn — opencode keeps its server up and the
    /// session record. The next `write(_:)` re-uses the same session id.
    func abort() async {
        guard let port, let id = ocSessionId, let url = abortURL(port: port, sessionId: id) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        _ = try? await URLSession.shared.data(for: req)
    }

    /// Build the abort URL with the session id percent-escaped as a single
    /// path component. The opencode-supplied id is usually a UUID-ish slug
    /// without special characters, but we don't trust it — a malicious or
    /// malformed value containing `/` or `?` would otherwise either land
    /// on a different opencode route or split the URL into garbage. Using
    /// `URLComponents` + `addingPercentEncoding(.urlPathAllowed)` keeps the
    /// id contained.
    private func abortURL(port: Int, sessionId: String) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = port
        let escapedId = sessionId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sessionId
        components.percentEncodedPath = "/session/\(escapedId)/abort"
        return components.url
    }

    // MARK: - Log parsing

    private func handleLog(_ data: Data) {
        logBuffer.append(data)
        guard let text = String(data: logBuffer, encoding: .utf8) else { return }
        logBuffer.removeAll(keepingCapacity: true)

        if port == nil {
            let pattern = #"opencode server listening on http://127\.0\.0\.1:(\d+)"#
            if let range = text.range(of: pattern, options: .regularExpression) {
                let match = String(text[range])
                if let captured = match.split(separator: ":").last,
                   let p = Int(captured) {
                    port = p
                    // Server is up — cancel the deadman timer.
                    portTimeoutTask?.cancel()
                    portTimeoutTask = nil
                    Task { @MainActor in await self.connectOnceReady() }
                }
            }
        }
    }

    private func connectOnceReady() async {
        guard let port else { return }
        // Wait a moment for the server's HTTP routes to register after the
        // listening log line.
        try? await Task.sleep(for: .milliseconds(150))

        // Create an OpenCode session.
        var createReq = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/session")!)
        createReq.httpMethod = "POST"
        createReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        createReq.httpBody = Data("{}".utf8)
        do {
            let (data, _) = try await URLSession.shared.data(for: createReq)
            struct CreateResp: Decodable { let id: String }
            let resp = try JSONDecoder().decode(CreateResp.self, from: data)
            ocSessionId = resp.id
            // Surface the opencode session id so the iOS descriptor carries
            // it. Used by the "Open in Terminal" handoff so a fresh
            // `opencode` invocation can reference the same conversation
            // (no `--resume` flag today; we just open the project cwd).
            session.setProviderSessionId(id: resp.id)
        } catch {
            try? await session.markError(message: "opencode session create failed: \(error.localizedDescription)")
            return
        }

        // Subscribe to global SSE.
        subscribeSSE(port: port)

        // Flush any queued writes that came in before the server was ready.
        // The first queued turn carries the prepended system prompt, so a
        // silently-swallowed failure here would lose the safety rules for
        // the whole session. Surface it instead of dropping it.
        guard let sessionID = ocSessionId else { return }
        let queued = pendingWrites
        pendingWrites.removeAll()
        for content in queued {
            do {
                try await postPrompt(port: port, sessionID: sessionID, content: content)
            } catch {
                try? await session.markError(
                    message: "Couldn't send the first turn to OpenCode: \(error.localizedDescription)"
                )
                break
            }
        }
    }

    /// `/session/:id/prompt_async` is the headless equivalent of opencode's
    /// chat-window send — it queues the prompt and returns 200 immediately,
    /// streaming the assistant's response via `/global/event`. The legacy
    /// `/message` endpoint is synchronous and blocks until completion, which
    /// holds the iOS request open for the full turn and times out.
    private func postPrompt(port: Int, sessionID: String, content: String) async throws {
        let body: [String: Any] = [
            "parts": [["type": "text", "text": content]]
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = port
        let escapedId = sessionID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sessionID
        components.percentEncodedPath = "/session/\(escapedId)/prompt_async"
        guard let url = components.url else {
            throw NSError(domain: "OpenCodeServeHost", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not build prompt URL for session \(sessionID)"])
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        _ = try await URLSession.shared.data(for: req)
    }

    // MARK: - SSE

    private func subscribeSSE(port: Int) {
        guard sseTask == nil else { return }
        let url = URL(string: "http://127.0.0.1:\(port)/global/event")!
        var req = URLRequest(url: url)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.timeoutInterval = .infinity
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = .infinity
        cfg.timeoutIntervalForResource = .infinity
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        self.sseSession = session
        self.sseTask = session.dataTask(with: req)
        self.sseTask?.resume()
    }

    private func handleSSEPayload(_ json: [String: Any]) async {
        guard let payload = json["payload"] as? [String: Any],
              let type = payload["type"] as? String,
              let properties = payload["properties"] as? [String: Any] else { return }

        // Filter to our session id whenever the event carries one.
        let propSessionID = properties["sessionID"] as? String
            ?? (properties["part"] as? [String: Any])?["sessionID"] as? String
        if let propSessionID, let ocSessionId, propSessionID != ocSessionId { return }

        switch type {
        case "message.part.delta":
            handlePartDelta(properties)
        case "message.part.updated":
            handlePartUpdated(properties)
        case "session.idle":
            await flushBufferedTextParts()
            try? await session.injectEvent(event: makeEvent(.waiting, content: ""))
        case "session.error":
            let err = properties["error"] as? [String: Any]
            let msg = (err?["message"] as? String) ?? "opencode error"
            try? await session.markError(message: msg)
        default:
            break
        }
    }

    private func handlePartDelta(_ properties: [String: Any]) {
        guard let partID = properties["partID"] as? String,
              let delta = properties["delta"] as? String,
              !delta.isEmpty else { return }
        let field = (properties["field"] as? String) ?? "text"
        guard field == "text" else { return }   // ignore reasoning deltas for now
        textBuffers[partID, default: ""].append(delta)
        emitStreamingText(partID: partID)
    }

    private func handlePartUpdated(_ properties: [String: Any]) {
        guard let part = properties["part"] as? [String: Any],
              let partID = part["id"] as? String,
              let partType = part["type"] as? String else { return }

        switch partType {
        case "text":
            // Cumulative snapshot if delta wasn't already supplied.
            if let snapshot = part["text"] as? String, !snapshot.isEmpty {
                textBuffers[partID] = snapshot
            } else if let delta = properties["delta"] as? String, !delta.isEmpty {
                textBuffers[partID, default: ""].append(delta)
            }
            emitStreamingText(partID: partID)
        case "tool":
            if emittedToolParts.contains(partID) { return }
            emittedToolParts.insert(partID)
            let toolName = (part["tool"] as? String)
                ?? ((part["state"] as? [String: Any])?["title"] as? String)
                ?? "tool"
            Task { @MainActor in
                try? await session.injectEvent(event: makeEvent(.toolUse, content: toolName))
            }
        case "file":
            if emittedToolParts.contains(partID) { return }
            emittedToolParts.insert(partID)
            let path = (part["path"] as? String) ?? "file"
            Task { @MainActor in
                try? await session.injectEvent(event: makeEvent(.toolUse, content: "Read \(path)"))
            }
        default:
            break
        }
    }

    /// Push the running text buffer for `partID` as a MESSAGE event
    /// tagged with the part id. iOS's SessionLiveStore.ingest replaces
    /// any prior MESSAGE event carrying the same part id, so the user
    /// sees the message growing in place rather than as N stacked
    /// bubbles. Fire-and-forget — opencode emits deltas faster than
    /// our K/N broker can serialise.
    private func emitStreamingText(partID: String) {
        let text = textBuffers[partID] ?? ""
        guard !text.isEmpty else { return }
        let timestamp = Int64(Date.now.timeIntervalSince1970 * 1000)
        Task { @MainActor [weak self] in
            try? await self?.session.injectStreamingText(
                partId: partID,
                text: text,
                timestamp: timestamp
            )
        }
    }

    private func flushBufferedTextParts() async {
        // session.idle fires after the last delta — by this point iOS
        // has already seen the in-flight events thanks to emitStreamingText.
        // Drop the buffer so the next turn starts clean.
        textBuffers.removeAll()
        emittedToolParts.removeAll()
    }

    private func makeEvent(_ type: EventType, content: String) -> SmoothieEvent {
        SmoothieEvent(
            type: type,
            content: content,
            metadata: nil,
            timestamp: Int64(Date.now.timeIntervalSince1970 * 1000)
        )
    }

    // MARK: - Termination

    private func handleTermination(code: Int32) async {
        logStdout?.fileHandleForReading.readabilityHandler = nil
        logStderr?.fileHandleForReading.readabilityHandler = nil
        sseTask?.cancel()
        sseSession?.invalidateAndCancel()
        sseTask = nil
        sseSession = nil

        if code != 0 {
            try? await session.markError(message: "opencode serve exited with code \(code)")
        }
    }
}

extension OpenCodeServeHost: URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        let weakSelfRef = WeakOCBox(unsafeOwner: self)
        Task { @MainActor in
            guard let me = weakSelfRef.value else { return }
            me.sseLineBuffer.append(chunk)
            while let range = me.sseLineBuffer.range(of: "\n\n") {
                let frame = String(me.sseLineBuffer[..<range.lowerBound])
                me.sseLineBuffer.removeSubrange(..<range.upperBound)
                me.processFrame(frame)
            }
        }
    }

    private func processFrame(_ frame: String) {
        var dataLines: [String] = []
        for raw in frame.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            if line.hasPrefix("data:") {
                let body = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                if !body.isEmpty { dataLines.append(body) }
            }
        }
        guard !dataLines.isEmpty else { return }
        let joined = dataLines.joined(separator: "\n")
        guard let data = joined.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        Task { @MainActor in await self.handleSSEPayload(json) }
    }
}

@MainActor
private final class WeakOCBox {
    weak var value: OpenCodeServeHost?
    init(_ value: OpenCodeServeHost) { self.value = value }

    nonisolated init(unsafeOwner: OpenCodeServeHost) {
        self.value = unsafeOwner
    }
}

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
/// 4. `write(_:)` POSTs `/session/{id}/message` with a `parts:[{type:"text",text:...}]`
///    body and waits for the SSE stream to surface assistant events.
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

    /// Tracks the cumulative assistant text per messageID so we can emit
    /// incremental MESSAGE events as the response streams in.
    private var emittedLength: [String: Int] = [:]

    var isRunning: Bool { process?.isRunning ?? false }

    init(session: Session, executable: String, cwd: String) {
        self.session = session
        self.executable = executable
        self.cwd = cwd
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
    }

    func write(_ content: String) async throws {
        try? await session.noteUserMessageSent()
        guard let port, let id = ocSessionId else {
            // Queue until the server is ready.
            pendingWrites.append(content)
            return
        }
        try await postMessage(port: port, sessionID: id, content: content)
    }

    func terminate() {
        if let port, let id = ocSessionId {
            var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/session/\(id)/abort")!)
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
                    Task { @MainActor in await self.connectOnceReady() }
                }
            }
        }
    }

    private func connectOnceReady() async {
        guard let port else { return }
        // Wait a moment for the server's HTTP routes to fully register
        // after the listening log line — opencode logs the port before
        // routes are bound on some versions.
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
        } catch {
            try? await session.markError(message: "opencode session create failed: \(error.localizedDescription)")
            return
        }

        // Subscribe to global SSE.
        subscribeSSE(port: port)

        // Flush any queued writes that came in before the server was ready.
        let queued = pendingWrites
        pendingWrites.removeAll()
        for content in queued {
            try? await postMessage(port: port, sessionID: ocSessionId!, content: content)
        }
    }

    private func postMessage(port: Int, sessionID: String, content: String) async throws {
        let body: [String: Any] = [
            "parts": [["type": "text", "text": content]]
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/session/\(sessionID)/message")!)
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
        // OpenCode SSE frames look like:
        //   data: { "payload": { "type": "message.updated", "properties": { ... } } }
        guard let payload = json["payload"] as? [String: Any],
              let type = payload["type"] as? String,
              let properties = payload["properties"] as? [String: Any] else { return }

        switch type {
        case "message.updated":
            await handleMessageUpdated(properties)
        case "message.removed":
            if let messageID = properties["messageID"] as? String {
                emittedLength.removeValue(forKey: messageID)
            }
        default:
            break
        }
    }

    private func handleMessageUpdated(_ properties: [String: Any]) async {
        guard let info = properties["info"] as? [String: Any] else { return }
        // Filter to our own opencode session id.
        if let sessionID = info["sessionID"] as? String, sessionID != ocSessionId { return }
        guard let messageID = info["id"] as? String else { return }
        guard let role = info["role"] as? String, role == "assistant" else { return }

        // Surface an error if the assistant message ended with one.
        if let errorBlob = info["error"] as? [String: Any] {
            let data = errorBlob["data"] as? [String: Any]
            let msg = (data?["message"] as? String) ?? (errorBlob["name"] as? String) ?? "opencode error"
            try? await session.markError(message: msg)
            return
        }

        // OpenCode hasn't surfaced a `parts` field directly here; it lives on
        // a separate `part.updated` event in some builds. For v0 we don't
        // accumulate text — we just rely on `time.completed` to mark the
        // turn as ready for the user.
        if let time = info["time"] as? [String: Any], time["completed"] is NSNumber {
            let event = SmoothieEvent(
                type: EventType.waiting,
                content: "",
                metadata: nil,
                timestamp: Int64(Date.now.timeIntervalSince1970 * 1000)
            )
            try? await session.injectEvent(event: event)
            emittedLength.removeValue(forKey: messageID)
        }
    }

    /// Find the textual content the assistant has produced so far in the
    /// current message — concatenate every `text` part if present.
    private func extractText(from info: [String: Any]) -> String {
        guard let parts = info["parts"] as? [[String: Any]] else { return "" }
        return parts.compactMap { p -> String? in
            guard (p["type"] as? String) == "text" else { return nil }
            return p["text"] as? String
        }.joined()
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
            // SSE messages are separated by an empty line.
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

    // The SSE delegate runs on a non-isolated queue and needs to construct
    // a weak reference without hopping. We do the unsafe construction here
    // and immediately bounce back to the MainActor before reading `.value`.
    nonisolated init(unsafeOwner: OpenCodeServeHost) {
        self.value = unsafeOwner
    }
}

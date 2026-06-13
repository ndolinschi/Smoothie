import Foundation
import Shared

/// Cursor CLI driver. The CLI speaks ACP (Agent Client Protocol) — a
/// JSON-RPC 2.0 dialect over stdio. We spawn `cursor-agent acp` once
/// and keep stdin/stdout open for the lifetime of the session.
///
/// Wire shape: each JSON-RPC frame is one line. Server-to-client
/// notifications (the ones we consume) carry `method: session/update`
/// with content blocks; the `CursorAdapter` line-parses these and
/// turns them into SmoothieEvents.
///
/// What this v1 implements:
///   - `initialize` request on host start (protocol version + capabilities).
///   - `session/new` request once the initialize response arrives.
///   - `session/prompt` request on each `write(_:)`.
///   - `session/request_permission` is auto-approved (response with
///     "allow") — surfacing a real permission UI is a follow-up.
///   - `fs/read_text_file` / `fs/write_text_file` requests fulfilled
///     against the project cwd (best-effort, sandbox-respecting).
///
/// What's NOT implemented yet (deferred):
///   - Multi-session ACP. We only run one session per host.
///   - Streaming partial responses for `fs/*` requests.
///   - Auth flow (`authenticate` request). We assume the user has
///     already run `cursor-agent` once interactively to sign in.
@MainActor
final class CursorACPHost: NSObject, SessionHost {
    let session: Session
    private let executable: String
    private let cwd: String
    private let baseArgs: [String]
    private let env: [String: String]

    private var process: Process?
    private var stdinHandle: FileHandle?
    // ACP frames are newline-delimited JSON-RPC; this host does its own
    // frame splitting on stdoutBuffer below (it must dispatch requests vs
    // responses vs notifications, not just hand lines to a parser).
    private var stdoutBuffer = Data()
    private var stderr = BoundedStderr()
    /// Monotonically increasing JSON-RPC request ids. Even ids are
    /// requests we send; odd ids come from the server.
    private var nextRequestId: Int = 0
    /// ACP session id the server returns from `session/new`. Used as
    /// the `sessionId` param for every subsequent `session/prompt`.
    private var acpSessionId: String?
    /// Buffer of user prompts queued before the ACP handshake finishes.
    /// Flushed once `session/new` returns.
    private var pendingPrompts: [String] = []
    private var handshakeComplete = false

    /// ACP has no system-prompt channel in the surface we drive, so the
    /// safety/system prompt is prepended to the first `session/prompt`
    /// text; the ACP session then carries it.
    private var promptInjector: SystemPromptInjector

    var isRunning: Bool { process?.isRunning ?? false }

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
        super.init()
    }

    func start() throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = baseArgs
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)

        var procEnv = ProcessInfo.processInfo.environment
        for (k, v) in env { procEnv[k] = v }
        proc.environment = procEnv

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

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

        self.process = proc
        self.stdinHandle = stdinPipe.fileHandleForWriting
        try proc.run()

        // Kick off the ACP handshake.
        sendInitialize()
    }

    func write(_ content: String) async throws {
        try? await session.noteUserMessageSent()
        let outgoing = promptInjector.decorate(content)
        guard let acpSessionId, handshakeComplete else {
            pendingPrompts.append(outgoing)
            return
        }
        sendPrompt(sessionId: acpSessionId, content: outgoing)
    }

    func terminate() {
        guard let proc = process else { return }
        SubprocessLifecycle.terminateWithGrace(proc)
    }

    /// ACP `session/cancel` cancels the current turn but keeps the
    /// ACP session alive. The next `write(_:)` reuses the same
    /// sessionId.
    func abort() async {
        guard let acpSessionId else { return }
        sendNotification(
            method: "session/cancel",
            params: ["sessionId": acpSessionId]
        )
    }

    // MARK: - JSON-RPC client

    private func sendInitialize() {
        sendRequest(
            method: "initialize",
            params: [
                "protocolVersion": 1 as Int,
                "clientCapabilities": [
                    "fs": [
                        "readTextFile": true,
                        "writeTextFile": true,
                    ],
                ],
            ] as [String: Any]
        )
    }

    private func sendNewSession() {
        sendRequest(
            method: "session/new",
            params: [
                "cwd": cwd,
                "mcpServers": [] as [Any],
            ] as [String: Any]
        )
    }

    private func sendPrompt(sessionId: String, content: String) {
        sendRequest(
            method: "session/prompt",
            params: [
                "sessionId": sessionId,
                "prompt": [
                    ["type": "text", "text": content]
                ] as [Any],
            ] as [String: Any]
        )
    }

    private func sendRequest(method: String, params: Any) {
        nextRequestId += 2     // even ids for our requests
        let id = nextRequestId
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]
        writeJSON(envelope)
    }

    private func sendNotification(method: String, params: Any) {
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
        ]
        writeJSON(envelope)
    }

    private func sendResponse(id: Any, result: Any) {
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "result": result,
        ]
        writeJSON(envelope)
    }

    private func writeJSON(_ envelope: [String: Any]) {
        guard let handle = stdinHandle else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: envelope) else {
            return
        }
        var bytes = data
        bytes.append(0x0A)     // newline
        try? handle.write(contentsOf: bytes)
    }

    // MARK: - JSON-RPC server (incoming frames)

    private func handleStdout(_ data: Data) async {
        stdoutBuffer.append(data)
        while let nl = stdoutBuffer.firstIndex(of: 0x0A) {
            let lineData = stdoutBuffer[..<nl]
            stdoutBuffer.removeSubrange(...nl)
            guard !lineData.isEmpty,
                  let line = String(data: lineData, encoding: .utf8) else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            await handleFrame(trimmed)
        }
    }

    /// Dispatches one JSON-RPC frame. Notifications without an id are
    /// forwarded to the K/N parser via `session.ingestText` so the
    /// CursorAdapter can map `session/update` to SmoothieEvents. Server
    /// requests get a response. Responses to our own requests advance
    /// the handshake / queue state.
    private func handleFrame(_ line: String) async {
        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }

        // Server-issued request → respond.
        if let id = obj["id"], let method = obj["method"] as? String {
            await handleServerRequest(id: id, method: method, params: obj["params"])
            return
        }

        // Response to one of our requests.
        if obj["id"] != nil, let result = obj["result"] {
            await handleResponse(result: result)
            return
        }

        // Notification — forward the raw line to the K/N parser.
        if obj["method"] is String {
            _ = try? await session.ingestText(text: line + "\n")
            return
        }
    }

    private func handleServerRequest(id: Any, method: String, params: Any?) async {
        switch method {
        case "session/request_permission":
            // Auto-allow. Future work: surface a permission card on iOS.
            let allowed: [String: Any] = [
                "outcome": ["outcome": "selected", "optionId": "allow_once"],
            ]
            sendResponse(id: id, result: allowed)
        case "fs/read_text_file":
            let path = (params as? [String: Any])?["path"] as? String ?? ""
            let absolute = absolutize(path)
            let content = (try? String(contentsOfFile: absolute, encoding: .utf8)) ?? ""
            sendResponse(id: id, result: ["content": content])
        case "fs/write_text_file":
            let p = params as? [String: Any]
            let path = (p?["path"] as? String) ?? ""
            let content = (p?["content"] as? String) ?? ""
            let absolute = absolutize(path)
            try? content.write(toFile: absolute, atomically: true, encoding: .utf8)
            sendResponse(id: id, result: [:] as [String: Any])
        default:
            // Unknown method — respond with an error so the agent
            // doesn't hang waiting on us.
            sendResponse(id: id, result: [
                "error": ["code": -32601, "message": "Method not found: \(method)"],
            ])
        }
    }

    private func absolutize(_ path: String) -> String {
        if path.hasPrefix("/") { return path }
        return (cwd as NSString).appendingPathComponent(path)
    }

    private func handleResponse(result: Any) async {
        // We only track two responses that drive the handshake:
        //   - initialize → fire session/new
        //   - session/new → capture sessionId, flush queued prompts.
        guard let resultObj = result as? [String: Any] else { return }
        if !handshakeComplete && acpSessionId == nil {
            if let sessionId = resultObj["sessionId"] as? String {
                acpSessionId = sessionId
                handshakeComplete = true
                session.setProviderSessionId(id: sessionId)
                let queued = pendingPrompts
                pendingPrompts.removeAll()
                for content in queued {
                    sendPrompt(sessionId: sessionId, content: content)
                }
            } else if resultObj["protocolVersion"] != nil {
                // Initialize completed — request a fresh session.
                sendNewSession()
            }
        }
    }

    private func handleStderr(_ data: Data) {
        stderr.append(data)
    }

    private func handleTermination(code: Int32) async {
        if code != 0 {
            let detail = stderr.text.isEmpty ? "" : "\n\(stderr.text)"
            try? await session.markError(message: "cursor-agent exited with code \(code)\(detail)")
        }
        process = nil
        stdinHandle = nil
    }
}

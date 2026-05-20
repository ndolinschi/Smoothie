import Foundation

/// Session lifecycle endpoints — list / create / message / abort /
/// kill / open-in-terminal — plus the SSE stream URL builder.
///
/// Extracted from APIClient.swift in P24.d D4.
extension APIClient {
    func sessions() async throws -> [SessionDescriptorWire] {
        let data = try await get("/sessions")
        return try decode([SessionDescriptorWire].self, from: data)
    }

    func createSession(_ req: CreateSessionRequestWire) async throws -> SessionDescriptorWire {
        let data = try await post("/sessions", json: req)
        return try decode(SessionDescriptorWire.self, from: data)
    }

    func sendMessage(sessionId: String, content: String) async throws {
        struct Body: Encodable { let content: String }
        _ = try await post("/sessions/\(sessionId)/message", json: Body(content: content))
    }

    /// Send a turn that may include image attachments. Images travel in the
    /// JSON envelope as `{mimeType, base64}` entries; the macOS server
    /// decodes them and ProcessHost (Claude only) wraps them in content
    /// blocks on the way to stream-json stdin. Other providers reject with
    /// HTTP 415.
    func sendMessage(sessionId: String, content: String, images: [StagedImage]) async throws {
        if images.isEmpty {
            try await sendMessage(sessionId: sessionId, content: content)
            return
        }
        struct ImagePayload: Encodable { let mimeType: String; let base64: String }
        struct Body: Encodable {
            let content: String
            let images: [ImagePayload]
        }
        let payload = Body(
            content: content,
            images: images.map { ImagePayload(mimeType: $0.mimeType, base64: $0.base64) }
        )
        _ = try await post("/sessions/\(sessionId)/message", json: payload)
    }

    @discardableResult
    func killSession(sessionId: String) async throws -> Bool {
        let data = try await delete("/sessions/\(sessionId)")
        struct R: Decodable { let terminated: Bool }
        return (try? decode(R.self, from: data).terminated) ?? false
    }

    /// Cancel the in-flight turn without killing the session. Per-CLI
    /// semantics: Claude → SIGINT (process keeps running); Gemini →
    /// terminate current one-shot spawn; OpenCode → opencode `/abort`.
    @discardableResult
    func abortSession(sessionId: String) async throws -> Bool {
        struct EmptyBody: Encodable {}
        let data = try await post("/sessions/\(sessionId)/abort", json: EmptyBody())
        struct R: Decodable { let aborted: Bool }
        return (try? decode(R.self, from: data).aborted) ?? false
    }

    /// Hand off the active session to the Mac's Terminal.app. Daemon
    /// kills its wrapped subprocess and runs osascript to open Terminal
    /// with the provider's resume command. Returns the exact command
    /// the daemon spawned (e.g. `claude --resume <id>`) so the iOS view
    /// can show it in the "Continued in Terminal" banner.
    @discardableResult
    func openTerminal(sessionId: String) async throws -> String {
        struct EmptyBody: Encodable {}
        let data = try await post("/sessions/\(sessionId)/open-terminal", json: EmptyBody())
        struct R: Decodable {
            let openedInTerminal: Bool
            let command: String
        }
        let decoded = try decode(R.self, from: data)
        return decoded.command
    }

    func streamURL(sessionId: String) -> URL? {
        guard let p = store.current else { return nil }
        return p.baseURL.appendingPathComponent("sessions/\(sessionId)/stream")
    }
}

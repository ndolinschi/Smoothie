import Foundation

/// Bearer-auth-aware REST client. Pulls host+token from PairingStore at call
/// time so token rotations take effect on the next request.
@MainActor
struct APIClient {
    let store: PairingStore

    enum APIError: LocalizedError {
        case notPaired
        case http(Int, String)
        case transport(String)
        case decode(String)
        /// Daemon-side connection refused / host unreachable. Distinct
        /// from generic `transport` so the UI can render a more useful
        /// "Make sure Smoothie is running on your Mac" prompt instead
        /// of the URLSession default ("The Internet connection appears
        /// to be offline") which misleads users.
        case daemonUnreachable(host: String)

        var errorDescription: String? {
            switch self {
            case .notPaired:           return "Not paired with a server"
            case .http(let c, let m):  return "HTTP \(c): \(m)"
            case .transport(let m):    return m
            case .decode(let m):       return "Decode error: \(m)"
            case .daemonUnreachable(let host):
                return "Daemon on \(host) isn't responding. Make sure Smoothie is running on your Mac."
            }
        }
    }

    // MARK: - Generic helpers

    @discardableResult
    func get(_ path: String) async throws -> Data {
        try await request(method: "GET", path: path, body: nil)
    }

    @discardableResult
    func post(_ path: String, json: any Encodable) async throws -> Data {
        let body = try JSONEncoder().encode(AnyEncodable(json))
        return try await request(method: "POST", path: path, body: body)
    }

    @discardableResult
    func delete(_ path: String) async throws -> Data {
        try await request(method: "DELETE", path: path, body: nil)
    }

    private func request(method: String, path: String, body: Data?) async throws -> Data {
        guard let pairing = store.current else { throw APIError.notPaired }
        // appendingPathComponent percent-encodes `?` and `=`, which destroys
        // query strings. Build the URL as a string so `/projects/files?path=…&q=…`
        // round-trips intact.
        let separator = path.hasPrefix("/") ? "" : "/"
        guard let url = URL(string: "\(pairing.baseURL.absoluteString)\(separator)\(path)") else {
            throw APIError.transport("Bad URL for \(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(pairing.token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        req.timeoutInterval = 30
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
            return data
        } catch let err as APIError {
            throw err
        } catch {
            // Distinguish "daemon not running" from generic network
            // errors so the UI can render an actionable message.
            // `cannotConnectToHost` / `cannotFindHost` / `timedOut` /
            // `networkConnectionLost` are the common shapes when the
            // user has quit Smoothie on the Mac.
            let nsErr = error as NSError
            let daemonDown: Set<Int> = [
                NSURLErrorCannotConnectToHost,
                NSURLErrorCannotFindHost,
                NSURLErrorTimedOut,
                NSURLErrorNetworkConnectionLost,
            ]
            if nsErr.domain == NSURLErrorDomain, daemonDown.contains(nsErr.code) {
                throw APIError.daemonUnreachable(host: pairing.label)
            }
            throw APIError.transport(error.localizedDescription)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decode(error.localizedDescription)
        }
    }

    // MARK: - Typed endpoints

    func health() async throws -> Data { try await get("/health") }

    /// Greeting metadata for the dashboard home (username, full name,
    /// hostname). Pulled once on HomeView appear; cached client-side
    /// since the values don't change between launches.
    func me() async throws -> MeWire {
        let data = try await get("/me")
        return try decode(MeWire.self, from: data)
    }

    func adapters() async throws -> [AdapterInfoWire] {
        let data = try await get("/adapters")
        return try decode([AdapterInfoWire].self, from: data)
    }

    func projects() async throws -> [ProjectWire] {
        let data = try await get("/projects")
        return try decode([ProjectWire].self, from: data)
    }

    func browse(path: String? = nil) async throws -> BrowseResponseWire {
        let p: String
        if let path {
            p = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        } else {
            p = ""
        }
        let route = p.isEmpty ? "/browse" : "/browse?path=\(p)"
        let data = try await get(route)
        return try decode(BrowseResponseWire.self, from: data)
    }

    func projectFiles(path: String, query: String = "") async throws -> [FileEntryWire] {
        let p = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let data = try await get("/projects/files?path=\(p)&q=\(q)")
        return try decode([FileEntryWire].self, from: data)
    }

    func fileContent(path: String) async throws -> FileContentWire {
        let p = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path
        let data = try await get("/projects/file?path=\(p)")
        return try decode(FileContentWire.self, from: data)
    }

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

/// Type-erases any Encodable for the generic `post` helper.
private struct AnyEncodable: Encodable {
    let base: any Encodable
    init(_ base: any Encodable) { self.base = base }
    func encode(to encoder: any Encoder) throws { try base.encode(to: encoder) }
}

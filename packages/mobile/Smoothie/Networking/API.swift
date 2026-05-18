import Foundation

struct API: Sendable {
    let baseURL: URL

    init(baseURL: URL) { self.baseURL = baseURL }

    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.hasPrefix("http://"), !s.hasPrefix("https://") {
            s = "http://\(s)"
        }
        guard var components = URLComponents(string: s) else { return nil }
        if components.port == nil {
            components.port = 7749
        }
        return components.url
    }

    enum APIError: Error, LocalizedError {
        case http(Int, String)
        case decode(String)
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .http(let code, let msg): return "HTTP \(code): \(msg)"
            case .decode(let msg):         return "Decode error: \(msg)"
            case .transport(let msg):      return msg
            }
        }
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw APIError.transport("Bad URL: \(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 30
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                throw APIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
            return data
        } catch let err as APIError {
            throw err
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    private func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        let data = try await request(path)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decode(error.localizedDescription)
        }
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B, as type: T.Type = T.self) async throws -> T {
        let payload = try JSONEncoder().encode(body)
        let data = try await request(path, method: "POST", body: payload)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decode(error.localizedDescription)
        }
    }

    // MARK: - Endpoints

    func health() async throws -> HealthResponse {
        try await get("/health")
    }

    func projects() async throws -> [ProjectDTO] {
        try await get("/projects")
    }

    func adapters() async throws -> [AdapterInfo] {
        try await get("/adapters")
    }

    func sessions() async throws -> [SessionDTO] {
        try await get("/sessions")
    }

    func createSession(projectPath: String, cli: CLIType) async throws -> SessionDTO {
        try await post("/sessions", body: CreateSessionRequest(projectPath: projectPath, cli: cli))
    }

    func sendMessage(sessionId: String, content: String) async throws {
        let payload = try JSONEncoder().encode(SendMessageRequest(content: content))
        _ = try await request("/sessions/\(sessionId)/message", method: "POST", body: payload)
    }

    @discardableResult
    func killSession(sessionId: String) async throws -> Bool {
        let data = try await request("/sessions/\(sessionId)", method: "DELETE")
        struct R: Decodable { let terminated: Bool }
        return (try? JSONDecoder().decode(R.self, from: data).terminated) ?? false
    }

    func streamURL(sessionId: String) -> URL? {
        URL(string: "/sessions/\(sessionId)/stream", relativeTo: baseURL)?.absoluteURL
    }
}

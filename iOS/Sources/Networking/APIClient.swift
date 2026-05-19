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

        var errorDescription: String? {
            switch self {
            case .notPaired:           return "Not paired with a server"
            case .http(let c, let m):  return "HTTP \(c): \(m)"
            case .transport(let m):    return m
            case .decode(let m):       return "Decode error: \(m)"
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
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var req = URLRequest(url: pairing.baseURL.appendingPathComponent(trimmed))
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

    func adapters() async throws -> [AdapterInfoWire] {
        let data = try await get("/adapters")
        return try decode([AdapterInfoWire].self, from: data)
    }

    func projects() async throws -> [ProjectWire] {
        let data = try await get("/projects")
        return try decode([ProjectWire].self, from: data)
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

    @discardableResult
    func killSession(sessionId: String) async throws -> Bool {
        let data = try await delete("/sessions/\(sessionId)")
        struct R: Decodable { let terminated: Bool }
        return (try? decode(R.self, from: data).terminated) ?? false
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

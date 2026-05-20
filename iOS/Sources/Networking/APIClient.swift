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
    //
    // Helpers are `internal` (default) so per-domain extension files
    // (APIClient+Sessions, APIClient+Projects, APIClient+Pairing) can
    // call them. Each extension only sees the typed endpoint surface
    // for its domain; transport + decode live here.

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

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decode(error.localizedDescription)
        }
    }
}

/// Type-erases any Encodable for the generic `post` helper. Lives in
/// this file rather than its own so existing call sites don't need
/// import gymnastics.
struct AnyEncodable: Encodable {
    let base: any Encodable
    init(_ base: any Encodable) { self.base = base }
    func encode(to encoder: any Encoder) throws { try base.encode(to: encoder) }
}

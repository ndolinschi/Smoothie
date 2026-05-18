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

        var errorDescription: String? {
            switch self {
            case .notPaired:           return "Not paired with a server"
            case .http(let c, let m):  return "HTTP \(c): \(m)"
            case .transport(let m):    return m
            }
        }
    }

    func get(_ path: String) async throws -> Data {
        guard let pairing = store.current else { throw APIError.notPaired }
        var req = URLRequest(url: pairing.baseURL.appendingPathComponent(path.trimmingPrefix("/")))
        req.httpMethod = "GET"
        req.setValue("Bearer \(pairing.token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
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
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}

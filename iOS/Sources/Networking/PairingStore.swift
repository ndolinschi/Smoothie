import Foundation
import Observation
import Shared

/// Holds the host+token a user paired with. Persists across launches via Keychain.
/// `Pairing` is the materialised triple the rest of the app consumes; `nil`
/// means the user hasn't paired yet and should see ConnectView.
@MainActor
@Observable
final class PairingStore {
    struct Pairing: Equatable {
        var host: String
        var port: Int
        var token: String
        var baseURL: URL { URL(string: "http://\(host):\(port)")! }
    }

    private(set) var current: Pairing?
    private(set) var lastError: String?

    private let accountHost = "pairing-host"
    private let accountPort = "pairing-port"
    private let accountToken = "pairing-token"

    init() {
        if let host = Keychain.read(accountHost).flatMap({ String(data: $0, encoding: .utf8) }),
           let portData = Keychain.read(accountPort).flatMap({ String(data: $0, encoding: .utf8) }),
           let port = Int(portData),
           let token = Keychain.read(accountToken).flatMap({ String(data: $0, encoding: .utf8) }),
           !host.isEmpty, !token.isEmpty {
            current = Pairing(host: host, port: port, token: token)
        }
    }

    /// Save a pairing parsed from QR or entered manually.
    func save(host: String, port: Int, token: String) {
        Keychain.write(accountHost, Data(host.utf8))
        Keychain.write(accountPort, Data(String(port).utf8))
        Keychain.write(accountToken, Data(token.utf8))
        current = Pairing(host: host, port: port, token: token)
        lastError = nil
    }

    /// Forget pairing — back to Connect screen.
    func clear() {
        Keychain.delete(accountHost)
        Keychain.delete(accountPort)
        Keychain.delete(accountToken)
        current = nil
        lastError = nil
    }

    /// Parse a `smoothie://pair?...` URL via the shared Kotlin parser.
    func saveFromURL(_ url: String) -> Bool {
        guard let payload = QRPayload.companion.parse(url: url) else {
            lastError = "QR is not a Smoothie pairing code"
            return false
        }
        save(host: payload.host, port: Int(payload.port), token: payload.token)
        return true
    }

    /// Quick `/health` probe to confirm the server is reachable and reply matches.
    @discardableResult
    func verify() async -> Bool {
        guard let pairing = current else { return false }
        var req = URLRequest(url: pairing.baseURL.appendingPathComponent("health"))
        req.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                lastError = nil
                return true
            }
            lastError = "Server returned non-200"
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}

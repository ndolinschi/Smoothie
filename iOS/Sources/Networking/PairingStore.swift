import Foundation
import CryptoKit
import Observation
import Shared

/// Holds every Mac the user has paired with, plus the currently-active
/// selection. Persisted across launches via Keychain: the full pairing list
/// is stored as a single JSON blob, the active id as its own entry. Earlier
/// single-pair installs are migrated on first launch.
///
/// `current` (the single triple the rest of the app consumes) is derived
/// from `pairings` + `activeId`, so APIClient and the routing logic continue
/// to work unchanged.
@MainActor
@Observable
final class PairingStore {
    struct Pairing: Codable, Identifiable, Equatable, Hashable {
        let id: String
        var label: String
        var host: String
        var port: Int
        var token: String

        var baseURL: URL { URL(string: "http://\(host):\(port)")! }

        init(label: String, host: String, port: Int, token: String) {
            self.id = Self.makeId(host: host, port: port)
            self.label = label
            self.host = host
            self.port = port
            self.token = token
        }

        static func makeId(host: String, port: Int) -> String {
            let digest = SHA256.hash(data: Data("\(host):\(port)".utf8))
            return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        }
    }

    private(set) var pairings: [Pairing] = []
    private(set) var activeId: String?
    private(set) var lastError: String?

    /// Derived single-pair view. APIClient + routing consume this.
    var current: Pairing? {
        guard let activeId else { return nil }
        return pairings.first { $0.id == activeId }
    }

    private let accountList = "pairing-list-v2"
    private let accountActive = "pairing-active-v2"

    // Legacy single-pair keys retained for migration only.
    private let legacyHost = "pairing-host"
    private let legacyPort = "pairing-port"
    private let legacyToken = "pairing-token"

    init() {
        load()
        migrateLegacyIfNeeded()
    }

    // MARK: - Public API

    /// Save a pairing parsed from QR or entered manually. If this Mac is
    /// already in the list (matched by host:port) the entry is updated in
    /// place; either way the new id becomes active.
    func save(host: String, port: Int, token: String, label: String? = nil) {
        let derivedLabel = label ?? defaultLabel(host: host)
        let pairing = Pairing(label: derivedLabel, host: host, port: port, token: token)
        if let i = pairings.firstIndex(where: { $0.id == pairing.id }) {
            // Preserve user-edited label if present.
            var existing = pairings[i]
            existing.host = pairing.host
            existing.port = pairing.port
            existing.token = pairing.token
            if label != nil { existing.label = derivedLabel }
            pairings[i] = existing
        } else {
            pairings.append(pairing)
        }
        activeId = pairing.id
        lastError = nil
        persist()
    }

    /// Remove a pairing. If the removed entry was active, the most recently
    /// added remaining pairing becomes active (or `nil` if none left).
    func remove(id: String) {
        pairings.removeAll { $0.id == id }
        if activeId == id {
            activeId = pairings.last?.id
        }
        persist()
    }

    /// Switch the active Mac without touching the list.
    func switchTo(id: String) {
        guard pairings.contains(where: { $0.id == id }) else { return }
        activeId = id
        persist()
    }

    /// Rename a pairing (manual override of the default host-based label).
    func rename(id: String, to label: String) {
        guard let i = pairings.firstIndex(where: { $0.id == id }) else { return }
        pairings[i].label = label
        persist()
    }

    /// Wipe everything — back to ConnectView.
    func clear() {
        pairings.removeAll()
        activeId = nil
        lastError = nil
        Keychain.delete(accountList)
        Keychain.delete(accountActive)
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

    /// Parse + save-with-rollback variant used by the QR scanner so a
    /// successfully-decoded but unreachable Mac doesn't pollute the list.
    @discardableResult
    func tryPairFromURL(_ url: String) async -> Bool {
        guard let payload = QRPayload.companion.parse(url: url) else {
            lastError = "QR is not a Smoothie pairing code"
            return false
        }
        return await tryPair(host: payload.host, port: Int(payload.port), token: payload.token)
    }

    /// Atomic "save + verify, roll back on failure" helper. Used by
    /// ConnectView and ManualPairView so a failed pair attempt never leaves
    /// a dead entry in the list.
    @discardableResult
    func tryPair(host: String, port: Int, token: String, label: String? = nil) async -> Bool {
        let id = Pairing.makeId(host: host, port: port)
        let alreadyExisted = pairings.contains { $0.id == id }
        let priorActive = activeId
        save(host: host, port: port, token: token, label: label)
        let ok = await verify()
        if !ok {
            if alreadyExisted {
                if let priorActive { switchTo(id: priorActive) }
            } else {
                remove(id: id)
            }
            return false
        }
        return true
    }

    /// Quick `/health` probe against the active pairing.
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

    // MARK: - Persistence

    private func load() {
        if let data = Keychain.read(accountList),
           let list = try? JSONDecoder().decode([Pairing].self, from: data) {
            pairings = list
        }
        if let data = Keychain.read(accountActive),
           let id = String(data: data, encoding: .utf8),
           pairings.contains(where: { $0.id == id }) {
            activeId = id
        } else {
            activeId = pairings.first?.id
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(pairings) {
            Keychain.write(accountList, data)
        }
        if let activeId {
            Keychain.write(accountActive, Data(activeId.utf8))
        } else {
            Keychain.delete(accountActive)
        }
    }

    private func migrateLegacyIfNeeded() {
        // Skip if we already have a list.
        if !pairings.isEmpty { return }
        guard
            let host = Keychain.read(legacyHost).flatMap({ String(data: $0, encoding: .utf8) }),
            let portStr = Keychain.read(legacyPort).flatMap({ String(data: $0, encoding: .utf8) }),
            let port = Int(portStr),
            let token = Keychain.read(legacyToken).flatMap({ String(data: $0, encoding: .utf8) }),
            !host.isEmpty, !token.isEmpty
        else { return }
        save(host: host, port: port, token: token)
        Keychain.delete(legacyHost)
        Keychain.delete(legacyPort)
        Keychain.delete(legacyToken)
    }

    private func defaultLabel(host: String) -> String {
        // Strip ".tail-net" / ".local" suffixes to get a friendlier short name.
        let trimmed = host
            .replacingOccurrences(of: ".tail-net", with: "")
            .replacingOccurrences(of: ".local", with: "")
        if trimmed.isEmpty { return host }
        return trimmed.capitalized
    }
}

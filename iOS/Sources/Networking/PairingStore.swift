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
        /// `http` for LAN / Tailscale, `https` for Cloudflare tunnel pairings.
        /// Optional in the wire payload — older QRs without `scheme=` parse
        /// as `http`.
        var scheme: String

        var baseURL: URL {
            // Build via URLComponents so a malformed `host` (whitespace,
            // unicode, IPv6 bracket mismatch) can't crash the app via
            // force-unwrap. The previous `URL(string: ...)!` form was a
            // real reachable crash path — APIClient calls `baseURL` on
            // every request and a single bad pairing blob would tear
            // the process down. If construction does fail, fall back to
            // an obviously-invalid host so the next request raises a
            // transport error the connection banner can surface, rather
            // than killing the app.
            var components = URLComponents()
            components.scheme = scheme
            components.host = host
            // For `https` tunnels (Cloudflare), drop the explicit port if
            // it's the default 443 so URLSession picks the right port and
            // SNI hostname without surprises.
            if !(scheme == "https" && (port == 443 || port == 0)) {
                components.port = port
            }
            return components.url
                ?? URL(string: "http://smoothie-invalid-host.local")!
        }

        init(label: String, host: String, port: Int, token: String, scheme: String = "http") {
            self.id = Self.makeId(host: host, port: port, scheme: scheme)
            self.label = label
            self.host = host
            self.port = port
            self.token = token
            self.scheme = scheme
        }

        // Backwards-compatible decoder so older Keychain blobs without a
        // `scheme` field still load (they default to "http").
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id     = try c.decode(String.self, forKey: .id)
            self.label  = try c.decode(String.self, forKey: .label)
            self.host   = try c.decode(String.self, forKey: .host)
            self.port   = try c.decode(Int.self,    forKey: .port)
            self.token  = try c.decode(String.self, forKey: .token)
            self.scheme = (try? c.decode(String.self, forKey: .scheme)) ?? "http"
        }

        static func makeId(host: String, port: Int, scheme: String = "http") -> String {
            let digest = SHA256.hash(data: Data("\(scheme)://\(host):\(port)".utf8))
            return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        }
    }

    private(set) var pairings: [Pairing] = []
    private(set) var activeId: String?
    private(set) var lastError: String?
    /// Daemon version reported by the last successful `/health` probe of
    /// the active pairing. `nil` until the first probe lands. Surfaced in
    /// Settings and used by `compatibilityWarning` to flag a major-version
    /// skew between this app and the Mac daemon (wire-protocol drift).
    private(set) var daemonVersion: String?

    /// Non-blocking warning when the daemon's major version differs from
    /// the app's, which is where wire-format incompatibilities live. Nil
    /// when versions match, are missing, or differ only in minor/patch.
    var compatibilityWarning: String? {
        guard let daemon = daemonVersion,
              let app = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        else { return nil }
        let daemonMajor = daemon.split(separator: ".").first.map(String.init)
        let appMajor = app.split(separator: ".").first.map(String.init)
        guard let dm = daemonMajor, let am = appMajor, dm != am else { return nil }
        return "This app is v\(app) but the Mac daemon is v\(daemon). Update whichever is older — across a major version the two can speak different protocols and sessions may behave oddly."
    }

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
    func save(host: String, port: Int, token: String, scheme: String = "http", label: String? = nil) {
        let derivedLabel = label ?? defaultLabel(host: host)
        let pairing = Pairing(label: derivedLabel, host: host, port: port, token: token, scheme: scheme)
        if let i = pairings.firstIndex(where: { $0.id == pairing.id }) {
            // Preserve user-edited label if present.
            var existing = pairings[i]
            existing.host = pairing.host
            existing.port = pairing.port
            existing.token = pairing.token
            existing.scheme = pairing.scheme
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
        save(host: payload.host, port: Int(payload.port), token: payload.token, scheme: payload.scheme)
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
        return await tryPair(host: payload.host, port: Int(payload.port), token: payload.token, scheme: payload.scheme)
    }

    /// Atomic "save + verify, roll back on failure" helper. Used by
    /// ConnectView and ManualPairView so a failed pair attempt never leaves
    /// a dead entry in the list.
    @discardableResult
    func tryPair(host: String, port: Int, token: String, scheme: String = "http", label: String? = nil) async -> Bool {
        let id = Pairing.makeId(host: host, port: port, scheme: scheme)
        let alreadyExisted = pairings.contains { $0.id == id }
        let priorActive = activeId
        save(host: host, port: port, token: token, scheme: scheme, label: label)
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
        // HTTPS = Cloudflare tunnel: allow 30 s for cold-start (first request
        // through a new trycloudflare.com tunnel takes 15-25 s in practice).
        // HTTP = LAN/Tailscale: 12 s is plenty; failing fast is better UX.
        req.timeoutInterval = pairing.scheme == "https" ? 30 : 12
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                lastError = nil
                // Capture the daemon version so Settings can show it and
                // compatibilityWarning can flag a major-version skew.
                if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let v = obj["version"] as? String {
                    daemonVersion = v
                }
                return true
            }
            lastError = "Server returned non-200"
            return false
        } catch let urlErr as URLError {
            lastError = friendlyURLError(urlErr, pairing: pairing)
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Translates URLError codes into messages that tell the user what to do
    /// rather than quoting the raw system error string. Uses the actual
    /// baseURL so the address shown always matches what was tried.
    private func friendlyURLError(_ err: URLError, pairing: Pairing) -> String {
        // Show the exact URL that was probed, not a hand-assembled string.
        // This catches cases where the pairing was stored with a bad host
        // (e.g. "https://xxx.trycloudflare.com" as the host field, which
        // URLComponents folds into http://smoothie-invalid-host.local).
        let addr = pairing.baseURL.absoluteString
        let isRemote = pairing.scheme == "https"
        switch err.code {
        case .timedOut:
            if isRemote {
                return "Timed out reaching \(addr) — the Cloudflare tunnel may still be warming up. Tap Retry."
            }
            return "Timed out reaching \(addr). Make sure your phone and Mac are on the same network, or switch to Remote (Cloudflare) mode on the Mac."
        case .cannotConnectToHost:
            return "Connection refused at \(addr). Is the Smoothie daemon running on your Mac?"
        case .notConnectedToInternet, .networkConnectionLost:
            return "No network connection. Check your phone's WiFi or cellular."
        case .cannotFindHost, .dnsLookupFailed:
            if isRemote {
                return "Could not reach \(addr). The Cloudflare tunnel URL may have expired — re-scan the QR."
            }
            return "Could not find \(addr). Check the host address or switch to Remote mode."
        default:
            return "\(addr) — \(err.localizedDescription)"
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

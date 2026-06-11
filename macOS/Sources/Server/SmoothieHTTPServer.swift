import Foundation
import Hummingbird
import NIOCore
import Observation
import Shared

/// Bearer-guarded HTTP server. /health is public; everything else lives behind
/// the BearerAuthMiddleware. Routes are mounted via the Routes module.
@MainActor
@Observable
final class SmoothieHTTPServer {
    enum Status: Equatable {
        case stopped
        case starting
        case running(host: String, port: Int)
        case failed(String)
    }

    private(set) var status: Status = .stopped
    private(set) var startedAt: Date?
    private var serverTask: Task<Void, Never>?

    let pairing: PairingService
    let manager: SessionManager
    let registry: AdapterRegistry
    let processes: ProcessRegistry
    let prefs: Preferences

    init(
        pairing: PairingService,
        manager: SessionManager,
        registry: AdapterRegistry,
        processes: ProcessRegistry,
        prefs: Preferences
    ) {
        self.pairing = pairing
        self.manager = manager
        self.registry = registry
        self.processes = processes
        self.prefs = prefs
    }

    func start() {
        guard serverTask == nil else { return }
        let token = pairing.token
        let host = pairing.host
        let port = pairing.port
        let manager = self.manager
        let registry = self.registry
        let processes = self.processes
        let prefs = self.prefs

        let router = Self.buildRouter(
            token: token,
            manager: manager,
            registry: registry,
            processes: processes,
            prefs: prefs
        )

        // Always bind to all interfaces so the phone can reach the daemon
        // over LAN or Tailscale regardless of which address `pairing.host`
        // resolved to. `pairing.host` is used only for the QR code display.
        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname("0.0.0.0", port: port),
                serverName: "Smoothie"
            )
        )
        status = .starting

        serverTask = Task { [weak self] in
            do {
                await MainActor.run {
                    self?.status = .running(host: host, port: port)
                    self?.startedAt = Date()
                }
                try await app.runService()
                await MainActor.run { self?.status = .stopped }
            } catch is CancellationError {
                await MainActor.run { self?.status = .stopped }
            } catch {
                let msg = error.localizedDescription
                await MainActor.run { self?.status = .failed(msg) }
            }
        }
    }

    func stop() {
        serverTask?.cancel()
        serverTask = nil
        status = .stopped
    }

    func restart() {
        stop()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            self.start()
        }
    }

    private static func buildRouter(
        token: String,
        manager: SessionManager,
        registry: AdapterRegistry,
        processes: ProcessRegistry,
        prefs: Preferences
    ) -> Router<BasicRequestContext> {
        let router = Router(context: BasicRequestContext.self)

        // /health is intentionally public so the iOS app can probe before
        // submitting the Bearer header. Version comes from the bundle so
        // project.yml stays the single source of truth.
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0"
        router.get("/health") { _, _ -> Response in
            jsonResponse("{\"healthy\":true,\"version\":\(jsonString(version))}")
        }

        let group = router.group()
            .add(middleware: BearerAuthMiddleware(token: token))

        Routes.mount(group, manager: manager, registry: registry, processes: processes, prefs: prefs)

        return router
    }
}

struct BearerAuthMiddleware<Context: RequestContext>: RouterMiddleware {
    let token: String
    /// Shared across all requests for the lifetime of the router so the
    /// failure window survives between connections.
    let failureGate = AuthFailureGate()

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        let header = request.headers[.authorization]
        guard let header, Self.constantTimeEqual(header, "Bearer \(token)") else {
            // Throttle brute-force guessing: after a burst of bad tokens,
            // answer 429 instead of 401 until the window cools down.
            // Valid tokens are never affected — only failures count.
            if failureGate.registerFailureAndCheckBlocked() {
                return errorResponse(.tooManyRequests, "too many failed auth attempts — try again later")
            }
            return errorResponse(.unauthorized, "unauthorized")
        }
        return try await next(request, context)
    }

    /// Sliding-window counter of failed bearer attempts. Lock-guarded
    /// because Hummingbird handlers run concurrently across connections.
    /// 10 failures within 60 s flips subsequent failures to 429 until
    /// the window drains — slow enough to make brute-forcing the
    /// 32-byte token impractical even on a hostile LAN, loose enough
    /// that a phone with a stale token just sees a few 401s.
    final class AuthFailureGate: @unchecked Sendable {
        private let lock = NSLock()
        private var failures: [Date] = []
        private let window: TimeInterval = 60
        private let maxFailures = 10

        func registerFailureAndCheckBlocked() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let now = Date()
            failures.removeAll { now.timeIntervalSince($0) >= window }
            failures.append(now)
            return failures.count > maxFailures
        }
    }

    /// Constant-time byte comparison. The naive `==` on `String` short-
    /// circuits on the first mismatching byte, which leaks the prefix
    /// length of the correct token to a network observer measuring
    /// response timing. On Tailscale we trust the peer link, but the
    /// pairing token is the single source of authority on the daemon —
    /// a tampered Tailscale node or a localhost-bound malicious app
    /// shouldn't be able to brute-force the bearer one byte at a time.
    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let lhs = Array(a.utf8)
        let rhs = Array(b.utf8)
        // Always walk `max(lhs.count, rhs.count)` so a length mismatch
        // doesn't itself become a timing oracle.
        let length = max(lhs.count, rhs.count)
        var diff: UInt8 = lhs.count == rhs.count ? 0 : 1
        for i in 0..<length {
            let l: UInt8 = i < lhs.count ? lhs[i] : 0
            let r: UInt8 = i < rhs.count ? rhs[i] : 0
            diff |= (l ^ r)
        }
        return diff == 0
    }
}

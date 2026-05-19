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

        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname(host, port: port),
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
        // submitting the Bearer header.
        router.get("/health") { _, _ -> Response in
            jsonResponse("{\"healthy\":true,\"version\":\"0.2.0\"}")
        }

        let group = router.group()
            .add(middleware: BearerAuthMiddleware(token: token))

        Routes.mount(group, manager: manager, registry: registry, processes: processes, prefs: prefs)

        return router
    }
}

struct BearerAuthMiddleware<Context: RequestContext>: RouterMiddleware {
    let token: String

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        let header = request.headers[.authorization]
        guard let header, header == "Bearer \(token)" else {
            return errorResponse(.unauthorized, "unauthorized")
        }
        return try await next(request, context)
    }
}

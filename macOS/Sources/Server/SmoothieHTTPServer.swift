import Foundation
import Hummingbird
import NIOCore
import Observation
import Shared

/// Minimal v2 HTTP surface: `/health` (public) and `/whoami` (bearer-guarded
/// sanity ping). Sessions/SSE/projects/browse routes land in P4/P5/P7 as the
/// shared K/N session machinery is wired in.
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
    let registry = AdapterRegistry()

    init(pairing: PairingService) {
        self.pairing = pairing
    }

    func start() {
        guard serverTask == nil else { return }
        let token = pairing.token
        let host = pairing.host
        let port = pairing.port

        let router = Self.buildRouter(token: token)
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

    private static func buildRouter(token: String) -> Router<BasicRequestContext> {
        let router = Router(context: BasicRequestContext.self)

        // /health is intentionally public — used by the iOS app to verify the
        // server is alive before submitting the auth header.
        router.get("/health") { _, _ -> Response in
            jsonResponse("{\"healthy\":true,\"version\":\"0.2.0\"}")
        }

        // Everything else requires Bearer.
        router.group()
            .add(middleware: BearerAuthMiddleware(token: token))
            .get("/whoami") { _, _ -> Response in
                jsonResponse("{\"paired\":true}")
            }

        return router
    }
}

private func jsonResponse(_ body: String, status: HTTPResponse.Status = .ok) -> Response {
    var buf = ByteBuffer()
    buf.writeBytes(Array(body.utf8))
    return Response(
        status: status,
        headers: [.contentType: "application/json"],
        body: ResponseBody(byteBuffer: buf)
    )
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
            return jsonResponse("{\"error\":\"unauthorized\"}", status: .unauthorized)
        }
        return try await next(request, context)
    }
}

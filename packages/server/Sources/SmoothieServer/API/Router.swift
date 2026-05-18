import Foundation
import Hummingbird
import NIOCore

/// Builds the Hummingbird router. Captures dependencies via closures rather than
/// custom request contexts to keep things explicit.
enum APIRouter {
    static func build(
        config: Config,
        registry: AdapterRegistry,
        manager: SessionManager,
        startedAt: Date
    ) -> Router<BasicRequestContext> {
        let router = Router(context: BasicRequestContext.self)

        router.get("/health") { _, _ -> Response in
            let info = await registry.info
            let body = HealthResponse(
                version: config.version,
                uptime: Date().timeIntervalSince(startedAt),
                bindAddress: "\(config.bindAddress):\(config.port)",
                adapters: info
            )
            return try jsonResponse(body)
        }

        router.get("/projects") { _, _ -> Response in
            let projects = listProjects(under: config.allowedRoots)
            return try jsonResponse(projects)
        }

        router.get("/adapters") { _, _ -> Response in
            let info = await registry.info
            return try jsonResponse(info)
        }

        router.post("/sessions") { request, _ -> Response in
            let body = try await readBody(request, max: 64 * 1024)
            let req = try JSONDecoder().decode(CreateSessionRequest.self, from: body)
            guard config.isPathAllowed(req.projectPath) else {
                return errorResponse(status: .forbidden, message: "Path not allowed: \(req.projectPath)")
            }
            let systemPrompt = loadSystemPrompt(promptsDir: config.promptsDir, cli: req.cli)
            do {
                let session = try await manager.create(
                    projectPath: req.projectPath,
                    cli: req.cli,
                    systemPromptText: systemPrompt
                )
                return try jsonResponse(await session.snapshot())
            } catch let err as AdapterError {
                return errorResponse(status: .badRequest, message: err.description)
            } catch {
                return errorResponse(status: .internalServerError, message: "\(error)")
            }
        }

        router.get("/sessions") { _, _ -> Response in
            let list = await manager.list()
            return try jsonResponse(list)
        }

        router.get("/sessions/:id/stream") { request, context -> Response in
            guard let idStr = context.parameters.get("id"), let id = UUID(uuidString: idStr) else {
                return errorResponse(status: .badRequest, message: "Invalid session id")
            }
            guard let session = await manager.get(id) else {
                return errorResponse(status: .notFound, message: "Session not found")
            }
            let events = await session.subscribe()

            let asyncBytes = AsyncStream<ByteBuffer> { continuation in
                let task = Task {
                    // Initial comment frame helps some clients (curl) start parsing.
                    continuation.yield(ByteBuffer(bytes: Array(": connected\n\n".utf8)))
                    for await event in events {
                        let frame = SSEFormatter.frame(event)
                        continuation.yield(ByteBuffer(bytes: Array(frame)))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }

            return Response(
                status: .ok,
                headers: [
                    .contentType: "text/event-stream",
                    .cacheControl: "no-cache",
                    .connection: "keep-alive"
                ],
                body: ResponseBody(asyncSequence: asyncBytes)
            )
        }

        router.post("/sessions/:id/message") { request, context -> Response in
            guard let idStr = context.parameters.get("id"), let id = UUID(uuidString: idStr) else {
                return errorResponse(status: .badRequest, message: "Invalid session id")
            }
            guard let session = await manager.get(id) else {
                return errorResponse(status: .notFound, message: "Session not found")
            }
            let body = try await readBody(request, max: 1024 * 1024)
            let req = try JSONDecoder().decode(SendMessageRequest.self, from: body)
            do {
                try await session.send(req.content)
            } catch let err as AdapterError {
                return errorResponse(status: .badRequest, message: err.description)
            }
            return try jsonResponse(["status": "ok"])
        }

        router.delete("/sessions/:id") { _, context -> Response in
            guard let idStr = context.parameters.get("id"), let id = UUID(uuidString: idStr) else {
                return errorResponse(status: .badRequest, message: "Invalid session id")
            }
            let ok = await manager.terminate(id)
            return try jsonResponse(["terminated": ok])
        }

        return router
    }

    // MARK: - Helpers

    private static func jsonResponse<T: Encodable>(_ value: T, status: HTTPResponse.Status = .ok) throws -> Response {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(value)
        var buf = ByteBuffer()
        buf.writeBytes(Array(data))
        return Response(
            status: status,
            headers: [.contentType: "application/json"],
            body: ResponseBody(byteBuffer: buf)
        )
    }

    private static func errorResponse(status: HTTPResponse.Status, message: String) -> Response {
        let body = "{\"error\":\"\(message.replacingOccurrences(of: "\"", with: "\\\""))\"}".data(using: .utf8) ?? Data()
        var buf = ByteBuffer()
        buf.writeBytes(Array(body))
        return Response(
            status: status,
            headers: [.contentType: "application/json"],
            body: ResponseBody(byteBuffer: buf)
        )
    }

    private static func readBody(_ request: Request, max: Int) async throws -> Data {
        let buffer = try await request.body.collect(upTo: max)
        return Data(buffer.readableBytesView)
    }

    private static func listProjects(under roots: [String]) -> [ProjectDTO] {
        let fm = FileManager.default
        var seen = Set<String>()
        var out: [ProjectDTO] = []
        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries {
                if entry.hasPrefix(".") { continue }
                let fullPath = (root as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else { continue }
                if seen.contains(fullPath) { continue }
                seen.insert(fullPath)
                let isGit = fm.fileExists(atPath: (fullPath as NSString).appendingPathComponent(".git"))
                out.append(ProjectDTO(name: entry, path: fullPath, isGit: isGit))
            }
        }
        return out.sorted { ($0.isGit ? 0 : 1, $0.name.lowercased()) < ($1.isGit ? 0 : 1, $1.name.lowercased()) }
    }

    private static func loadSystemPrompt(promptsDir: String?, cli: CLIType) -> String? {
        guard let dir = promptsDir else { return nil }
        let folder: String
        switch cli {
        case .opencode: folder = "opencode"
        case .claude:   folder = "claude-code"
        case .gemini:   folder = "gemini"
        case .codex:    folder = "codex"
        }
        let path = (dir as NSString).appendingPathComponent("\(folder)/system.md")
        return try? String(contentsOfFile: path, encoding: .utf8)
    }
}

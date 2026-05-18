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

        router.get("/projects/files") { request, _ -> Response in
            let query = parseQuery(request.uri.query)
            guard let path = query["path"], config.isPathAllowed(path) else {
                return errorResponse(status: .forbidden, message: "Path not allowed")
            }
            let q = query["q"] ?? ""
            let files = listFiles(under: path, query: q)
            return try jsonResponse(files)
        }

        router.get("/projects/file") { request, _ -> Response in
            let query = parseQuery(request.uri.query)
            guard let path = query["path"], config.isPathAllowed(path) else {
                return errorResponse(status: .forbidden, message: "Path not allowed")
            }
            guard let content = readFile(at: path) else {
                return errorResponse(status: .notFound, message: "File not found or not readable")
            }
            return try jsonResponse(content)
        }

        router.get("/browse") { request, _ -> Response in
            let query = parseQuery(request.uri.query)
            let response = browse(path: query["path"], config: config)
            return try jsonResponse(response)
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

    private static func parseQuery(_ raw: String?) -> [String: String] {
        guard let raw, !raw.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for pair in raw.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            let rawValue = String(parts[1])
            let value = rawValue.removingPercentEncoding ?? rawValue
            result[key] = value
        }
        return result
    }

    private static let fileListExcludes: Set<String> = [
        ".git", ".build", ".swiftpm", "node_modules", "DerivedData",
        ".expo", ".next", ".cache", "dist", "build", ".turbo",
        ".DS_Store", "Pods", ".gradle"
    ]

    private static let fileListMaxResults = 1000
    private static let fileMaxBytes = 100 * 1024

    private static func listFiles(under root: String, query: String) -> [FileEntry] {
        let fm = FileManager.default
        let q = query.lowercased()
        let rootURL = URL(fileURLWithPath: root)
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [FileEntry] = []
        let rootPrefix = root.hasSuffix("/") ? root : root + "/"

        for case let url as URL in enumerator {
            if results.count >= fileListMaxResults { break }
            let name = url.lastPathComponent
            if fileListExcludes.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true { continue }
            let abs = url.path
            let relative = abs.hasPrefix(rootPrefix) ? String(abs.dropFirst(rootPrefix.count)) : abs
            if !q.isEmpty, !relative.lowercased().contains(q) { continue }
            results.append(FileEntry(path: relative, fullPath: abs, size: values?.fileSize ?? 0))
        }
        return results.sorted { $0.path.lowercased() < $1.path.lowercased() }
    }

    private static let browseExcludes: Set<String> = [
        ".Trash", ".cache", "Library", ".npm", ".yarn", ".pnpm", ".bun"
    ]

    private static func browse(path: String?, config: Config) -> BrowseResponse {
        let roots = config.allowedRoots
        if let path, !path.isEmpty {
            guard config.isPathAllowed(path) else {
                return BrowseResponse(current: nil, parent: nil, entries: rootEntries(roots), roots: roots)
            }
            let parentPath = (path as NSString).deletingLastPathComponent
            let parent: String? = {
                if parentPath == path { return nil }
                return config.isPathAllowed(parentPath) ? parentPath : nil
            }()
            return BrowseResponse(
                current: path,
                parent: parent,
                entries: listSubdirs(at: path, config: config),
                roots: roots
            )
        }
        return BrowseResponse(current: nil, parent: nil, entries: rootEntries(roots), roots: roots)
    }

    private static func rootEntries(_ roots: [String]) -> [BrowseEntry] {
        let fm = FileManager.default
        return roots.compactMap { root in
            guard fm.fileExists(atPath: root) else { return nil }
            let name = (root as NSString).lastPathComponent
            let isGit = fm.fileExists(atPath: (root as NSString).appendingPathComponent(".git"))
            return BrowseEntry(name: name, path: root, isDirectory: true, isGit: isGit, isAllowed: true)
        }
    }

    private static func listSubdirs(at path: String, config: Config) -> [BrowseEntry] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        var entries: [BrowseEntry] = []
        for name in contents {
            if name.hasPrefix(".") && name != ".git" { continue }
            if browseExcludes.contains(name) { continue }
            if fileListExcludes.contains(name) { continue }
            let full = (path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue else { continue }
            let isGit = fm.fileExists(atPath: (full as NSString).appendingPathComponent(".git"))
            let isAllowed = config.isPathAllowed(full)
            entries.append(BrowseEntry(name: name, path: full, isDirectory: true, isGit: isGit, isAllowed: isAllowed))
        }
        return entries.sorted { a, b in
            if a.isGit != b.isGit { return a.isGit }
            return a.name.lowercased() < b.name.lowercased()
        }
    }

    private static func readFile(at path: String) -> FileContent? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return nil }
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        let attrs = try? fm.attributesOfItem(atPath: path)
        let actualSize = (attrs?[.size] as? Int) ?? 0
        let data = (try? handle.read(upToCount: fileMaxBytes + 1)) ?? Data()
        let truncated = data.count > fileMaxBytes
        let trimmed = truncated ? data.prefix(fileMaxBytes) : data
        guard let text = String(data: trimmed, encoding: .utf8) else { return nil }
        return FileContent(path: path, content: text, size: trimmed.count.advanced(by: 0), truncated: truncated || actualSize > fileMaxBytes)
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

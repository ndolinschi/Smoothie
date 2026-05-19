import Foundation
import Hummingbird
import NIOCore
import Shared

/// Builds the Bearer-guarded route group. Kotlin types ship from K/N without
/// `Sendable` conformance, and `ProcessRegistry` / `Preferences` are
/// `@MainActor`, so route handlers explicitly hop to MainActor for any work
/// that touches those.
enum Routes {
    /// Sendable container for the per-app services the route group needs.
    /// All members are either thread-safe Kotlin objects (internally
    /// mutex-protected) or MainActor-isolated Swift objects only accessed
    /// inside `Task { @MainActor in ... }` blocks below.
    struct Handle: @unchecked Sendable {
        let manager: SessionManager
        let registry: AdapterRegistry
        let processes: ProcessRegistry
        let prefs: Preferences
    }

    @MainActor
    static func mount(
        _ group: RouterGroup<BasicRequestContext>,
        manager: SessionManager,
        registry: AdapterRegistry,
        processes: ProcessRegistry,
        prefs: Preferences
    ) {
        let handle = Handle(manager: manager, registry: registry, processes: processes, prefs: prefs)

        group.get("/whoami") { _, _ in
            jsonResponse("{\"paired\":true}")
        }

        group.get("/adapters") { _, _ -> Response in
            let infos = handle.registry.all()
            return jsonResponse(encodeAdapterList(infos))
        }

        // MARK: Projects

        group.get("/projects") { _, _ -> Response in
            let json = await Task { @MainActor in
                let projects = listTopLevelProjects(allowedRoots: handle.prefs.allowedRoots)
                return encodeProjectList(projects)
            }.value
            return jsonResponse(json)
        }

        group.get("/browse") { request, _ -> Response in
            let query = parseQuery(request.uri.query)
            let json = await Task { @MainActor in
                let path = query["path"]
                let response = browseFolder(path: path, prefs: handle.prefs)
                return encodeBrowseResponse(response)
            }.value
            return jsonResponse(json)
        }

        group.get("/projects/files") { request, _ -> Response in
            let query = parseQuery(request.uri.query)
            let result: (Bool, String) = await Task { @MainActor in
                guard let path = query["path"], handle.prefs.isPathAllowed(path) else {
                    return (false, "path not allowed")
                }
                let q = query["q"] ?? ""
                let files = listProjectFiles(under: path, query: q)
                return (true, encodeFileEntries(files))
            }.value
            if !result.0 {
                return errorResponse(.forbidden, result.1)
            }
            return jsonResponse(result.1)
        }

        group.get("/projects/file") { request, _ -> Response in
            let query = parseQuery(request.uri.query)
            let result: (HTTPResponse.Status, String) = await Task { @MainActor in
                guard let path = query["path"], handle.prefs.isPathAllowed(path) else {
                    return (.forbidden, "{\"error\":\"path not allowed\"}")
                }
                guard let content = readSingleFile(at: path) else {
                    return (.notFound, "{\"error\":\"file not found or not readable\"}")
                }
                return (.ok, encodeFileContent(content))
            }.value
            return jsonResponse(result.1, status: result.0)
        }

        // MARK: Sessions

        group.get("/sessions") { _, _ -> Response in
            let list = try await handle.manager.list()
            return jsonResponse(encodeSessionList(list))
        }

        group.post("/sessions") { request, _ -> Response in
            let body = try await readBody(request, max: 64 * 1024)
            guard let req = decodeCreate(body) else {
                return errorResponse(.badRequest, "Bad request body")
            }
            let result: Result<String, Error> = await Task { @MainActor in
                do {
                    let descriptor = try await handle.processes.spawn(request: req)
                    return .success(encodeSession(descriptor))
                } catch {
                    return .failure(error)
                }
            }.value
            switch result {
            case .success(let json): return jsonResponse(json)
            case .failure(let err):  return errorResponse(.badRequest, err.localizedDescription)
            }
        }

        group.delete("/sessions/:id") { _, context -> Response in
            guard let id = context.parameters.get("id") else {
                return errorResponse(.badRequest, "missing id")
            }
            let terminated = await Task { @MainActor in
                await handle.processes.terminate(id: id)
            }.value
            return jsonResponse("{\"terminated\":\(terminated)}")
        }

        group.post("/sessions/:id/message") { request, context -> Response in
            guard let id = context.parameters.get("id") else {
                return errorResponse(.badRequest, "missing id")
            }
            let body = try await readBody(request, max: 1024 * 1024)
            guard let content = decodeContent(body) else {
                return errorResponse(.badRequest, "missing content")
            }
            do {
                let result: Result<Void, Error> = await Task { @MainActor in
                    guard let host = handle.processes.host(forSessionId: id) else {
                        return .failure(NSError(domain: "Smoothie", code: 404, userInfo: [NSLocalizedDescriptionKey: "session not found"]))
                    }
                    do {
                        try await host.write(content)
                        return .success(())
                    } catch {
                        return .failure(error)
                    }
                }.value
                switch result {
                case .success: return jsonResponse("{\"status\":\"ok\"}")
                case .failure(let err):
                    let status: HTTPResponse.Status = (err as NSError).code == 404 ? .notFound : .internalServerError
                    return errorResponse(status, err.localizedDescription)
                }
            }
        }

        group.get("/sessions/:id/stream") { _, context -> Response in
            guard let id = context.parameters.get("id") else {
                return errorResponse(.badRequest, "missing id")
            }
            guard let session = try await handle.manager.get(id: id) else {
                return errorResponse(.notFound, "session not found")
            }

            let buffered = try await session.snapshot()
            let backlog = buffered.map { encodeSSE(event: $0) }
            let connectComment = ByteBuffer(bytes: Array(": connected\n\n".utf8))

            let stream = AsyncStream<ByteBuffer> { continuation in
                continuation.yield(connectComment)
                for frame in backlog {
                    continuation.yield(frame)
                }
                let sub = session.subscribeForSwift { event in
                    continuation.yield(encodeSSE(event: event))
                }
                let subBox = SubscriptionBox(sub: sub)
                continuation.onTermination = { _ in subBox.close() }
            }

            return Response(
                status: .ok,
                headers: [
                    .contentType: "text/event-stream",
                    .cacheControl: "no-cache",
                    .connection: "keep-alive",
                ],
                body: ResponseBody(asyncSequence: stream)
            )
        }
    }
}

/// Holds a Kotlin Subscription so we can drop it from a non-Sendable
/// closure context (AsyncStream.onTermination).
final class SubscriptionBox: @unchecked Sendable {
    private let sub: Subscription
    init(sub: Subscription) { self.sub = sub }
    func close() { sub.close() }
}

// MARK: - Encoders

func encodeAdapterList(_ infos: [AdapterInfo]) -> String {
    var entries: [String] = []
    for info in infos {
        var keys: [String] = []
        keys.append("\"cli\":\"\(info.cli.name.lowercased())\"")
        keys.append("\"installed\":\(info.installed)")
        if let v = info.version { keys.append("\"version\":\(jsonString(v))") }
        else { keys.append("\"version\":null") }
        if let features = info.features {
            keys.append("\"features\":\(encodeFeatures(features))")
        } else {
            keys.append("\"features\":null")
        }
        entries.append("{" + keys.joined(separator: ",") + "}")
    }
    return "[" + entries.joined(separator: ",") + "]"
}

func encodeFeatures(_ f: ProviderFeatures) -> String {
    var keys: [String] = []
    keys.append("\"supportsModelPicker\":\(f.supportsModelPicker)")
    keys.append("\"supportsReasoningEffort\":\(f.supportsReasoningEffort)")
    keys.append("\"supportsModes\":\(f.supportsModes)")
    if let m = f.defaultModel { keys.append("\"defaultModel\":\(jsonString(m))") }
    else { keys.append("\"defaultModel\":null") }
    keys.append("\"availableModels\":\(jsonStringArray(f.availableModels))")
    keys.append("\"availableReasoningEfforts\":\(jsonStringArray(f.availableReasoningEfforts))")
    keys.append("\"availableModes\":\(jsonStringArray(f.availableModes))")
    let cmds = f.slashCommands.map { c in
        "{\"name\":\(jsonString(c.name)),\"description\":\(jsonString(c.description_))}"
    }
    keys.append("\"slashCommands\":[" + cmds.joined(separator: ",") + "]")
    return "{" + keys.joined(separator: ",") + "}"
}

func encodeSessionList(_ list: [SessionDescriptor]) -> String {
    let items = list.map(encodeSession)
    return "[" + items.joined(separator: ",") + "]"
}

func encodeSession(_ d: SessionDescriptor) -> String {
    var keys: [String] = []
    keys.append("\"id\":\(jsonString(d.id))")
    keys.append("\"projectPath\":\(jsonString(d.projectPath))")
    keys.append("\"projectName\":\(jsonString(d.projectName))")
    keys.append("\"cli\":\"\(d.cli.name.lowercased())\"")
    if let m = d.model { keys.append("\"model\":\(jsonString(m))") } else { keys.append("\"model\":null") }
    if let r = d.reasoningEffort { keys.append("\"reasoningEffort\":\(jsonString(r))") } else { keys.append("\"reasoningEffort\":null") }
    if let mode = d.mode { keys.append("\"mode\":\(jsonString(mode))") } else { keys.append("\"mode\":null") }
    keys.append("\"state\":\"\(d.state.name.lowercased())\"")
    keys.append("\"createdAt\":\(d.createdAt)")
    return "{" + keys.joined(separator: ",") + "}"
}

func encodeEvent(_ e: SmoothieEvent) -> String {
    var keys: [String] = []
    keys.append("\"type\":\"\(e.type.name.lowercased())\"")
    keys.append("\"content\":\(jsonString(e.content))")
    keys.append("\"timestamp\":\(e.timestamp)")
    keys.append("\"metadata\":null")
    return "{" + keys.joined(separator: ",") + "}"
}

func encodeSSE(event: SmoothieEvent) -> ByteBuffer {
    let json = encodeEvent(event)
    let frame = "event: \(event.type.name.lowercased())\ndata: \(json)\n\n"
    return ByteBuffer(bytes: Array(frame.utf8))
}

// MARK: - Project scanning (P5 stub; Cursor-style picker is P6)

struct ProjectInfo: Sendable {
    let name: String
    let path: String
    let isGit: Bool
}

@MainActor
func listTopLevelProjects(allowedRoots: [String]) -> [ProjectInfo] {
    let fm = FileManager.default
    var seen = Set<String>()
    var out: [ProjectInfo] = []
    for root in allowedRoots {
        guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
        for entry in entries where !entry.hasPrefix(".") {
            let full = (root as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue else { continue }
            if seen.contains(full) { continue }
            seen.insert(full)
            let isGit = fm.fileExists(atPath: (full as NSString).appendingPathComponent(".git"))
            out.append(ProjectInfo(name: entry, path: full, isGit: isGit))
        }
    }
    return out.sorted { a, b in
        if a.isGit != b.isGit { return a.isGit }
        return a.name.lowercased() < b.name.lowercased()
    }
}

func encodeProjectList(_ projects: [ProjectInfo]) -> String {
    let items = projects.map { p in
        "{\"name\":\(jsonString(p.name)),\"path\":\(jsonString(p.path)),\"isGit\":\(p.isGit)}"
    }
    return "[" + items.joined(separator: ",") + "]"
}

// MARK: - Folder browser (P6)

struct BrowseEntryInfo: Sendable {
    let name: String
    let path: String
    let isDirectory: Bool
    let isGit: Bool
    let isAllowed: Bool
}

struct BrowseResponseInfo: Sendable {
    let current: String?
    let parent: String?
    let entries: [BrowseEntryInfo]
    let roots: [String]
}

private let browseHiddenExcludes: Set<String> = [
    ".Trash", ".cache", "Library", ".npm", ".yarn", ".pnpm", ".bun"
]

private let browseDirExcludes: Set<String> = [
    ".git", ".build", ".swiftpm", "node_modules", "DerivedData",
    ".expo", ".next", ".cache", "dist", "build", ".turbo",
    ".DS_Store", "Pods", ".gradle"
]

@MainActor
func browseFolder(path: String?, prefs: Preferences) -> BrowseResponseInfo {
    let roots = prefs.allowedRoots
    if let path, !path.isEmpty {
        guard prefs.isPathAllowed(path) else {
            return BrowseResponseInfo(current: nil, parent: nil, entries: rootBrowseEntries(roots), roots: roots)
        }
        let parentPath = (path as NSString).deletingLastPathComponent
        let parent: String? = {
            if parentPath == path { return nil }
            return prefs.isPathAllowed(parentPath) ? parentPath : nil
        }()
        return BrowseResponseInfo(
            current: path,
            parent: parent,
            entries: listSubdirs(at: path, prefs: prefs),
            roots: roots
        )
    }
    return BrowseResponseInfo(current: nil, parent: nil, entries: rootBrowseEntries(roots), roots: roots)
}

private func rootBrowseEntries(_ roots: [String]) -> [BrowseEntryInfo] {
    let fm = FileManager.default
    return roots.compactMap { root in
        guard fm.fileExists(atPath: root) else { return nil }
        let name = (root as NSString).lastPathComponent
        let isGit = fm.fileExists(atPath: (root as NSString).appendingPathComponent(".git"))
        return BrowseEntryInfo(name: name, path: root, isDirectory: true, isGit: isGit, isAllowed: true)
    }
}

@MainActor
private func listSubdirs(at path: String, prefs: Preferences) -> [BrowseEntryInfo] {
    let fm = FileManager.default
    guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return [] }
    var entries: [BrowseEntryInfo] = []
    for name in contents {
        if name.hasPrefix(".") && name != ".git" { continue }
        if browseHiddenExcludes.contains(name) { continue }
        if browseDirExcludes.contains(name) { continue }
        let full = (path as NSString).appendingPathComponent(name)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue else { continue }
        let isGit = fm.fileExists(atPath: (full as NSString).appendingPathComponent(".git"))
        entries.append(BrowseEntryInfo(
            name: name,
            path: full,
            isDirectory: true,
            isGit: isGit,
            isAllowed: prefs.isPathAllowed(full)
        ))
    }
    return entries.sorted { a, b in
        if a.isGit != b.isGit { return a.isGit }
        return a.name.lowercased() < b.name.lowercased()
    }
}

func encodeBrowseResponse(_ r: BrowseResponseInfo) -> String {
    var keys: [String] = []
    if let c = r.current { keys.append("\"current\":\(jsonString(c))") } else { keys.append("\"current\":null") }
    if let p = r.parent { keys.append("\"parent\":\(jsonString(p))") } else { keys.append("\"parent\":null") }
    let entryItems = r.entries.map { e in
        "{\"name\":\(jsonString(e.name)),\"path\":\(jsonString(e.path)),\"isDirectory\":\(e.isDirectory),\"isGit\":\(e.isGit),\"isAllowed\":\(e.isAllowed)}"
    }
    keys.append("\"entries\":[" + entryItems.joined(separator: ",") + "]")
    keys.append("\"roots\":\(jsonStringArray(r.roots))")
    return "{" + keys.joined(separator: ",") + "}"
}

// MARK: - File listing (P6 — used by Mention picker in P7 too)

struct FileEntryInfo: Sendable {
    let path: String        // relative
    let fullPath: String    // absolute
    let size: Int
}

struct FileContentInfo: Sendable {
    let path: String
    let content: String
    let size: Int
    let truncated: Bool
}

private let fileListExcludes: Set<String> = [
    ".git", ".build", ".swiftpm", "node_modules", "DerivedData",
    ".expo", ".next", ".cache", "dist", "build", ".turbo",
    ".DS_Store", "Pods", ".gradle"
]
private let fileMaxBytes = 100 * 1024
private let fileListMaxResults = 1000

@MainActor
func listProjectFiles(under root: String, query: String) -> [FileEntryInfo] {
    let fm = FileManager.default
    let q = query.lowercased()
    let rootURL = URL(fileURLWithPath: root)
    guard let enumerator = fm.enumerator(
        at: rootURL,
        includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
        options: [.skipsHiddenFiles]
    ) else { return [] }

    var results: [FileEntryInfo] = []
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
        results.append(FileEntryInfo(path: relative, fullPath: abs, size: values?.fileSize ?? 0))
    }
    return results.sorted { $0.path.lowercased() < $1.path.lowercased() }
}

@MainActor
func readSingleFile(at path: String) -> FileContentInfo? {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return nil }
    guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? handle.close() }
    let attrs = try? fm.attributesOfItem(atPath: path)
    let actualSize = (attrs?[.size] as? Int) ?? 0
    let data = (try? handle.read(upToCount: fileMaxBytes + 1)) ?? Data()
    let truncated = data.count > fileMaxBytes || actualSize > fileMaxBytes
    let trimmed = truncated ? data.prefix(fileMaxBytes) : data
    guard let text = String(data: trimmed, encoding: .utf8) else { return nil }
    return FileContentInfo(path: path, content: text, size: trimmed.count, truncated: truncated)
}

func encodeFileEntries(_ entries: [FileEntryInfo]) -> String {
    let items = entries.map { e in
        "{\"path\":\(jsonString(e.path)),\"fullPath\":\(jsonString(e.fullPath)),\"size\":\(e.size)}"
    }
    return "[" + items.joined(separator: ",") + "]"
}

func encodeFileContent(_ c: FileContentInfo) -> String {
    var keys: [String] = []
    keys.append("\"path\":\(jsonString(c.path))")
    keys.append("\"content\":\(jsonString(c.content))")
    keys.append("\"size\":\(c.size)")
    keys.append("\"truncated\":\(c.truncated)")
    return "{" + keys.joined(separator: ",") + "}"
}

// MARK: - Query parsing

func parseQuery(_ raw: String?) -> [String: String] {
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

// MARK: - Decoders

func decodeCreate(_ data: Data) -> CreateSessionRequest? {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    guard let projectPath = obj["projectPath"] as? String,
          let cliRaw = obj["cli"] as? String,
          let cli = parseCLIType(cliRaw)
    else { return nil }
    let model = obj["model"] as? String
    let reasoning = obj["reasoningEffort"] as? String
    let mode = obj["mode"] as? String
    return CreateSessionRequest(
        projectPath: projectPath,
        cli: cli,
        model: model,
        reasoningEffort: reasoning,
        mode: mode
    )
}

func decodeContent(_ data: Data) -> String? {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    return obj["content"] as? String
}

func parseCLIType(_ raw: String) -> CLIType? {
    switch raw.lowercased() {
    case "claude", "claude_code", "claude-code", "claudecode": return .claudeCode
    case "gemini":                                              return .gemini
    case "opencode", "open_code", "open-code":                  return .openCode
    default:                                                    return nil
    }
}

// MARK: - Util

func readBody(_ request: Request, max: Int) async throws -> Data {
    let buffer = try await request.body.collect(upTo: max)
    return Data(buffer.readableBytesView)
}

func jsonString(_ value: String) -> String {
    if let data = try? JSONSerialization.data(withJSONObject: [value], options: [.fragmentsAllowed]),
       let str = String(data: data, encoding: .utf8) {
        let trimmed = str.dropFirst().dropLast()
        return String(trimmed)
    }
    return "\"\""
}

func jsonStringArray(_ values: [String]) -> String {
    "[" + values.map { jsonString($0) }.joined(separator: ",") + "]"
}

func jsonResponse(_ body: String, status: HTTPResponse.Status = .ok) -> Response {
    var buf = ByteBuffer()
    buf.writeBytes(Array(body.utf8))
    return Response(
        status: status,
        headers: [.contentType: "application/json"],
        body: ResponseBody(byteBuffer: buf)
    )
}

func errorResponse(_ status: HTTPResponse.Status, _ message: String) -> Response {
    let body = "{\"error\":\(jsonString(message))}"
    return jsonResponse(body, status: status)
}

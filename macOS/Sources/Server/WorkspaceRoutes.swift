import Foundation
import Hummingbird
import Shared

/// Per-session workspace endpoints — git branch listing/switching and
/// MCP server enable/disable. Mounted from `Routes.mount` so they share
/// the same Bearer-guarded group, but kept in their own file because
/// neither feature is core to the session lifecycle (which lives in
/// Routes.swift).
enum WorkspaceRoutes {
    @MainActor
    static func mount(
        _ group: RouterGroup<BasicRequestContext>,
        handle: Routes.Handle
    ) {
        // MARK: - Branches

        // GET /sessions/:id/branches
        // Lists every branch in the project's working tree along with the
        // currently checked-out branch. The project path comes from the
        // Session descriptor — the daemon doesn't accept caller-supplied
        // paths so a compromised iOS client can't trick the daemon into
        // running git in an unexpected directory.
        group.get("/sessions/:id/branches") { _, context -> Response in
            guard let id = context.parameters.get("id") else {
                return errorResponse(.badRequest, "missing id")
            }
            let result: Result<BranchListing, Error> = await Task { @MainActor in
                guard let session = try? await handle.manager.get(id: id) else {
                    return .failure(NSError(
                        domain: "Smoothie", code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "session not found"]
                    ))
                }
                let descriptor: SessionDescriptor
                do {
                    descriptor = try await session.descriptor()
                } catch {
                    return .failure(error)
                }
                do {
                    let listing = try GitBranches.list(cwd: descriptor.projectPath)
                    return .success(listing)
                } catch {
                    return .failure(error)
                }
            }.value
            switch result {
            case .success(let listing):
                return jsonResponse(encodeBranchListing(listing))
            case .failure(let err):
                let nsErr = err as NSError
                let status: HTTPResponse.Status = nsErr.code == 404 ? .notFound : .internalServerError
                return errorResponse(status, nsErr.localizedDescription)
            }
        }

        // POST /sessions/:id/branch  { "branch": "feature/x" }
        // Runs `git checkout <branch>` in the project root. On success the
        // updated SessionDescriptor (carrying the new branch in metadata)
        // is returned. Uncommitted changes / merge conflicts surface as
        // 409 Conflict with git's stderr in the body so the iOS picker can
        // show the real reason.
        group.post("/sessions/:id/branch") { request, context -> Response in
            guard let id = context.parameters.get("id") else {
                return errorResponse(.badRequest, "missing id")
            }
            let body = try await readBody(request, max: 4_096)
            guard let branchName = decodeBranchBody(body) else {
                return errorResponse(.badRequest, "missing branch")
            }
            // SessionDescriptor isn't Sendable (Kotlin/Native type), so
            // the cross-actor hop returns the already-encoded JSON
            // string instead of the descriptor itself. encode() runs
            // inside the @MainActor closure where the Kotlin type can
            // safely be read.
            let result: Result<String, Error> = await Task { @MainActor in
                guard let session = try? await handle.manager.get(id: id) else {
                    return .failure(NSError(
                        domain: "Smoothie", code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "session not found"]
                    ))
                }
                let descriptor: SessionDescriptor
                do {
                    descriptor = try await session.descriptor()
                } catch {
                    return .failure(error)
                }
                do {
                    try GitBranches.checkout(cwd: descriptor.projectPath, branch: branchName)
                } catch {
                    return .failure(error)
                }
                let final = (try? await session.descriptor()) ?? descriptor
                return .success(encodeSession(final))
            }.value
            switch result {
            case .success(let json):
                return jsonResponse(json)
            case .failure(let err):
                let nsErr = err as NSError
                let status: HTTPResponse.Status
                switch nsErr.code {
                case 404: status = .notFound
                case 409: status = .conflict
                default:  status = .internalServerError
                }
                return errorResponse(status, nsErr.localizedDescription)
            }
        }

        // MARK: - MCP servers

        // GET /sessions/:id/mcp-servers
        // Returns the merged view: every MCP server the daemon knows
        // about (from per-CLI config discovery) plus the per-session
        // enabled subset. The iOS picker uses this to render the toggle
        // list. Unknown providers yield an empty `available` array — the
        // picker degrades gracefully to a "no servers" state rather than
        // erroring out.
        group.get("/sessions/:id/mcp-servers") { _, context -> Response in
            guard let id = context.parameters.get("id") else {
                return errorResponse(.badRequest, "missing id")
            }
            let result: Result<MCPListing, Error> = await Task { @MainActor in
                guard let session = try? await handle.manager.get(id: id) else {
                    return .failure(NSError(
                        domain: "Smoothie", code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "session not found"]
                    ))
                }
                let descriptor: SessionDescriptor
                do {
                    descriptor = try await session.descriptor()
                } catch {
                    return .failure(error)
                }
                let available = MCPDiscovery.servers(for: descriptor.cli)
                let enabled = handle.prefs.mcpEnabledServers(forSessionId: id) ?? available.map { $0.id }
                return .success(MCPListing(available: available, enabled: enabled))
            }.value
            switch result {
            case .success(let listing):
                return jsonResponse(encodeMCPListing(listing))
            case .failure(let err):
                let nsErr = err as NSError
                let status: HTTPResponse.Status = nsErr.code == 404 ? .notFound : .internalServerError
                return errorResponse(status, nsErr.localizedDescription)
            }
        }

        // MARK: - Transcript (Past Chats mention)

        // GET /sessions/:id/transcript
        // Returns the session's MESSAGE event stream assembled as a
        // single markdown string. Used by the iOS "Past Chats" mention
        // picker so a user can attach a prior conversation as context
        // to the next outgoing turn. Non-MESSAGE events (tool calls,
        // thinking, file edits) are skipped — the goal is the
        // dialogue, not the agent's machinery.
        group.get("/sessions/:id/transcript") { _, context -> Response in
            guard let id = context.parameters.get("id") else {
                return errorResponse(.badRequest, "missing id")
            }
            let result: Result<String, Error> = await Task { @MainActor in
                guard let session = try? await handle.manager.get(id: id) else {
                    return .failure(NSError(
                        domain: "Smoothie", code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "session not found"]
                    ))
                }
                let events = (try? await session.snapshot()) ?? []
                let descriptor: SessionDescriptor
                do {
                    descriptor = try await session.descriptor()
                } catch {
                    return .failure(error)
                }
                let assembled = assembleTranscript(
                    events: events,
                    projectName: descriptor.projectName,
                    cliName: descriptor.cli.name
                )
                return .success(assembled)
            }.value
            switch result {
            case .success(let body):
                let payload = "{\"transcript\":\(jsonString(body))}"
                return jsonResponse(payload)
            case .failure(let err):
                let nsErr = err as NSError
                let status: HTTPResponse.Status = nsErr.code == 404 ? .notFound : .internalServerError
                return errorResponse(status, nsErr.localizedDescription)
            }
        }

        // MARK: - P29 §8 — Create PR

        // GET /git/pr-ready
        // Lightweight precheck for the iOS composer's "Create PR" chip.
        // Hides the chip when `gh` is missing or the user hasn't run
        // `gh auth login`. iOS caches this for the app session.
        group.get("/git/pr-ready") { _, _ -> Response in
            let result = await Task { @MainActor in
                GitPRCreator.ghReady()
            }.value
            return jsonResponse(encodePRReady(result))
        }

        // POST /sessions/:id/create-pr
        // Runs the full git → gh pipeline (branch / add / commit /
        // push / pr create) in the session's project directory.
        // Returns the resulting PR URL or a stage-tagged error so the
        // iOS CreatePRSheet can surface a precise diagnostic.
        group.post("/sessions/:id/create-pr") { request, context -> Response in
            guard let id = context.parameters.get("id") else {
                return errorResponse(.badRequest, "missing id")
            }
            let body = try await readBody(request, max: 16_384)
            guard let payload = decodeCreatePRBody(body) else {
                return errorResponse(.badRequest, "invalid create-pr body")
            }
            let result: Result<String, Error> = await Task { @MainActor in
                guard let session = try? await handle.manager.get(id: id) else {
                    return .failure(NSError(
                        domain: "Smoothie", code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "session not found"]
                    ))
                }
                let descriptor: SessionDescriptor
                do {
                    descriptor = try await session.descriptor()
                } catch {
                    return .failure(error)
                }
                do {
                    let url = try GitPRCreator.createPR(
                        cwd: descriptor.projectPath,
                        title: payload.title,
                        body: payload.body,
                        branch: payload.branch,
                        useCurrentBranch: payload.useCurrentBranch
                    )
                    return .success(url)
                } catch let err as GitPRCreator.PRCreationError {
                    return .failure(NSError(
                        domain: "Smoothie", code: 409,
                        userInfo: [NSLocalizedDescriptionKey: "\(err.stage.rawValue): \(err.message)"]
                    ))
                } catch {
                    return .failure(error)
                }
            }.value
            switch result {
            case .success(let url):
                let payload = "{\"url\":\(jsonString(url))}"
                return jsonResponse(payload)
            case .failure(let err):
                let nsErr = err as NSError
                let status: HTTPResponse.Status
                switch nsErr.code {
                case 404: status = .notFound
                case 409: status = .conflict
                default:  status = .internalServerError
                }
                return errorResponse(status, nsErr.localizedDescription)
            }
        }

        // POST /sessions/:id/mcp-servers  { "enabled": ["id1", "id2"] }
        // Persists the per-session enabled subset. Takes effect on the
        // next host spawn (so the user typically follows this with a
        // model change or session restart). v1 doesn't restart hosts
        // automatically — that's a larger change touching ProcessRegistry.
        group.post("/sessions/:id/mcp-servers") { request, context -> Response in
            guard let id = context.parameters.get("id") else {
                return errorResponse(.badRequest, "missing id")
            }
            let body = try await readBody(request, max: 16_384)
            guard let enabledIds = decodeMCPEnabledBody(body) else {
                return errorResponse(.badRequest, "missing enabled list")
            }
            let result: Result<MCPListing, Error> = await Task { @MainActor in
                guard let session = try? await handle.manager.get(id: id) else {
                    return .failure(NSError(
                        domain: "Smoothie", code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "session not found"]
                    ))
                }
                handle.prefs.setMcpEnabledServers(enabledIds, forSessionId: id)
                let descriptor: SessionDescriptor
                do {
                    descriptor = try await session.descriptor()
                } catch {
                    return .failure(error)
                }
                let available = MCPDiscovery.servers(for: descriptor.cli)
                return .success(MCPListing(available: available, enabled: enabledIds))
            }.value
            switch result {
            case .success(let listing):
                return jsonResponse(encodeMCPListing(listing))
            case .failure(let err):
                let nsErr = err as NSError
                let status: HTTPResponse.Status = nsErr.code == 404 ? .notFound : .internalServerError
                return errorResponse(status, nsErr.localizedDescription)
            }
        }
    }
}

// MARK: - Encoders / decoders

/// Listing returned by GET /sessions/:id/branches.
struct BranchListing {
    let current: String?
    let branches: [String]
}

func encodeBranchListing(_ listing: BranchListing) -> String {
    var parts: [String] = []
    if let current = listing.current {
        parts.append("\"current\":\(jsonString(current))")
    } else {
        parts.append("\"current\":null")
    }
    parts.append("\"branches\":\(jsonStringArray(listing.branches))")
    return "{" + parts.joined(separator: ",") + "}"
}

func decodeBranchBody(_ data: Data) -> String? {
    struct Body: Decodable { let branch: String }
    guard let body = try? JSONDecoder().decode(Body.self, from: data) else { return nil }
    let trimmed = body.branch.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

/// Single MCP server entry surfaced to the picker.
struct MCPServerInfo {
    let id: String
    let name: String
    let description: String?
    let command: String?
    let source: String
}

struct MCPListing {
    let available: [MCPServerInfo]
    let enabled: [String]
}

func encodeMCPListing(_ listing: MCPListing) -> String {
    let avail = listing.available.map(encodeMCPServer).joined(separator: ",")
    var parts: [String] = []
    parts.append("\"available\":[\(avail)]")
    parts.append("\"enabled\":\(jsonStringArray(listing.enabled))")
    return "{" + parts.joined(separator: ",") + "}"
}

func encodeMCPServer(_ s: MCPServerInfo) -> String {
    var parts: [String] = []
    parts.append("\"id\":\(jsonString(s.id))")
    parts.append("\"name\":\(jsonString(s.name))")
    if let desc = s.description {
        parts.append("\"description\":\(jsonString(desc))")
    } else {
        parts.append("\"description\":null")
    }
    if let cmd = s.command {
        parts.append("\"command\":\(jsonString(cmd))")
    } else {
        parts.append("\"command\":null")
    }
    parts.append("\"source\":\(jsonString(s.source))")
    return "{" + parts.joined(separator: ",") + "}"
}

func decodeMCPEnabledBody(_ data: Data) -> [String]? {
    struct Body: Decodable { let enabled: [String] }
    return (try? JSONDecoder().decode(Body.self, from: data))?.enabled
}

// MARK: - P29 §8 — Create PR encoders / decoders

/// Parsed `POST /sessions/:id/create-pr` body.
struct CreatePRPayload {
    let title: String
    let body: String
    let branch: String
    let useCurrentBranch: Bool
}

func decodeCreatePRBody(_ data: Data) -> CreatePRPayload? {
    struct Body: Decodable {
        let title: String
        let body: String
        let branch: String
        let useCurrentBranch: Bool
    }
    guard let parsed = try? JSONDecoder().decode(Body.self, from: data) else { return nil }
    let title = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let branch = parsed.branch.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return nil }
    return CreatePRPayload(
        title: title,
        body: parsed.body,
        branch: branch,
        useCurrentBranch: parsed.useCurrentBranch
    )
}

func encodePRReady(_ result: GitPRCreator.ReadyResult) -> String {
    let missingJSON = jsonStringArray(result.missing)
    return "{\"ready\":\(result.ready),\"missing\":\(missingJSON)}"
}

// MARK: - Transcript assembly

/// Build a compact markdown transcript from a session's event ring.
/// MESSAGE events are kept; everything else (tool calls, thinking,
/// state pings, context updates) is dropped — the goal is the
/// dialogue, not the agent's machinery. Lines are prefixed with
/// `**Agent:**` / `**You:**` heuristically: the daemon doesn't tag
/// MESSAGE events with author today, so we assume the assistant is
/// the source. The first line is a one-line header so the caller can
/// drop the block straight into another prompt as a reference.
func assembleTranscript(events: [SmoothieEvent], projectName: String, cliName: String) -> String {
    var lines: [String] = []
    lines.append("# Past chat — \(projectName) (\(cliName))")
    lines.append("")
    var emittedAny = false
    for event in events {
        guard event.type == EventType.message else { continue }
        let trimmed = event.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        lines.append("**Agent:** \(trimmed)")
        lines.append("")
        emittedAny = true
    }
    if !emittedAny {
        lines.append("_(no assistant messages were exchanged in this session.)_")
    }
    return lines.joined(separator: "\n")
}

import Foundation

/// Branch + MCP endpoints. Mirror of `WorkspaceRoutes.swift` on the
/// daemon side. The same APIClient transport / error handling applies.
extension APIClient {
    // MARK: - Branches

    func branches(sessionId: String) async throws -> BranchListingWire {
        let data = try await get("/sessions/\(sessionId)/branches")
        return try decode(BranchListingWire.self, from: data)
    }

    @discardableResult
    func switchBranch(sessionId: String, branch: String) async throws -> SessionDescriptorWire {
        struct Body: Encodable { let branch: String }
        let data = try await post("/sessions/\(sessionId)/branch", json: Body(branch: branch))
        return try decode(SessionDescriptorWire.self, from: data)
    }

    // MARK: - MCP servers

    func mcpServers(sessionId: String) async throws -> MCPListingWire {
        let data = try await get("/sessions/\(sessionId)/mcp-servers")
        return try decode(MCPListingWire.self, from: data)
    }

    @discardableResult
    func setMCPEnabled(sessionId: String, enabled: [String]) async throws -> MCPListingWire {
        struct Body: Encodable { let enabled: [String] }
        let data = try await post("/sessions/\(sessionId)/mcp-servers", json: Body(enabled: enabled))
        return try decode(MCPListingWire.self, from: data)
    }

    // MARK: - Transcript (Past Chats mention)

    /// Fetch a past session's assembled markdown transcript so the
    /// composer can stage it as @-mention context for the next turn.
    /// Daemon assembles MESSAGE events only — tool calls / thinking /
    /// state pings are stripped to keep the reference block compact.
    func transcript(sessionId: String) async throws -> String {
        let data = try await get("/sessions/\(sessionId)/transcript")
        struct R: Decodable { let transcript: String }
        return try decode(R.self, from: data).transcript
    }

    // MARK: - P29 §8 — Create PR

    /// Precheck for the Create-PR composer chip. Hits
    /// `GET /git/pr-ready`, which on the daemon side runs `gh
    /// --version` and `gh auth status`. iOS caches the response for
    /// the app session — there's no live toolchain reload.
    func prReady() async throws -> PRReadyWire {
        let data = try await get("/git/pr-ready")
        return try decode(PRReadyWire.self, from: data)
    }

    /// Run the full create-PR pipeline on the daemon: optional new
    /// branch, `git add -A`, `git commit -m <title>`, `git push -u
    /// origin <branch>`, `gh pr create`. Returns the resulting PR
    /// URL. On failure the daemon returns 4xx/5xx with a stage hint
    /// in the body — the APIClient turns that into `APIError.http`.
    func createPR(sessionId: String, _ request: CreatePRRequestWire) async throws -> CreatePRResponseWire {
        let data = try await post("/sessions/\(sessionId)/create-pr", json: request)
        return try decode(CreatePRResponseWire.self, from: data)
    }
}

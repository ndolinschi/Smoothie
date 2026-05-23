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
}

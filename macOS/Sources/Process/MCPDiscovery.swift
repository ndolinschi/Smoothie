import Foundation
import Shared

/// Best-effort per-CLI MCP server discovery. Each adapter has its own
/// config format and path; this enum centralises the lookups so the
/// route layer doesn't have to special-case providers.
///
/// Today: Claude reads from `~/.claude.json` (the file `claude mcp add`
/// writes to). Other providers return empty — the daemon stub is in
/// place so the iOS picker degrades gracefully ("No MCP servers
/// detected for $cli") and the user gets the same picker UX across
/// every adapter without us having to ship four real integrations in
/// one pass.
///
/// The toggle persists in `Preferences` regardless of provider, so when
/// a future CLI grows MCP support the user's choice is already there
/// and the spawn-side wiring is the only missing piece.
enum MCPDiscovery {
    static func servers(for cli: CLIType) -> [MCPServerInfo] {
        switch cli.name.lowercased() {
        case "claude_code":
            return claudeServers()
        case "gemini":
            return geminiServers()
        case "open_code":
            return openCodeServers()
        case "antigravity":
            return []     // agy doesn't surface MCP today
        default:
            return []
        }
    }

    // MARK: - Claude Code

    /// `~/.claude.json` contains a top-level `mcpServers` map of
    /// `{ name: { command, args, ... } }`. Defensive — any malformed
    /// shape yields an empty list so the picker just shows "no servers
    /// detected" rather than the route 500'ing.
    private static func claudeServers() -> [MCPServerInfo] {
        let path = NSHomeDirectory() + "/.claude.json"
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any]
        else { return [] }
        var result: [MCPServerInfo] = []
        for (name, raw) in servers {
            let entry = raw as? [String: Any]
            let command = entry?["command"] as? String
            let descriptor = command.map { "Configured in ~/.claude.json — \($0)" }
            result.append(MCPServerInfo(
                id: name,
                name: name,
                description: descriptor,
                command: command,
                source: "~/.claude.json"
            ))
        }
        return result.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    // MARK: - Gemini

    /// Gemini CLI keeps MCP config under `~/.gemini/settings.json` with
    /// an `mcp` object. Best-effort parse; if the file shape changes the
    /// picker degrades to an empty list.
    private static func geminiServers() -> [MCPServerInfo] {
        let path = NSHomeDirectory() + "/.gemini/settings.json"
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mcp = json["mcp"] as? [String: Any],
              let servers = mcp["servers"] as? [String: Any]
        else { return [] }
        var result: [MCPServerInfo] = []
        for (name, raw) in servers {
            let entry = raw as? [String: Any]
            let command = entry?["command"] as? String
            result.append(MCPServerInfo(
                id: name,
                name: name,
                description: command.map { "Gemini MCP — \($0)" },
                command: command,
                source: "~/.gemini/settings.json"
            ))
        }
        return result.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    // MARK: - OpenCode

    /// OpenCode keeps MCP config under `~/.config/opencode/config.json`
    /// (xdg-config style). The shape is provider-defined; we read the
    /// `mcp` block if present and surface command names only.
    private static func openCodeServers() -> [MCPServerInfo] {
        let candidates = [
            NSHomeDirectory() + "/.config/opencode/config.json",
            NSHomeDirectory() + "/.opencode/config.json",
        ]
        for path in candidates {
            guard FileManager.default.fileExists(atPath: path),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let mcp = json["mcp"] as? [String: Any]
            else { continue }
            var result: [MCPServerInfo] = []
            for (name, raw) in mcp {
                let entry = raw as? [String: Any]
                let command = entry?["command"] as? String
                result.append(MCPServerInfo(
                    id: name,
                    name: name,
                    description: command.map { "OpenCode MCP — \($0)" },
                    command: command,
                    source: path
                ))
            }
            return result.sorted { $0.name.lowercased() < $1.name.lowercased() }
        }
        return []
    }
}

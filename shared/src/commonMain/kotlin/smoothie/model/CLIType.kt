package smoothie.model

import kotlinx.serialization.Serializable

@Serializable
enum class CLIType(val executableName: String, val displayName: String) {
    CLAUDE_CODE(executableName = "claude", displayName = "Claude Code"),
    GEMINI(executableName = "gemini", displayName = "Gemini"),
    OPEN_CODE(executableName = "opencode", displayName = "OpenCode"),
    /**
     * Google Antigravity CLI — `agy` (released May 2026 at I/O, replaces
     * Gemini CLI for consumer accounts on 18 June 2026). Headless invocation
     * is `agy -p "<text>"` with optional `-c` to continue the most recent
     * conversation in the same working directory. Auth is OAuth via the
     * desktop Antigravity.app; the daemon assumes the user has signed in
     * once on this Mac.
     */
    ANTIGRAVITY(executableName = "agy", displayName = "Antigravity"),
}

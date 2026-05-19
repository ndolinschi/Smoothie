package smoothie.model

import kotlinx.serialization.Serializable

@Serializable
enum class CLIType(val executableName: String, val displayName: String) {
    CLAUDE_CODE(executableName = "claude", displayName = "Claude Code"),
    GEMINI(executableName = "gemini", displayName = "Gemini"),
    OPEN_CODE(executableName = "opencode", displayName = "OpenCode"),
}

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
    /**
     * OpenAI Codex CLI — `codex`. Non-interactive invocation is
     * `codex exec --json "<prompt>"` which emits a JSONL stream of
     * thread/turn/item events (item types include agent_message,
     * reasoning, command, file_change, mcp_tool_call, web_search,
     * plan_update). Install: `brew install openai-codex` or
     * `npm i -g @openai/codex`.
     */
    CODEX(executableName = "codex", displayName = "Codex"),
    /**
     * Cursor CLI — `cursor-agent`. Headless invocation speaks ACP
     * (Agent Client Protocol) — JSON-RPC 2.0 over stdio. Flow:
     * initialize → authenticate → session/new → session/prompt with
     * streaming chunks for thinking blocks, tool calls, and assistant
     * messages. Install: `curl https://cursor.com/install -fsS | bash`.
     */
    CURSOR(executableName = "cursor-agent", displayName = "Cursor"),
}

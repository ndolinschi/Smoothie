package smoothie.session

import kotlinx.serialization.Serializable
import smoothie.model.CLIType

/**
 * Snapshot exposed to iOS. Categories are intentionally ordered so the
 * segmented status-footer bar always reads the same way across
 * platforms (System prompt left, conversation right). Daemon owns the
 * canonical order so the client doesn't have to sort.
 */
@Serializable
data class ContextSnapshot(
    val total: Int,
    val max: Int,
    val breakdown: List<ContextCategory>,
)

@Serializable
data class ContextCategory(
    val id: String,
    val label: String,
    val tokens: Int,
)

/**
 * Per-`Session` token-budget bookkeeping. Phase 2 v1 ships the
 * `conversation` counter (every emitted MESSAGE / THINKING / TOOL_USE
 * / TOOL_RESULT / FILE_EDIT body contributes its char-count via
 * `TokenEstimator`). The other six slots (system prompt, tool
 * definitions, rules, skills, mcp, subagent definitions) are reported
 * as zero today; they'll fill in as the daemon-side prompt assembly
 * grows hooks to declare what it loaded.
 *
 * Thread-safety: callers must serialise themselves (we wrap mutations
 * in the owning `Session`'s mutex). Reading via `snapshot()` is a
 * single value-type copy.
 */
class ContextTracker(private val cli: CLIType) {
    private var systemPromptTokens: Int = 0
    private var toolDefinitionTokens: Int = 0
    private var rulesTokens: Int = 0
    private var skillsTokens: Int = 0
    private var mcpTokens: Int = 0
    private var subagentDefinitionTokens: Int = 0
    private var conversationTokens: Int = 0

    /** Hard ceiling for the current model. Static map per CLI for now;
     *  daemon may eventually surface this via /adapters. */
    private val maxTokens: Int
        get() = when (cli) {
            CLIType.CLAUDE_CODE -> 200_000
            CLIType.GEMINI      -> 1_000_000
            CLIType.OPEN_CODE   -> 200_000
            CLIType.ANTIGRAVITY -> 0          // unknown → iOS hides ring
            CLIType.CODEX       -> 256_000    // gpt-5-codex window per OpenAI docs
            CLIType.CURSOR      -> 200_000    // proxies underlying model; safe default
        }

    /** Add an emitted event's content to the conversation bucket. Called
     *  from Session.ingestParsed for every event whose content takes
     *  real tokens (MESSAGE / THINKING / TOOL_USE / TOOL_RESULT /
     *  FILE_EDIT). Skipped for WAITING / DONE / ERROR — those are state
     *  transitions, not content. */
    fun addConversation(content: String) {
        conversationTokens += TokenEstimator.estimate(content)
    }

    /** Seed the system-prompt bucket. Called once at session boot when
     *  the macOS side knows the assembled safety prompt. */
    fun seedSystemPrompt(text: String) {
        systemPromptTokens = TokenEstimator.estimate(text)
    }

    fun snapshot(): ContextSnapshot {
        val total = systemPromptTokens + toolDefinitionTokens + rulesTokens +
            skillsTokens + mcpTokens + subagentDefinitionTokens + conversationTokens
        return ContextSnapshot(
            total = total,
            max = maxTokens,
            breakdown = listOf(
                ContextCategory("system_prompt",        "System prompt",        systemPromptTokens),
                ContextCategory("tool_definitions",     "Tool definitions",     toolDefinitionTokens),
                ContextCategory("rules",                "Rules",                rulesTokens),
                ContextCategory("skills",               "Skills",               skillsTokens),
                ContextCategory("mcp",                  "MCP",                  mcpTokens),
                ContextCategory("subagent_definitions", "Subagent definitions", subagentDefinitionTokens),
                ContextCategory("conversation",         "Conversation",         conversationTokens),
            )
        )
    }
}

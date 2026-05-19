package smoothie.adapters

import smoothie.model.AdapterInfo
import smoothie.model.CLIType
import smoothie.model.CreateSessionRequest
import smoothie.model.EventType
import smoothie.model.ProviderFeatures
import smoothie.model.SlashCommand
import smoothie.model.SmoothieEvent

/**
 * OpenCode parser stub. The macOS [OpenCodeServeHost] talks to
 * `opencode serve` over HTTP + SSE rather than piping stdout through this
 * parser, so the `ingest`-related methods are not wired. We still need an
 * adapter so [AdapterRegistry.parserFor] returns something the host can
 * read `info.features` from, and so the iOS picker sees OpenCode listed
 * with a real ProviderFeatures payload.
 */
class OpenCodeAdapter : AdapterParser {
    override val cli: CLIType = CLIType.OPEN_CODE
    override val info: AdapterInfo = AdapterInfo(
        cli = CLIType.OPEN_CODE,
        installed = true,
        version = null,
        features = DEFAULT_FEATURES,
    )

    override fun ingest(stdoutBytes: ByteArray): List<SmoothieEvent> = emptyList()

    override fun encodeUserMessage(content: String): String = content

    override fun launchArguments(request: CreateSessionRequest, systemPromptText: String?): List<String> {
        // The Swift host owns the actual `opencode serve` invocation; this
        // parser is HTTP-transport-only.
        return listOf("serve", "--port", "0", "--print-logs")
    }

    override fun launchEnvironment(): Map<String, String> = emptyMap()

    override fun isWaitingTurnEnd(event: SmoothieEvent): Boolean = event.type == EventType.WAITING

    override fun isLimitReached(event: SmoothieEvent): Boolean = false

    companion object {
        val DEFAULT_FEATURES = ProviderFeatures(
            supportsModelPicker = true,
            supportsReasoningEffort = false,
            supportsModes = false,
            defaultModel = null,
            // OpenCode picks the model from the user's config — we ship a
            // short list of common defaults so the iOS model picker has
            // something to show, but the actual list comes from the user's
            // `~/.config/opencode/opencode.json` config.
            availableModels = listOf(
                "anthropic/claude-sonnet-4-5",
                "anthropic/claude-haiku-4-5",
                "openai/gpt-5",
                "google/gemini-3-pro",
            ),
            availableReasoningEfforts = emptyList(),
            availableModes = emptyList(),
            slashCommands = listOf(
                SlashCommand("/help", "OpenCode help"),
                SlashCommand("/clear", "Clear conversation"),
                SlashCommand("/models", "List models"),
            ),
        )
    }
}

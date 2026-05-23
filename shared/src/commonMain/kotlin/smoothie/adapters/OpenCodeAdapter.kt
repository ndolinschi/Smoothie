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
            // OpenCode picks the model from the user's config. The
            // proper fix is to hit the running serve's `/providers`
            // endpoint after spawn and forward the result — that's
            // v1.5 work since it needs the OpenCodeServeHost to feed
            // dynamic features back through the adapter. For v1 we
            // ship a generous static list covering the four main
            // providers OpenCode supports out of the box so the iOS
            // model picker isn't an embarrassing three-row sliver.
            availableModels = listOf(
                // Anthropic
                "anthropic/claude-opus-4-7",
                "anthropic/claude-sonnet-4-6",
                "anthropic/claude-sonnet-4-5",
                "anthropic/claude-haiku-4-5",
                // OpenAI
                "openai/gpt-5",
                "openai/gpt-5-mini",
                "openai/gpt-4o",
                "openai/o1",
                "openai/o3-mini",
                // Google
                "google/gemini-3-pro",
                "google/gemini-3-flash-preview",
                "google/gemini-2.5-pro",
                // Groq / open models
                "groq/llama-3.3-70b-versatile",
                "groq/kimi-k2",
                "groq/qwen-2.5-coder-32b",
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

package smoothie.adapters

import smoothie.model.AdapterInfo
import smoothie.model.CLIType
import smoothie.model.CreateSessionRequest
import smoothie.model.EventType
import smoothie.model.ProviderFeatures
import smoothie.model.SlashCommand
import smoothie.model.SmoothieEvent

/**
 * Antigravity (`agy`) parser stub. The macOS [AntigravityOneshotHost] spawns
 * one `agy -p "<text>"` process per user turn (and keeps multi-turn memory
 * via `-c` to continue the most recent conversation in the same project cwd).
 *
 * Unlike Claude / Gemini, `agy` v1.0.0 outputs plain markdown — no JSONL,
 * no stream-json. So this adapter doesn't do line-by-line parsing; the host
 * buffers the whole stdout, then directly calls `Session.injectEvent` with
 * a single MESSAGE event followed by WAITING when the process exits. We
 * keep [ingest] as a no-op for API conformance.
 *
 * v1.0.0 flags we rely on (from `agy --help`):
 * - `-p "<text>"` / `--print` — one-shot, non-interactive
 * - `-c` / `--continue` — continue the most recent conversation
 * - `--conversation <id>` — resume a specific conversation by ID
 * - `--add-dir <path>` — add a directory to the workspace (we pass the
 *   project root via process cwd; this flag is reserved for future use)
 * - `--dangerously-skip-permissions` — auto-approve tool calls (required
 *   for headless operation since there's no terminal to prompt the user;
 *   safety is enforced via the assembled system prompt)
 * - `--print-timeout <duration>` — default 5m, we keep the default
 *
 * Model selection: v1.0.0 does NOT expose a `--model` flag. The model used
 * is whatever the user has configured in the Antigravity desktop app /
 * plugin config. We surface `supportsModelPicker = false` so the iOS picker
 * skips the section for now.
 */
class AntigravityAdapter : AdapterParser {
    override val cli: CLIType = CLIType.ANTIGRAVITY
    override val info: AdapterInfo = AdapterInfo(
        cli = CLIType.ANTIGRAVITY,
        installed = true,
        version = null,
        features = DEFAULT_FEATURES,
    )

    override fun ingest(stdoutBytes: ByteArray): List<SmoothieEvent> = emptyList()

    override fun encodeUserMessage(content: String): String = content

    override fun launchArguments(request: CreateSessionRequest, systemPromptText: String?): List<String> {
        // Static base args. The host owns the per-turn `-p "<text>"` and
        // `-c` flags since they change with each call.
        return listOf(
            "--dangerously-skip-permissions",
        )
    }

    override fun launchEnvironment(): Map<String, String> = mapOf(
        "NO_COLOR" to "1",
        "TERM" to "xterm-256color",
    )

    override fun isWaitingTurnEnd(event: SmoothieEvent): Boolean = event.type == EventType.WAITING

    override fun isLimitReached(event: SmoothieEvent): Boolean {
        if (event.type != EventType.ERROR) return false
        val needle = event.content.lowercase()
        return needle.contains("quota") ||
            needle.contains("rate limit") ||
            needle.contains("exhausted") ||
            needle.contains("billing")
    }

    companion object {
        val DEFAULT_FEATURES = ProviderFeatures(
            // agy v1.0.0 has no `--model` flag; defer to user's desktop
            // config. When Google ships a model flag we flip this on.
            supportsModelPicker = false,
            supportsReasoningEffort = false,
            // No Plan/Code mode split yet on the CLI surface — flag stays
            // off so the mode chip is hidden for Antigravity sessions.
            supportsModes = false,
            defaultModel = null,
            availableModels = emptyList(),
            availableReasoningEfforts = emptyList(),
            availableModes = emptyList(),
            slashCommands = listOf(
                SlashCommand("/logout", "Sign out of Antigravity"),
                SlashCommand("/help", "Antigravity CLI help"),
            ),
        )
    }
}

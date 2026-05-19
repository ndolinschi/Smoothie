package smoothie.adapters

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import smoothie.model.AdapterInfo
import smoothie.model.CLIType
import smoothie.model.CreateSessionRequest
import smoothie.model.EventType
import smoothie.model.ProviderFeatures
import smoothie.model.SlashCommand
import smoothie.model.SmoothieEvent
import smoothie.util.nowEpochMillis

/**
 * Parser for the Gemini CLI in stream-json mode.
 *
 * Gemini's `-p "<msg>" --output-format stream-json` emits:
 * - `{"type":"init","session_id":"…","model":"…"}` at startup
 * - `{"type":"message","role":"user","content":"<echo>"}` (skipped — we
 *    already know what the user sent)
 * - `{"type":"message","role":"assistant","content":"<chunk>","delta":true}`
 *    repeated until the turn ends
 * - `{"type":"result","status":"success",…}` at end of turn
 *
 * v1 ships Gemini as **one-shot per session** — the gemini process exits
 * after each turn. Multi-turn `--resume <id>` continuation lands in v1.5
 * once the macOS host knows how to re-spawn per send. Today: a session
 * sends one message and reaches WAITING; for a follow-up the user creates
 * a new session.
 */
class GeminiAdapter : AdapterParser {
    override val cli: CLIType = CLIType.GEMINI
    override val info: AdapterInfo = AdapterInfo(
        cli = CLIType.GEMINI,
        installed = true,
        version = null,
        features = DEFAULT_FEATURES,
    )

    private val json = Json { ignoreUnknownKeys = true; isLenient = true }
    private val buffer = StringBuilder()

    /// Captured the first time we see an `init` event. The macOS host can
    /// thread this back as `--resume <id>` once multi-turn lands.
    var lastSessionId: String? = null
        private set

    override fun ingest(stdoutBytes: ByteArray): List<SmoothieEvent> {
        buffer.append(stdoutBytes.decodeToString())
        val events = mutableListOf<SmoothieEvent>()
        while (true) {
            val nl = buffer.indexOf('\n')
            if (nl < 0) break
            val line = buffer.substring(0, nl).trim()
            buffer.deleteRange(0, nl + 1)
            if (line.isEmpty() || !line.startsWith("{")) continue
            parseLine(line)?.let { events += it }
        }
        return events
    }

    override fun encodeUserMessage(content: String): String {
        // Gemini -p is one-shot per spawn; subsequent messages need a new
        // process (host responsibility). This is a placeholder for the
        // common interface — the host does not actually write to stdin.
        return content
    }

    override fun launchArguments(request: CreateSessionRequest, systemPromptText: String?): List<String> {
        // The user's first message is wired through by the host; this method
        // returns the static piece. The actual prompt arg `-p "<text>"` is
        // injected at spawn time by the host so it can replace it on follow-up
        // turns.
        val args = mutableListOf(
            "--output-format", "stream-json",
            "--include-directories", request.projectPath,
            "--skip-trust",
        )
        request.model?.let { args += listOf("--model", it) }
        when (request.mode) {
            "yolo" -> args += listOf("--yolo")
            "auto_edit", "plan", "default" -> args += listOf("--approval-mode", request.mode!!)
            else -> { /* leave default */ }
        }
        return args
    }

    override fun launchEnvironment(): Map<String, String> = mapOf(
        "NO_COLOR" to "1",
        "TERM" to "xterm-256color",
    )

    override fun isWaitingTurnEnd(event: SmoothieEvent): Boolean = event.type == EventType.WAITING

    override fun isLimitReached(event: SmoothieEvent): Boolean {
        if (event.type != EventType.ERROR) return false
        val needle = event.content.lowercase()
        return needle.contains("quota") || needle.contains("rate limit") || needle.contains("exhausted")
    }

    // MARK: - Internal

    private fun parseLine(line: String): SmoothieEvent? {
        val obj = runCatching { json.parseToJsonElement(line) }.getOrNull()?.jsonObject ?: return null
        val type = obj["type"]?.jsonPrimitive?.contentOrNull ?: return null
        val now = nowEpochMillis()

        return when (type) {
            "init" -> {
                lastSessionId = obj["session_id"]?.jsonPrimitive?.contentOrNull ?: lastSessionId
                SmoothieEvent(EventType.THINKING, "starting", null, now)
            }

            "message" -> {
                val role = obj["role"]?.jsonPrimitive?.contentOrNull
                if (role == "user") return null
                val content = obj["content"]?.jsonPrimitive?.contentOrNull ?: ""
                if (content.isBlank()) return null
                // Gemini sends deltas; we render each as its own MESSAGE row.
                // Markdown polish in P7+ can re-coalesce if the UX warrants it.
                SmoothieEvent(EventType.MESSAGE, content, null, now)
            }

            "tool_call", "tool_use" -> {
                val name = obj["tool"]?.jsonPrimitive?.contentOrNull
                    ?: obj["name"]?.jsonPrimitive?.contentOrNull
                    ?: "tool"
                SmoothieEvent(EventType.TOOL_USE, name, null, now)
            }

            "tool_result" -> {
                val content = obj["content"]?.jsonPrimitive?.contentOrNull
                    ?: obj["output"]?.jsonPrimitive?.contentOrNull
                    ?: ""
                SmoothieEvent(EventType.TOOL_RESULT, content, null, now)
            }

            "result" -> {
                val status = obj["status"]?.jsonPrimitive?.contentOrNull
                if (status == "success") {
                    SmoothieEvent(EventType.WAITING, "", null, now)
                } else {
                    val msg = obj["error"]?.jsonPrimitive?.contentOrNull
                        ?: obj["result"]?.jsonPrimitive?.contentOrNull
                        ?: "result: $status"
                    SmoothieEvent(EventType.ERROR, msg, null, now)
                }
            }

            "error" -> {
                val msg = obj["message"]?.jsonPrimitive?.contentOrNull
                    ?: obj["error"]?.jsonPrimitive?.contentOrNull
                    ?: line
                SmoothieEvent(EventType.ERROR, msg, null, now)
            }

            else -> null
        }
    }

    companion object {
        val DEFAULT_FEATURES = ProviderFeatures(
            supportsModelPicker = true,
            supportsReasoningEffort = false,
            supportsModes = true,
            defaultModel = "auto-gemini-3",
            availableModels = listOf(
                "auto-gemini-3",
                "gemini-3-flash-preview",
                "gemini-3.1-flash-lite",
            ),
            availableReasoningEfforts = emptyList(),
            availableModes = listOf("default", "auto_edit", "yolo", "plan"),
            slashCommands = listOf(
                SlashCommand("/help", "Gemini CLI help"),
                SlashCommand("/skills", "Show installed agent skills"),
                SlashCommand("/extensions", "Show installed extensions"),
            ),
        )
    }
}

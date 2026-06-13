package smoothie.adapters

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
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
 * OpenAI Codex CLI parser. Non-interactive invocation:
 *
 *   codex exec --json "<prompt>"
 *
 * Emits a JSONL stream of events. Top-level shape varies by event kind:
 *
 *   { "type": "thread.started", "thread_id": "abc123" }
 *   { "type": "turn.started" }
 *   { "type": "item.completed", "item": { "type": "agent_message", "text": "..." } }
 *   { "type": "item.completed", "item": { "type": "reasoning", "text": "..." } }
 *   { "type": "item.completed", "item": { "type": "command_execution", "command": "ls", "stdout": "..." } }
 *   { "type": "item.completed", "item": { "type": "file_change", "path": "...", "diff": "..." } }
 *   { "type": "item.completed", "item": { "type": "mcp_tool_call", "server": "...", "tool": "...", "result": "..." } }
 *   { "type": "turn.completed" }
 *   { "type": "error", "message": "..." }
 *
 * Item types we map to Smoothie events:
 *   - agent_message     → MESSAGE
 *   - reasoning         → THINKING
 *   - command_execution → TOOL_USE (name = "Bash", input = { command })
 *   - file_change       → FILE_EDIT
 *   - mcp_tool_call     → TOOL_USE (name = MCP tool, input = ...)
 *   - web_search        → TOOL_USE (name = "WebSearch")
 *   - plan_update       → TOOL_USE (name = "Plan")
 *
 * turn.completed maps to WAITING; turn.failed / error map to ERROR.
 *
 * Model selection: Codex defaults to `gpt-5-codex` (the only model exposed
 * via the CLI today). We surface a single model entry so the iOS picker
 * isn't empty.
 */
class CodexAdapter : AdapterParser {
    override val cli: CLIType = CLIType.CODEX
    override val info: AdapterInfo = AdapterInfo(
        cli = CLIType.CODEX,
        installed = true,
        version = null,
        features = DEFAULT_FEATURES,
    )

    private val lineBuffer = LineByteBuffer()
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    override fun ingest(stdoutBytes: ByteArray): List<SmoothieEvent> {
        val now = nowEpochMillis()
        val out = mutableListOf<SmoothieEvent>()
        for (raw in lineBuffer.feed(stdoutBytes)) {
            val trimmed = raw.trim()
            if (trimmed.isEmpty()) continue
            val obj = parseObject(trimmed) ?: continue
            mapEvent(obj, now)?.let { out += it }
        }
        return out
    }

    private fun parseObject(line: String): JsonObject? {
        return try {
            (json.parseToJsonElement(line) as? JsonObject)
        } catch (_: Throwable) {
            null
        }
    }

    private fun mapEvent(obj: JsonObject, now: Long): SmoothieEvent? {
        val type = obj["type"]?.jsonPrimitive?.contentOrNull ?: return null
        return when (type) {
            "turn.completed", "thread.completed" -> SmoothieEvent(EventType.WAITING, "", null, now)
            "turn.failed", "error" -> {
                val msg = obj["message"]?.jsonPrimitive?.contentOrNull
                    ?: obj["error"]?.jsonPrimitive?.contentOrNull
                    ?: "Codex error"
                SmoothieEvent(EventType.ERROR, msg, null, now)
            }
            "item.completed", "item.delta" -> {
                val item = obj["item"]?.jsonObject ?: return null
                mapItem(item, now)
            }
            else -> null
        }
    }

    private fun mapItem(item: JsonObject, now: Long): SmoothieEvent? {
        val kind = item["type"]?.jsonPrimitive?.contentOrNull ?: return null
        return when (kind) {
            "agent_message" -> {
                val text = item["text"]?.jsonPrimitive?.contentOrNull ?: return null
                if (text.isBlank()) null
                else SmoothieEvent(EventType.MESSAGE, text, null, now)
            }
            "reasoning" -> {
                val text = item["text"]?.jsonPrimitive?.contentOrNull ?: return null
                if (text.isBlank()) null
                else SmoothieEvent(EventType.THINKING, text, null, now)
            }
            "command_execution" -> {
                val cmd = item["command"]?.jsonPrimitive?.contentOrNull ?: "command"
                val metadata = buildMap<String, JsonElement> {
                    put("name", JsonPrimitive("Bash"))
                    put("input", buildJsonObject {
                        put("command", JsonPrimitive(cmd))
                    })
                }
                SmoothieEvent(EventType.TOOL_USE, "Bash", metadata, now)
            }
            "file_change" -> {
                val path = item["path"]?.jsonPrimitive?.contentOrNull ?: "file"
                val metadata = buildMap<String, JsonElement> {
                    put("name", JsonPrimitive("Edit"))
                    put("path", JsonPrimitive(path))
                    put("input", buildJsonObject {
                        put("file_path", JsonPrimitive(path))
                    })
                }
                SmoothieEvent(EventType.FILE_EDIT, "Edit", metadata, now)
            }
            "mcp_tool_call" -> {
                val tool = item["tool"]?.jsonPrimitive?.contentOrNull ?: "tool"
                val server = item["server"]?.jsonPrimitive?.contentOrNull
                val metadata = buildMap<String, JsonElement> {
                    put("name", JsonPrimitive(tool))
                    if (server != null) put("input", buildJsonObject {
                        put("server", JsonPrimitive(server))
                    })
                }
                SmoothieEvent(EventType.TOOL_USE, tool, metadata, now)
            }
            "web_search" -> {
                val query = item["query"]?.jsonPrimitive?.contentOrNull ?: ""
                val metadata = buildMap<String, JsonElement> {
                    put("name", JsonPrimitive("WebSearch"))
                    if (query.isNotEmpty()) put("input", buildJsonObject {
                        put("query", JsonPrimitive(query))
                    })
                }
                SmoothieEvent(EventType.TOOL_USE, "WebSearch", metadata, now)
            }
            "plan_update" -> {
                val plan = item["plan"]?.jsonPrimitive?.contentOrNull ?: "plan"
                SmoothieEvent(EventType.TOOL_USE, "Plan",
                    buildMap<String, JsonElement> {
                        put("name", JsonPrimitive("Plan"))
                        put("input", buildJsonObject {
                            put("plan", JsonPrimitive(plan))
                        })
                    }, now)
            }
            else -> null
        }
    }

    override fun encodeUserMessage(content: String): String = content

    override fun launchArguments(request: CreateSessionRequest, systemPromptText: String?): List<String> {
        // The host owns the per-turn `--json "<prompt>"` since the prompt
        // changes with each call. This returns the static base args only.
        val out = mutableListOf("exec", "--json")
        if (request.model != null && request.model.isNotEmpty()) {
            out += listOf("--model", request.model)
        }
        return out
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
            needle.contains("rate_limit") ||
            needle.contains("exhausted") ||
            needle.contains("billing")
    }

    companion object {
        val DEFAULT_FEATURES = ProviderFeatures(
            supportsModelPicker = true,
            supportsReasoningEffort = false,
            supportsModes = false,
            defaultModel = "gpt-5-codex",
            availableModels = listOf("gpt-5-codex", "gpt-4.1-codex"),
            availableReasoningEfforts = emptyList(),
            availableModes = emptyList(),
            slashCommands = listOf(
                SlashCommand("/help", "Codex CLI help"),
                SlashCommand("/login", "Sign in / refresh API key"),
                SlashCommand("/logout", "Sign out"),
            ),
        )
    }
}

private fun buildJsonObject(builder: MutableMap<String, JsonElement>.() -> Unit): JsonObject {
    val map = mutableMapOf<String, JsonElement>()
    map.builder()
    return JsonObject(map)
}

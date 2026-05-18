package smoothie.adapters

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import smoothie.model.AdapterInfo
import smoothie.model.CLIType
import smoothie.model.CreateSessionRequest
import smoothie.model.EventType
import smoothie.model.ProviderFeatures
import smoothie.model.SlashCommand
import smoothie.model.SmoothieEvent
import smoothie.util.nowEpochMillis

class ClaudeAdapter : AdapterParser {
    override val cli: CLIType = CLIType.CLAUDE_CODE
    override val info: AdapterInfo = AdapterInfo(
        cli = CLIType.CLAUDE_CODE,
        installed = true,                     // host-side check overrides this
        version = null,                       // populated by registry on probe
        features = DEFAULT_FEATURES,
    )

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }
    private val buffer = StringBuilder()

    override fun ingest(stdoutBytes: ByteArray): List<SmoothieEvent> {
        buffer.append(stdoutBytes.decodeToString())
        val events = mutableListOf<SmoothieEvent>()
        while (true) {
            val nl = buffer.indexOf('\n')
            if (nl < 0) break
            val line = buffer.substring(0, nl).trim()
            buffer.deleteRange(0, nl + 1)
            if (line.isEmpty()) continue
            parseLine(line)?.let { events += it }
        }
        return events
    }

    override fun encodeUserMessage(content: String): String {
        val payload = buildJsonObject {
            put("type", JsonPrimitive("user"))
            putJsonObject("message") {
                put("role", JsonPrimitive("user"))
                putJsonArray("content") {
                    add(buildJsonObject {
                        put("type", JsonPrimitive("text"))
                        put("text", JsonPrimitive(content))
                    })
                }
            }
        }
        return json.encodeToString(JsonElement.serializer(), payload) + "\n"
    }

    override fun launchArguments(request: CreateSessionRequest, systemPromptText: String?): List<String> {
        val args = mutableListOf(
            "-p",
            "--output-format", "stream-json",
            "--input-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--add-dir", request.projectPath,
        )
        request.model?.let { args += listOf("--model", it) }
        request.reasoningEffort?.let { args += listOf("--effort", it) }
        systemPromptText?.takeIf { it.isNotBlank() }?.let {
            args += listOf("--append-system-prompt", it)
        }
        return args
    }

    override fun launchEnvironment(): Map<String, String> = mapOf(
        "NO_COLOR" to "1",
        "TERM" to "xterm-256color",
    )

    override fun isWaitingTurnEnd(event: SmoothieEvent): Boolean =
        event.type == EventType.WAITING

    override fun isLimitReached(event: SmoothieEvent): Boolean =
        event.type == EventType.LIMIT_REACHED

    // MARK: - Internal parsing

    private fun parseLine(line: String): SmoothieEvent? {
        val obj = runCatching { json.parseToJsonElement(line) }.getOrNull()?.jsonObject ?: return null
        val type = obj["type"]?.jsonPrimitive?.contentOrNull ?: return null
        val now = nowEpochMillis()

        return when (type) {
            "system" -> {
                val subtype = obj["subtype"]?.jsonPrimitive?.contentOrNull
                if (subtype == "init") {
                    SmoothieEvent(EventType.THINKING, "starting", null, now)
                } else null
            }

            "assistant" -> assistantBlocksToEvent(obj, now)

            "user" -> null     // echo of our message — skip

            "result" -> {
                val subtype = obj["subtype"]?.jsonPrimitive?.contentOrNull
                if (subtype == "success") {
                    SmoothieEvent(EventType.WAITING, "", null, now)
                } else {
                    val errText = obj["result"]?.jsonPrimitive?.contentOrNull
                        ?: obj["error"]?.jsonPrimitive?.contentOrNull
                        ?: "result: $subtype"
                    SmoothieEvent(EventType.ERROR, errText, null, now)
                }
            }

            "rate_limit_event" -> {
                val info = obj["rate_limit_info"]?.jsonObject
                val status = info?.get("status")?.jsonPrimitive?.contentOrNull
                if (status == "blocked" || status == "limit_reached") {
                    SmoothieEvent(EventType.LIMIT_REACHED, "Claude rate limit reached", null, now)
                } else null
            }

            "stream_event" -> null    // partial chunks — ignore in v1

            else -> null
        }
    }

    private fun assistantBlocksToEvent(obj: JsonObject, now: Long): SmoothieEvent? {
        val blocks = obj["message"]?.jsonObject?.get("content")?.jsonArray ?: return null
        for (block in blocks) {
            val b = block.jsonObject
            val t = b["type"]?.jsonPrimitive?.contentOrNull ?: continue
            return when (t) {
                "text" -> {
                    val text = b["text"]?.jsonPrimitive?.contentOrNull ?: ""
                    if (text.isBlank()) null else SmoothieEvent(EventType.MESSAGE, text, null, now)
                }
                "thinking" -> {
                    val text = b["thinking"]?.jsonPrimitive?.contentOrNull ?: ""
                    if (text.isBlank()) null else SmoothieEvent(EventType.THINKING, text, null, now)
                }
                "tool_use" -> {
                    val name = b["name"]?.jsonPrimitive?.contentOrNull ?: "tool"
                    val input = b["input"]?.jsonObject
                    val filePath = input?.get("file_path")?.jsonPrimitive?.contentOrNull
                        ?: input?.get("path")?.jsonPrimitive?.contentOrNull
                    val metadata = buildMap<String, JsonElement> {
                        put("name", JsonPrimitive(name))
                        if (filePath != null) put("path", JsonPrimitive(filePath))
                    }
                    val eventType = if (filePath != null &&
                        name in setOf("Edit", "Write", "MultiEdit", "NotebookEdit")
                    ) EventType.FILE_EDIT else EventType.TOOL_USE
                    SmoothieEvent(eventType, name, metadata.ifEmpty { null }, now)
                }
                else -> null
            } ?: continue
        }
        return null
    }

    companion object {
        val DEFAULT_FEATURES = ProviderFeatures(
            supportsModelPicker = true,
            supportsReasoningEffort = true,
            supportsModes = false,
            defaultModel = "sonnet",
            availableModels = listOf("sonnet", "haiku", "opus"),
            availableReasoningEfforts = listOf("low", "medium", "high", "xhigh", "max"),
            availableModes = emptyList(),
            slashCommands = listOf(
                SlashCommand("/clear", "Reset conversation context"),
                SlashCommand("/context", "Show what's in context"),
                SlashCommand("/usage", "Show token usage"),
                SlashCommand("/init", "Initialize CLAUDE.md"),
                SlashCommand("/review", "Review pending changes"),
                SlashCommand("/security-review", "Security review of branch"),
                SlashCommand("/debug", "Toggle debug mode"),
            ),
        )
    }
}

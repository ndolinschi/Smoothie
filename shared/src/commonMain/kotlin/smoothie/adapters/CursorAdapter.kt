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
 * Cursor CLI parser. The CLI speaks ACP (Agent Client Protocol) — a
 * JSON-RPC 2.0 dialect over stdio. We drive it via:
 *
 *   cursor-agent acp
 *
 * Wire format on each stream message: a single JSON-RPC object per line,
 * either a request `{"jsonrpc":"2.0","method":"...","params":{...},"id":N}`,
 * a notification `{"jsonrpc":"2.0","method":"...","params":{...}}`, or a
 * response `{"jsonrpc":"2.0","result":{...},"id":N}`.
 *
 * Methods we receive from the server (cursor-agent → us):
 *   - `session/update` — agent emitted a content block (text, thinking,
 *     tool_call, tool_call_update, plan, etc.) for the current session.
 *   - `session/request_permission` — agent needs the user to approve a
 *     command. We auto-allow for the headless flow; presenting a
 *     real permission UI is a v1.5 deliverable.
 *   - `fs/read_text_file` / `fs/write_text_file` — agent asks us to
 *     read/write a file. The macOS host fulfills these against the
 *     project cwd.
 *
 * Update kinds inside `session/update.update`:
 *   - `agent_message_chunk` — assistant text delta (MESSAGE event with
 *     metadata.partId so iOS coalesces consecutive chunks).
 *   - `agent_thought_chunk` — reasoning delta (THINKING event).
 *   - `tool_call` — new tool invocation (TOOL_USE).
 *   - `tool_call_update` — updates to a tool's status / output.
 *   - `plan` — TODO list / plan update (TOOL_USE with name = "Plan").
 *
 * The host turns user prompts into `session/prompt` requests and ends
 * the turn when it sees a `stopReason` of `end_turn` or `cancelled`.
 *
 * This adapter parses the SERVER → CLIENT line stream — the host owns
 * the CLIENT → SERVER request side (initialize, session/new, prompt,
 * permission responses).
 */
class CursorAdapter : AdapterParser {
    override val cli: CLIType = CLIType.CURSOR
    override val info: AdapterInfo = AdapterInfo(
        cli = CLIType.CURSOR,
        installed = true,
        version = null,
        features = DEFAULT_FEATURES,
    )

    private var buffer: ByteArray = ByteArray(0)
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    override fun ingest(stdoutBytes: ByteArray): List<SmoothieEvent> {
        if (stdoutBytes.isEmpty()) return emptyList()
        buffer += stdoutBytes
        val text = buffer.decodeToString()
        val lines = text.split('\n')
        val complete = if (text.endsWith('\n')) lines else lines.dropLast(1)
        buffer = if (text.endsWith('\n')) ByteArray(0) else lines.last().encodeToByteArray()

        val now = nowEpochMillis()
        val out = mutableListOf<SmoothieEvent>()
        for (raw in complete) {
            val trimmed = raw.trim()
            if (trimmed.isEmpty()) continue
            val obj = parseObject(trimmed) ?: continue
            mapRpc(obj, now)?.let { out += it }
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

    /**
     * Map an ACP RPC frame to a SmoothieEvent. We only consume
     * notifications (and the agent-side `session/update` notifications
     * specifically); responses + requests are owned by the macOS host.
     */
    private fun mapRpc(obj: JsonObject, now: Long): SmoothieEvent? {
        val method = obj["method"]?.jsonPrimitive?.contentOrNull ?: return null
        if (method != "session/update") return null
        val params = obj["params"]?.jsonObject ?: return null
        val update = params["update"]?.jsonObject ?: return null
        val kind = update["sessionUpdate"]?.jsonPrimitive?.contentOrNull
            ?: update["kind"]?.jsonPrimitive?.contentOrNull
            ?: return null
        val partId = update["chunkId"]?.jsonPrimitive?.contentOrNull
            ?: update["toolCallId"]?.jsonPrimitive?.contentOrNull
            ?: update["id"]?.jsonPrimitive?.contentOrNull
        return when (kind) {
            "agent_message_chunk", "assistant_message_chunk" -> {
                val text = extractText(update["content"]) ?: return null
                if (text.isBlank()) null
                else SmoothieEvent(
                    EventType.MESSAGE,
                    text,
                    streamingMetadata(partId),
                    now,
                )
            }
            "agent_thought_chunk", "thinking_chunk" -> {
                val text = extractText(update["content"]) ?: return null
                if (text.isBlank()) null
                else SmoothieEvent(
                    EventType.THINKING,
                    text,
                    streamingMetadata(partId),
                    now,
                )
            }
            "tool_call" -> {
                val tool = update["title"]?.jsonPrimitive?.contentOrNull
                    ?: update["kind"]?.jsonPrimitive?.contentOrNull
                    ?: "tool"
                val metadata = buildMap<String, JsonElement> {
                    put("name", JsonPrimitive(tool))
                    update["rawInput"]?.let { put("input", it) }
                }
                SmoothieEvent(EventType.TOOL_USE, tool, metadata, now)
            }
            "tool_call_update" -> {
                // Status updates carry an outcome string; treat them as
                // TOOL_RESULT so iOS pairs them with the originating
                // TOOL_USE card. The agent's narrative comes through
                // separately as agent_message_chunk events.
                val outcome = update["content"]
                    ?.let { extractText(it) }
                    ?: update["status"]?.jsonPrimitive?.contentOrNull
                    ?: ""
                SmoothieEvent(EventType.TOOL_RESULT, outcome, null, now)
            }
            "plan" -> {
                val text = extractText(update["entries"]) ?: "plan updated"
                val metadata = buildMap<String, JsonElement> {
                    put("name", JsonPrimitive("Plan"))
                    put("input", JsonObject(mapOf("plan" to JsonPrimitive(text))))
                }
                SmoothieEvent(EventType.TOOL_USE, "Plan", metadata, now)
            }
            else -> null
        }
    }

    /**
     * ACP `content` can be a string, an array of content blocks
     * (`[{ type: "text", text: "..." }]`), or a single content block
     * object. Tolerant extraction returns the first plain text we find.
     */
    private fun extractText(element: JsonElement?): String? {
        element ?: return null
        // Plain string content.
        (element as? JsonPrimitive)?.let { return it.contentOrNull }
        // Single content-block object.
        (element as? JsonObject)?.let { obj ->
            obj["text"]?.jsonPrimitive?.contentOrNull?.let { return it }
            return null
        }
        // Array of blocks — concatenate text fields.
        if (element is kotlinx.serialization.json.JsonArray) {
            return element.joinToString("") { item ->
                (item as? JsonObject)?.get("text")?.jsonPrimitive?.contentOrNull ?: ""
            }
        }
        return null
    }

    private fun streamingMetadata(partId: String?): Map<String, JsonElement>? {
        if (partId.isNullOrEmpty()) return null
        return mapOf(
            "partId" to JsonPrimitive(partId),
            "streaming" to JsonPrimitive(true),
        )
    }

    override fun encodeUserMessage(content: String): String {
        // The host owns request framing — this stub is unused for Cursor
        // (the user message becomes a session/prompt JSON-RPC request,
        // not a stdin write).
        return content
    }

    override fun launchArguments(request: CreateSessionRequest, systemPromptText: String?): List<String> {
        // Static base args. The host handles JSON-RPC framing on stdio.
        return listOf("acp")
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
            supportsModelPicker = true,
            supportsReasoningEffort = false,
            supportsModes = false,
            // Cursor CLI defaults to the editor's currently-selected model;
            // we surface a small static list mirroring what the cursor.com
            // docs ship today.
            defaultModel = "auto",
            availableModels = listOf("auto", "sonnet-4.5", "gpt-5", "gpt-5-codex"),
            availableReasoningEfforts = emptyList(),
            availableModes = emptyList(),
            slashCommands = listOf(
                SlashCommand("/help", "Cursor CLI help"),
                SlashCommand("/login", "Authenticate cursor-agent"),
                SlashCommand("/logout", "Sign out"),
            ),
        )
    }
}

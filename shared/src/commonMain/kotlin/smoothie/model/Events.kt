package smoothie.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

@Serializable
enum class EventType {
    MESSAGE,
    THINKING,
    TOOL_USE,
    TOOL_RESULT,
    FILE_EDIT,
    WAITING,
    DONE,
    ERROR,
    LIMIT_REACHED,
    /** Side-channel update of the session's token-budget snapshot.
     *  Payload (a serialised ContextSnapshot) rides in `metadata` so
     *  the existing event encoder doesn't need a special shape. iOS
     *  consumes these in SessionLiveStore.applyContextUpdate before
     *  the visible event ring, so the agent transcript stays clean. */
    CONTEXT_UPDATE,
}

@Serializable
data class SmoothieEvent(
    val type: EventType,
    val content: String,
    val metadata: Map<String, JsonElement>? = null,
    val timestamp: Long,
) {
    /// Convenience for the macOS HTTP encoder: returns the metadata as a
    /// JSON-encoded string, or null if there isn't any. Lets the Swift
    /// side embed structured fields (Bash's `command`, Edit's `old_string`,
    /// etc.) without exporting `JsonElement` to Swift.
    fun metadataJson(): String? {
        val m = metadata ?: return null
        if (m.isEmpty()) return null
        return JsonObject(m).toString()
    }
}

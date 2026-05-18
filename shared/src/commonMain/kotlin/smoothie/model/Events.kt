package smoothie.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

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
}

@Serializable
data class SmoothieEvent(
    val type: EventType,
    val content: String,
    val metadata: Map<String, JsonElement>? = null,
    val timestamp: Long,
)

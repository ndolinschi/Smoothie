package smoothie.model

import kotlinx.serialization.Serializable

@Serializable
enum class SessionState {
    STARTING,
    THINKING,
    WAITING,
    DONE,
    ERROR,
    LIMIT_REACHED,
}

@Serializable
data class SessionDescriptor(
    val id: String,
    val projectPath: String,
    val projectName: String,
    val cli: CLIType,
    val model: String?,
    val reasoningEffort: String?,
    val mode: String?,
    val state: SessionState,
    val createdAt: Long,
)

@Serializable
data class CreateSessionRequest(
    val projectPath: String,
    val cli: CLIType,
    val model: String? = null,
    val reasoningEffort: String? = null,
    val mode: String? = null,
)

@Serializable
data class SendMessageRequest(
    val content: String,
)

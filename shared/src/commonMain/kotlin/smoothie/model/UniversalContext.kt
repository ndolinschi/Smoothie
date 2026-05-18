package smoothie.model

import kotlinx.serialization.Serializable

/// CLI-neutral representation of a session that can be handed off to a different
/// provider. `summary` is the compressed dialog if `ContextCompressor` ran, else
/// the raw transcript truncated. `changedFiles` is collected from `FILE_EDIT`
/// events as the session ran.
@Serializable
data class UniversalContext(
    val projectPath: String,
    val originalTask: String,
    val changedFiles: List<ChangedFile>,
    val transcript: List<DialogTurn>,
    val summary: String?,
)

@Serializable
data class ChangedFile(
    val path: String,
    val operation: String,        // edit / write / create / delete (best-effort from tool name)
)

@Serializable
data class DialogTurn(
    val role: String,             // "user" | "assistant"
    val content: String,
    val timestamp: Long,
)

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
enum class SessionOrigin {
    /// Spawned by Smoothie's daemon — the host is alive in our process tree.
    SMOOTHIE,
    /// Discovered from a CLI's on-disk history (Claude `~/.claude/projects/`,
    /// Gemini `~/.gemini/sessions/`, etc.). The user started this in Terminal.
    /// Driving it requires resuming via the provider's `--resume <id>` flag,
    /// at which point the descriptor flips to `SMOOTHIE`.
    TERMINAL,
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
    /// Provider-side conversation id (Claude `session_id`, Gemini
    /// `session_id`, OpenCode `session.id`). `null` for providers that
    /// don't expose one or before the first event arrives. Used by the
    /// iPhone↔Terminal handoff and Terminal-session discovery.
    val providerSessionId: String? = null,
    val origin: SessionOrigin = SessionOrigin.SMOOTHIE,
    /// P29 §2 — id of the session this one was spawned from. `null`
    /// for top-level sessions (the user started a fresh chat). When
    /// set, the iOS Home view groups this session as a child of its
    /// parent inside the project bucket with a 16pt indent + vertical
    /// guide. Future work plumbs auto-tagging when a user creates a
    /// new session from inside an existing SessionView; today the
    /// field is dormant for sessions the daemon creates on its own.
    val parentSessionId: String? = null,
)

@Serializable
data class CreateSessionRequest(
    val projectPath: String,
    val cli: CLIType,
    val model: String? = null,
    val reasoningEffort: String? = null,
    val mode: String? = null,
    /// When set, the host injects the provider's resume flag so the new
    /// subprocess picks up an existing conversation (Claude `--resume`,
    /// Gemini `--resume`, Antigravity `-c`). Used both by the
    /// iPhone-take-back-from-Terminal flow and by Terminal-session
    /// discovery → resume.
    val providerSessionId: String? = null,
    /// P29 §2 — when set, the spawned Session is tagged as a child of
    /// the named session for tree rendering on iOS. The daemon stores
    /// the id verbatim; no validation that the parent exists.
    val parentSessionId: String? = null,
)

@Serializable
data class SendMessageRequest(
    val content: String,
)

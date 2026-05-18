package smoothie.adapters

import smoothie.model.AdapterInfo
import smoothie.model.CLIType
import smoothie.model.CreateSessionRequest
import smoothie.model.SmoothieEvent

/**
 * Adapter responsibility in v2: *parse the CLI's structured stdout into
 * SmoothieEvents*, *encode user messages into the CLI's stdin format*, and
 * *declare how to spawn the CLI*. The actual process spawning and pipe
 * plumbing lives in Swift on the macOS app side — Kotlin Native's Foundation
 * cinterop is too sharp for production-quality NSTask lifetime management,
 * and Swift's `Foundation.Process` was already proven in v1.
 *
 * Each adapter holds a small line-accumulating buffer because stdout chunks
 * are arbitrary byte boundaries, not line-aligned.
 */
interface AdapterParser {
    val cli: CLIType

    /** Provider feature flags the UI uses to decide which composer controls
     *  to render (model picker, reasoning effort, plan/build/yolo, slash). */
    val info: AdapterInfo

    /** Feed raw stdout bytes. Returns events parsed from complete lines.
     *  Implementations are stateful — they hold a partial-line buffer. */
    fun ingest(stdoutBytes: ByteArray): List<SmoothieEvent>

    /** Encode a user message as the bytes to write to the CLI's stdin. The
     *  returned string already includes the appropriate line terminator. */
    fun encodeUserMessage(content: String): String

    /** Compute command-line arguments for spawning the CLI for this session. */
    fun launchArguments(request: CreateSessionRequest, systemPromptText: String?): List<String>

    /** Environment variables to inject when spawning. Defaults to none. */
    fun launchEnvironment(): Map<String, String> = emptyMap()

    /** Sniff if a specific incoming event signals the agent is now waiting for
     *  the user (i.e. turn ended successfully). Falls back to `false`. */
    fun isWaitingTurnEnd(event: SmoothieEvent): Boolean = false

    /** Sniff if a specific event signals the agent has hit its rate limit. */
    fun isLimitReached(event: SmoothieEvent): Boolean = false
}

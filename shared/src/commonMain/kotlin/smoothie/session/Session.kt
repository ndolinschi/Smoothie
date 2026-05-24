package smoothie.session

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import smoothie.adapters.AdapterParser
import smoothie.model.CLIType
import smoothie.model.CreateSessionRequest
import smoothie.model.EventType
import smoothie.model.SessionDescriptor
import smoothie.model.SessionOrigin
import smoothie.model.SessionState
import smoothie.model.SmoothieEvent
import smoothie.util.nowEpochMillis

/**
 * One live agent session. Pure in-memory state machine over `SmoothieEvent`s
 * emitted by an `AdapterParser`. The process spawning lives in Swift on the
 * Mac side; Swift pumps stdout bytes here via [ingest] and reads encoded user
 * messages via [encodeUserMessage].
 */
class Session(
    val id: String,
    private val request: CreateSessionRequest,
    val projectName: String,
    private val parser: AdapterParser,
    private val createdAt: Long = nowEpochMillis(),
    private val eventCap: Int = 5000,
) {
    private val mutex = Mutex()
    private val _events = mutableListOf<SmoothieEvent>()
    private val _state = MutableStateFlow(SessionState.STARTING)
    private val _live = MutableSharedFlow<SmoothieEvent>(
        replay = 0,
        extraBufferCapacity = 1024,
    )
    private val contextTracker = ContextTracker(request.cli)

    val cli: CLIType get() = request.cli
    val projectPath: String get() = request.projectPath
    val state: StateFlow<SessionState> = _state.asStateFlow()
    val liveEvents: SharedFlow<SmoothieEvent> = _live.asSharedFlow()

    /// Provider-side conversation id. Set initially from the
    /// `CreateSessionRequest.providerSessionId` (for resume flows) and
    /// updated by the host after the first event surfaces a real one
    /// from the CLI's output stream. All mutations go through the mutex
    /// via `setProviderSessionId` or `ingestParsed`, so no volatile
    /// marker is needed; reads from non-mutex callers (Swift hosts) are
    /// a single pointer load.
    private var _providerSessionId: String? = request.providerSessionId
    val providerSessionId: String? get() = _providerSessionId

    /// Allow the host layer to update the provider session id once the
    /// adapter has parsed it from the CLI's first event (Claude's
    /// stream-json `init`, Gemini's first JSONL frame, etc.).
    fun setProviderSessionId(id: String?) {
        _providerSessionId = id
    }

    suspend fun snapshot(): List<SmoothieEvent> = mutex.withLock { _events.toList() }

    suspend fun descriptor(): SessionDescriptor = mutex.withLock {
        SessionDescriptor(
            id = id,
            projectPath = request.projectPath,
            projectName = projectName,
            cli = request.cli,
            model = request.model,
            reasoningEffort = request.reasoningEffort,
            mode = request.mode,
            state = _state.value,
            createdAt = createdAt,
            providerSessionId = _providerSessionId,
            origin = SessionOrigin.SMOOTHIE,
            parentSessionId = request.parentSessionId,
        )
    }

    /** Pump stdout bytes from the child process. Returns the events produced
     *  so the caller can also forward them (e.g. for logging). */
    suspend fun ingest(stdoutBytes: ByteArray): List<SmoothieEvent> {
        return ingestParsed(parser.ingest(stdoutBytes))
    }

    /** Convenience for Swift hosts. Decodes UTF-8 text on the Kotlin side. */
    suspend fun ingestText(text: String): List<SmoothieEvent> {
        return ingestParsed(parser.ingestText(text))
    }

    private suspend fun ingestParsed(parsed: List<SmoothieEvent>): List<SmoothieEvent> {
        if (parsed.isEmpty()) return parsed
        val snapshotForUpdate: ContextSnapshot
        mutex.withLock {
            for (event in parsed) {
                _events += event
                if (_events.size > eventCap) {
                    _events.subList(0, _events.size - eventCap).clear()
                }
                updateStateForEvent(event)
                addToConversationIfContentful(event)
            }
            // Pick up the parser's most recently seen provider session id
            // (Claude system.init, Gemini init, etc.) so the descriptor
            // returned to iOS carries the resume id once it's known.
            parser.lastSessionId?.let { _providerSessionId = it }
            // Capture the snapshot INSIDE the lock — emitting the
            // CONTEXT_UPDATE then happens outside so we don't re-enter
            // the mutex (kotlinx.coroutines `Mutex` is not re-entrant
            // and would deadlock the suspending caller).
            snapshotForUpdate = contextTracker.snapshot()
        }
        for (event in parsed) _live.emit(event)
        // After publishing the visible events, fire one trailing
        // CONTEXT_UPDATE so iOS's status footer percent ring stays in
        // sync. No debouncing in v1 — bursty streams will fire many
        // updates but the iOS side just overwrites the snapshot.
        emitContextUpdateWithSnapshot(snapshotForUpdate)
        return parsed
    }

    /** Charge an event's content against the conversation budget when
     *  it actually carries text the model will see again. WAITING /
     *  DONE / ERROR / LIMIT_REACHED / CONTEXT_UPDATE are state /
     *  side-channel signals — they don't enter the model's context. */
    private fun addToConversationIfContentful(event: SmoothieEvent) {
        when (event.type) {
            EventType.MESSAGE, EventType.THINKING, EventType.TOOL_USE,
            EventType.TOOL_RESULT, EventType.FILE_EDIT -> {
                contextTracker.addConversation(event.content)
            }
            EventType.WAITING, EventType.DONE, EventType.ERROR,
            EventType.LIMIT_REACHED, EventType.CONTEXT_UPDATE -> Unit
        }
    }

    /** Emit a CONTEXT_UPDATE event with an already-captured snapshot.
     *  Callers must capture the snapshot under the mutex themselves
     *  (the kotlinx.coroutines Mutex isn't re-entrant). Side-channel
     *  only — does NOT push into `_events`; iOS's SessionLiveStore
     *  filters CONTEXT_UPDATE before the visible event ring.
     *
     *  Builds the JsonObject by hand instead of going through
     *  `kotlinx.serialization`'s reflection-less serializer. The earlier
     *  approach silently no-op'd on Kotlin/Native — the daemon log
     *  showed zero context_update events on the SSE stream even though
     *  `_live.emit` for normal events was working. Manual construction
     *  side-steps whatever the issue was.
     */
    private suspend fun emitContextUpdateWithSnapshot(snapshot: ContextSnapshot) {
        val breakdownArray = JsonArray(snapshot.breakdown.map { cat ->
            JsonObject(mapOf(
                "id" to JsonPrimitive(cat.id),
                "label" to JsonPrimitive(cat.label),
                "tokens" to JsonPrimitive(cat.tokens),
            ))
        })
        val snapshotJson = JsonObject(mapOf(
            "total" to JsonPrimitive(snapshot.total),
            "max" to JsonPrimitive(snapshot.max),
            "breakdown" to breakdownArray,
        ))
        val event = SmoothieEvent(
            type = EventType.CONTEXT_UPDATE,
            content = "",
            metadata = mapOf("snapshot" to snapshotJson),
            timestamp = nowEpochMillis(),
        )
        _live.emit(event)
    }

    /** Read the current token-budget snapshot. Used by the HTTP
     *  `/sessions/:id/context` route so a freshly-mounted iOS session
     *  can fetch initial state without waiting for the next ingest. */
    suspend fun contextSnapshot(): ContextSnapshot = mutex.withLock { contextTracker.snapshot() }

    /** Seed the system-prompt category from the macOS spawn path. */
    suspend fun seedSystemPrompt(text: String) {
        val snapshotForUpdate: ContextSnapshot
        mutex.withLock {
            contextTracker.seedSystemPrompt(text)
            snapshotForUpdate = contextTracker.snapshot()
        }
        emitContextUpdateWithSnapshot(snapshotForUpdate)
    }

    /** Swift-friendly subscription: invokes [onEvent] for every live event
     *  on a background dispatcher until [Subscription.close] is called.
     *  The HTTP SSE route uses this to forward events. */
    fun subscribeForSwift(onEvent: (SmoothieEvent) -> Unit): Subscription {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val job: Job = scope.launch {
            _live.asSharedFlow().collect { onEvent(it) }
        }
        return object : Subscription {
            override fun close() {
                job.cancel()
                scope.cancel()
            }
        }
    }

    /** Mark the user as having sent a message. Bumps state to THINKING so the
     *  UI shows the right indicator before any events arrive. */
    suspend fun noteUserMessageSent() {
        mutex.withLock { _state.update { SessionState.THINKING } }
    }

    /** Encode a user message into the bytes the CLI's stdin expects. */
    fun encodeUserMessage(content: String): String = parser.encodeUserMessage(content)

    /** Convenience for hosts that need to push an in-flight text part to
     *  the visible event stream. The metadata carries the part id so the
     *  iOS client can coalesce successive updates to the same part into
     *  one bubble instead of N stacked copies. Used by OpenCodeServeHost
     *  to stream `message.part.delta` text as it arrives. */
    suspend fun injectStreamingText(partId: String, text: String, timestamp: Long) {
        val metadata = mapOf<String, JsonElement>(
            "partId" to JsonPrimitive(partId),
            "streaming" to JsonPrimitive(true),
        )
        injectEvent(SmoothieEvent(EventType.MESSAGE, text, metadata, timestamp))
    }

    /** Inject a synthetic event (e.g. when Swift side detects process exit). */
    suspend fun injectEvent(event: SmoothieEvent) {
        val snapshotForUpdate: ContextSnapshot
        mutex.withLock {
            _events += event
            updateStateForEvent(event)
            addToConversationIfContentful(event)
            snapshotForUpdate = contextTracker.snapshot()
        }
        _live.emit(event)
        emitContextUpdateWithSnapshot(snapshotForUpdate)
    }

    /** Mark the session ended (process exited cleanly). */
    suspend fun markDone() {
        mutex.withLock { _state.update { SessionState.DONE } }
        _live.emit(SmoothieEvent(EventType.DONE, "session ended", null, nowEpochMillis()))
    }

    /** Mark the session errored (process crashed / non-zero exit). */
    suspend fun markError(message: String) {
        mutex.withLock { _state.update { SessionState.ERROR } }
        _live.emit(SmoothieEvent(EventType.ERROR, message, null, nowEpochMillis()))
    }

    private fun updateStateForEvent(event: SmoothieEvent) {
        when (event.type) {
            EventType.WAITING -> _state.update { SessionState.WAITING }
            EventType.DONE -> _state.update { SessionState.DONE }
            EventType.ERROR -> _state.update { SessionState.ERROR }
            EventType.LIMIT_REACHED -> _state.update { SessionState.LIMIT_REACHED }
            EventType.MESSAGE, EventType.THINKING, EventType.TOOL_USE,
            EventType.TOOL_RESULT, EventType.FILE_EDIT -> _state.update { SessionState.THINKING }
            EventType.CONTEXT_UPDATE -> Unit // side-channel; never moves state
        }
    }
}

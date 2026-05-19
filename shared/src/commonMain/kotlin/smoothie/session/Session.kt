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
import smoothie.adapters.AdapterParser
import smoothie.model.CLIType
import smoothie.model.CreateSessionRequest
import smoothie.model.EventType
import smoothie.model.SessionDescriptor
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

    val cli: CLIType get() = request.cli
    val projectPath: String get() = request.projectPath
    val state: StateFlow<SessionState> = _state.asStateFlow()
    val liveEvents: SharedFlow<SmoothieEvent> = _live.asSharedFlow()

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
        mutex.withLock {
            for (event in parsed) {
                _events += event
                if (_events.size > eventCap) {
                    _events.subList(0, _events.size - eventCap).clear()
                }
                updateStateForEvent(event)
            }
        }
        for (event in parsed) _live.emit(event)
        return parsed
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

    /** Inject a synthetic event (e.g. when Swift side detects process exit). */
    suspend fun injectEvent(event: SmoothieEvent) {
        mutex.withLock {
            _events += event
            updateStateForEvent(event)
        }
        _live.emit(event)
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
        }
    }
}

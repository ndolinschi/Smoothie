package smoothie.sse

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import smoothie.model.SmoothieEvent

/**
 * Fan-out broker between Session emitters and HTTP SSE subscribers. Each
 * session id has its own shared flow; the Swift HTTP layer subscribes per
 * incoming GET /sessions/:id/stream connection.
 *
 * Replay buffer is intentionally zero — subscribers should call
 * [Session.snapshot] for backlog and rely on this flow for live updates.
 */
class SSEBroker {
    private val mutex = Mutex()
    private val flows = mutableMapOf<String, MutableSharedFlow<SmoothieEvent>>()

    suspend fun publish(sessionId: String, event: SmoothieEvent) {
        val flow = mutex.withLock { flows.getOrPut(sessionId) { newFlow() } }
        flow.emit(event)
    }

    suspend fun stream(sessionId: String): Flow<SmoothieEvent> {
        val flow = mutex.withLock { flows.getOrPut(sessionId) { newFlow() } }
        return flow.asSharedFlow()
    }

    suspend fun drop(sessionId: String) = mutex.withLock {
        flows.remove(sessionId)
        Unit
    }

    private fun newFlow() = MutableSharedFlow<SmoothieEvent>(
        replay = 0,
        extraBufferCapacity = 1024,
    )
}

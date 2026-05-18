package smoothie.session

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import smoothie.adapters.AdapterParser
import smoothie.adapters.AdapterRegistry
import smoothie.model.CreateSessionRequest
import smoothie.model.SessionDescriptor
import smoothie.util.nowEpochMillis

/**
 * In-memory registry of live sessions. Mutex-guarded (concurrent map ops only).
 * Lifecycle of the underlying CLI process is owned by Swift on the macOS side —
 * SessionManager holds the parsed event stream and state, not the OS handles.
 */
class SessionManager(
    private val registry: AdapterRegistry,
) {
    private val mutex = Mutex()
    private val sessions = mutableMapOf<String, Session>()
    private val _activeIds = MutableStateFlow<List<String>>(emptyList())
    val activeIds: StateFlow<List<String>> = _activeIds.asStateFlow()

    suspend fun create(request: CreateSessionRequest): Session {
        val parser: AdapterParser = registry.parserFor(request.cli)
            ?: throw IllegalArgumentException("No adapter for ${request.cli}")
        val id = randomSessionId()
        val projectName = request.projectPath.substringAfterLast('/').ifEmpty { request.projectPath }
        val session = Session(
            id = id,
            request = request,
            projectName = projectName,
            parser = parser,
            createdAt = nowEpochMillis(),
        )
        mutex.withLock {
            sessions[id] = session
            _activeIds.value = sessions.keys.toList()
        }
        return session
    }

    suspend fun get(id: String): Session? = mutex.withLock { sessions[id] }

    suspend fun list(): List<SessionDescriptor> {
        val snapshot = mutex.withLock { sessions.values.toList() }
        return snapshot.map { it.descriptor() }
    }

    suspend fun remove(id: String): Session? = mutex.withLock {
        val removed = sessions.remove(id)
        _activeIds.value = sessions.keys.toList()
        removed
    }

    suspend fun clear() = mutex.withLock {
        sessions.clear()
        _activeIds.value = emptyList()
    }
}

private fun randomSessionId(): String {
    // 16 random bytes → 32 hex chars. Good enough for in-memory uniqueness.
    val bytes = ByteArray(16)
    smoothie.pairing.SecureRandom.fill(bytes)
    return bytes.joinToString("") { (it.toInt() and 0xFF).toString(16).padStart(2, '0') }
}

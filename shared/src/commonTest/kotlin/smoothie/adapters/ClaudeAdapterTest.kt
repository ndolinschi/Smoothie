package smoothie.adapters

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import smoothie.model.EventType

/**
 * Parser tests against recorded shapes of Claude Code's stream-json
 * output. The adapter is stateless about process lifecycle, so each
 * test drives it purely through `ingest` bytes.
 */
class ClaudeAdapterTest {

    private fun ingest(adapter: ClaudeAdapter, text: String) =
        adapter.ingest(text.encodeToByteArray())

    @Test
    fun initEventCapturesSessionIdAndEmitsThinking() {
        val adapter = ClaudeAdapter()
        val events = ingest(
            adapter,
            """{"type":"system","subtype":"init","session_id":"abc-123"}""" + "\n"
        )
        assertEquals(1, events.size)
        assertEquals(EventType.THINKING, events[0].type)
        assertEquals("abc-123", adapter.lastSessionId)
    }

    @Test
    fun assistantMessageWithMultipleBlocksEmitsOneEventPerBlock() {
        val adapter = ClaudeAdapter()
        val line = """
            {"type":"assistant","message":{"content":[
              {"type":"thinking","thinking":"let me look"},
              {"type":"text","text":"Here is the plan."},
              {"type":"tool_use","name":"Bash","input":{"command":"ls"}}
            ]}}
        """.trimIndent().replace("\n", "") + "\n"
        val events = ingest(adapter, line)
        assertEquals(3, events.size)
        assertEquals(EventType.THINKING, events[0].type)
        assertEquals("let me look", events[0].content)
        assertEquals(EventType.MESSAGE, events[1].type)
        assertEquals("Here is the plan.", events[1].content)
        assertEquals(EventType.TOOL_USE, events[2].type)
        assertEquals("Bash", events[2].content)
    }

    @Test
    fun editToolWithFilePathMapsToFileEdit() {
        val adapter = ClaudeAdapter()
        val line = """{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/tmp/a.swift"}}]}}""" + "\n"
        val events = ingest(adapter, line)
        assertEquals(1, events.size)
        assertEquals(EventType.FILE_EDIT, events[0].type)
        assertEquals("Edit", events[0].content)
    }

    @Test
    fun resultSuccessEmitsWaiting() {
        val adapter = ClaudeAdapter()
        val events = ingest(adapter, """{"type":"result","subtype":"success"}""" + "\n")
        assertEquals(1, events.size)
        assertEquals(EventType.WAITING, events[0].type)
    }

    @Test
    fun resultFailureEmitsErrorWithDetail() {
        val adapter = ClaudeAdapter()
        val events = ingest(
            adapter,
            """{"type":"result","subtype":"error_during_execution","result":"boom"}""" + "\n"
        )
        assertEquals(1, events.size)
        assertEquals(EventType.ERROR, events[0].type)
        assertEquals("boom", events[0].content)
    }

    @Test
    fun rateLimitBlockedEmitsLimitReached() {
        val adapter = ClaudeAdapter()
        val events = ingest(
            adapter,
            """{"type":"rate_limit_event","rate_limit_info":{"status":"blocked"}}""" + "\n"
        )
        assertEquals(1, events.size)
        assertEquals(EventType.LIMIT_REACHED, events[0].type)
    }

    @Test
    fun partialLineIsHeldUntilTheNewlineArrives() {
        val adapter = ClaudeAdapter()
        val whole = """{"type":"result","subtype":"success"}"""
        val first = ingest(adapter, whole.substring(0, 20))
        assertTrue(first.isEmpty(), "no newline yet — nothing should parse")
        val second = ingest(adapter, whole.substring(20) + "\n")
        assertEquals(1, second.size)
        assertEquals(EventType.WAITING, second[0].type)
    }

    @Test
    fun userEchoAndUnknownTypesAreSkipped() {
        val adapter = ClaudeAdapter()
        val events = ingest(
            adapter,
            """{"type":"user","message":{}}""" + "\n" +
                """{"type":"stream_event","event":{}}""" + "\n" +
                "not json at all\n"
        )
        assertTrue(events.isEmpty())
    }
}

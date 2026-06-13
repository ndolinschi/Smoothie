package smoothie.adapters

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import smoothie.model.EventType

class CodexAdapterTest {

    private fun ingest(a: CodexAdapter, s: String) = a.ingest(s.encodeToByteArray())

    @Test
    fun agentMessageItemBecomesMessage() {
        val a = CodexAdapter()
        val events = ingest(
            a,
            """{"type":"item.completed","item":{"type":"agent_message","text":"Done."}}""" + "\n"
        )
        assertEquals(1, events.size)
        assertEquals(EventType.MESSAGE, events[0].type)
        assertEquals("Done.", events[0].content)
    }

    @Test
    fun commandExecutionBecomesToolUse() {
        val a = CodexAdapter()
        val events = ingest(
            a,
            """{"type":"item.completed","item":{"type":"command_execution","command":"ls -la"}}""" + "\n"
        )
        assertEquals(1, events.size)
        assertEquals(EventType.TOOL_USE, events[0].type)
        assertEquals("Bash", events[0].content)
    }

    @Test
    fun fileChangeBecomesFileEdit() {
        val a = CodexAdapter()
        val events = ingest(
            a,
            """{"type":"item.completed","item":{"type":"file_change","path":"/tmp/x.swift"}}""" + "\n"
        )
        assertEquals(1, events.size)
        assertEquals(EventType.FILE_EDIT, events[0].type)
    }

    @Test
    fun turnCompletedBecomesWaiting() {
        val a = CodexAdapter()
        val events = ingest(a, """{"type":"turn.completed"}""" + "\n")
        assertEquals(listOf(EventType.WAITING), events.map { it.type })
    }

    @Test
    fun errorBecomesError() {
        val a = CodexAdapter()
        val events = ingest(a, """{"type":"error","message":"boom"}""" + "\n")
        assertEquals(1, events.size)
        assertEquals(EventType.ERROR, events[0].type)
        assertEquals("boom", events[0].content)
    }

    @Test
    fun multiByteAgentMessageSplitAcrossChunksSurvives() {
        val a = CodexAdapter()
        // Emoji + accented text in the message body, split byte-by-byte.
        val whole = (
            """{"type":"item.completed","item":{"type":"agent_message","text":"готово 🎉"}}""" + "\n"
            ).encodeToByteArray()
        var last: List<smoothie.model.SmoothieEvent> = emptyList()
        for (b in whole) {
            last = a.ingest(byteArrayOf(b))
            if (last.isNotEmpty()) break
        }
        assertEquals(1, last.size)
        assertEquals("готово 🎉", last[0].content)
    }

    @Test
    fun partialLineHeldUntilNewline() {
        val a = CodexAdapter()
        val line = """{"type":"turn.completed"}"""
        assertTrue(ingest(a, line.substring(0, 10)).isEmpty())
        assertEquals(1, ingest(a, line.substring(10) + "\n").size)
    }
}

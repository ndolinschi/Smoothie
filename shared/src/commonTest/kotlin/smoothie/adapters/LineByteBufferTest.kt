package smoothie.adapters

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class LineByteBufferTest {

    private fun bytes(s: String) = s.encodeToByteArray()

    @Test
    fun emptyChunkYieldsNothing() {
        val buf = LineByteBuffer()
        assertTrue(buf.feed(ByteArray(0)).isEmpty())
    }

    @Test
    fun singleCompleteLine() {
        val buf = LineByteBuffer()
        assertEquals(listOf("hello"), buf.feed(bytes("hello\n")))
    }

    @Test
    fun multipleLinesInOneChunk() {
        val buf = LineByteBuffer()
        assertEquals(listOf("a", "b", "c"), buf.feed(bytes("a\nb\nc\n")))
    }

    @Test
    fun trailingPartialLineIsHeldUntilCompleted() {
        val buf = LineByteBuffer()
        assertEquals(listOf("first"), buf.feed(bytes("first\nsec")))
        assertEquals(listOf("second"), buf.feed(bytes("ond\n")))
    }

    @Test
    fun noNewlineBuffersEverything() {
        val buf = LineByteBuffer()
        assertTrue(buf.feed(bytes("partial")).isEmpty())
        assertEquals(listOf("partial line"), buf.feed(bytes(" line\n")))
    }

    @Test
    fun blankLinesArePreserved() {
        val buf = LineByteBuffer()
        // The accumulator returns blanks; parsers skip them themselves.
        assertEquals(listOf("a", "", "b"), buf.feed(bytes("a\n\nb\n")))
    }

    @Test
    fun multiByteCodepointSplitAcrossChunksSurvives() {
        val buf = LineByteBuffer()
        // "café 😀" — the é (2 bytes) and the emoji (4 bytes) are exactly
        // the codepoints the old StringBuilder-decode-per-chunk path
        // corrupted when a read landed mid-codepoint.
        val full = "café 😀 done".encodeToByteArray()
        val nl = "\n".encodeToByteArray()
        val whole = full + nl
        // Split at every byte boundary and feed one byte at a time; the
        // line must reassemble byte-perfectly regardless of where the cut
        // lands inside a multi-byte sequence.
        var collected: List<String> = emptyList()
        for (b in whole) {
            collected = buf.feed(byteArrayOf(b))
            if (collected.isNotEmpty()) break
        }
        assertEquals(listOf("café 😀 done"), collected)
    }

    @Test
    fun cyrillicSplitAcrossTwoChunks() {
        val buf = LineByteBuffer()
        val line = "Привет мир".encodeToByteArray() + "\n".encodeToByteArray()
        // Cut in the middle of the first two-byte Cyrillic character.
        val firstHalf = line.copyOfRange(0, 1)
        val secondHalf = line.copyOfRange(1, line.size)
        assertTrue(buf.feed(firstHalf).isEmpty())
        assertEquals(listOf("Привет мир"), buf.feed(secondHalf))
    }

    @Test
    fun crlfIsLeftForCallerToTrim() {
        val buf = LineByteBuffer()
        // The buffer only splits on \n; a trailing \r rides along and the
        // parser's .trim() removes it. Verifies we don't accidentally eat
        // or choke on Windows line endings.
        assertEquals(listOf("line\r"), buf.feed(bytes("line\r\n")))
    }
}

package smoothie.adapters

/**
 * Accumulates raw stdout bytes and yields only *complete* lines, decoded
 * as UTF-8 once per line. Holding the buffer as bytes (not a String) is
 * the whole point: a multi-byte UTF-8 codepoint — an emoji, CJK, Cyrillic,
 * an accented Latin character — can be split across two pipe reads, and
 * decoding each raw chunk eagerly would corrupt or drop that codepoint.
 * By splitting on the `\n` byte and decoding each line only once both
 * halves have arrived, the boundary is invisible to the parser.
 *
 * Every CLI we wrap emits one structured object per line (stream-json,
 * JSONL, ACP frames), so line-framing is the natural unit. The trailing
 * partial line (bytes after the last `\n`) stays in the buffer for the
 * next [feed] call.
 *
 * Not thread-safe — callers serialise `ingest` through `Session`'s mutex
 * or the host's MainActor, so a single accumulator per parser is fine.
 */
internal class LineByteBuffer {
    private var bytes: ByteArray = ByteArray(0)

    private companion object {
        const val NEWLINE: Byte = 0x0A // '\n'
    }

    /**
     * Append [chunk] and return every complete line it completed, in order,
     * each already UTF-8 decoded and with no trailing newline. Lines that
     * are empty after the split are still returned (callers skip blanks);
     * a chunk with no newline returns an empty list and buffers the bytes.
     */
    fun feed(chunk: ByteArray): List<String> {
        if (chunk.isEmpty()) return emptyList()
        bytes += chunk
        var start = 0
        var out: MutableList<String>? = null
        var i = 0
        while (i < bytes.size) {
            if (bytes[i] == NEWLINE) {
                val line = bytes.decodeToString(start, i)
                if (out == null) out = mutableListOf()
                out.add(line)
                start = i + 1
            }
            i++
        }
        // Keep the trailing partial line (everything after the last `\n`).
        bytes = if (start == 0) bytes else bytes.copyOfRange(start, bytes.size)
        return out ?: emptyList()
    }
}

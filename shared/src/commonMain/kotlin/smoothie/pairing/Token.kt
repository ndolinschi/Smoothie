package smoothie.pairing

import kotlinx.serialization.Serializable

/// 32-byte random token, base64url-encoded for transport in the QR payload
/// and the iOS `Authorization: Bearer …` header.
object PairingToken {
    fun generate(): String {
        val bytes = ByteArray(32)
        SecureRandom.fill(bytes)
        return base64UrlEncode(bytes)
    }
}

@Serializable
data class QRPayload(
    val host: String,
    val port: Int,
    val token: String,
    /// Connection scheme — `http` for local/Tailscale binds, `https` for
    /// public tunnels (Cloudflare etc.). Optional on the wire for
    /// backward compatibility: a missing `scheme` parameter parses as
    /// `http` so existing QR codes keep working.
    val scheme: String = "http",
) {
    fun toURL(): String {
        val schemeParam = if (scheme == "http") "" else "&scheme=${scheme.urlPercentEncode()}"
        return "smoothie://pair?host=${host.urlPercentEncode()}&port=$port&token=${token.urlPercentEncode()}$schemeParam"
    }

    companion object {
        /// Parse a `smoothie://pair?...` URL. Returns null on malformed input.
        fun parse(url: String): QRPayload? {
            val withoutScheme = url.removePrefix("smoothie://pair?")
            if (withoutScheme == url) return null
            val params = withoutScheme.split('&').mapNotNull { kv ->
                val eq = kv.indexOf('=')
                if (eq < 0) null else kv.substring(0, eq) to urlPercentDecode(kv.substring(eq + 1))
            }.toMap()
            val host = params["host"] ?: return null
            val port = params["port"]?.toIntOrNull() ?: return null
            val token = params["token"] ?: return null
            val scheme = params["scheme"]?.takeIf { it == "http" || it == "https" } ?: "http"
            return QRPayload(host, port, token, scheme)
        }
    }
}

// MARK: - Encoding helpers

private val URL_ALLOWED: Set<Char> = (('A'..'Z') + ('a'..'z') + ('0'..'9') + listOf('-', '.', '_', '~')).toSet()

private fun String.urlPercentEncode(): String = buildString {
    for (ch in this@urlPercentEncode) {
        if (ch in URL_ALLOWED) append(ch)
        else {
            val bytes = ch.toString().encodeToByteArray()
            for (b in bytes) {
                val v = b.toInt() and 0xFF
                append('%')
                append(((v shr 4) and 0xF).toHexDigit())
                append((v and 0xF).toHexDigit())
            }
        }
    }
}

private fun urlPercentDecode(s: String): String {
    val out = ByteArray(s.length)
    var written = 0
    var i = 0
    while (i < s.length) {
        val c = s[i]
        if (c == '%' && i + 2 < s.length) {
            val hi = s[i + 1].hexValue()
            val lo = s[i + 2].hexValue()
            if (hi >= 0 && lo >= 0) {
                out[written++] = ((hi shl 4) or lo).toByte()
                i += 3
                continue
            }
        }
        if (c == '+') {
            out[written++] = ' '.code.toByte()
        } else {
            for (b in c.toString().encodeToByteArray()) {
                out[written++] = b
            }
        }
        i++
    }
    return out.decodeToString(0, written)
}

private fun Int.toHexDigit(): Char {
    val v = this and 0xF
    return if (v < 10) ('0'.code + v).toChar() else ('A'.code + (v - 10)).toChar()
}

private fun Char.hexValue(): Int = when (this) {
    in '0'..'9' -> this - '0'
    in 'a'..'f' -> this - 'a' + 10
    in 'A'..'F' -> this - 'A' + 10
    else -> -1
}

private val BASE64_URL: CharArray =
    ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_").toCharArray()

internal fun base64UrlEncode(bytes: ByteArray): String {
    val sb = StringBuilder(((bytes.size * 4) / 3) + 4)
    var i = 0
    while (i + 3 <= bytes.size) {
        val b0 = bytes[i].toInt() and 0xFF
        val b1 = bytes[i + 1].toInt() and 0xFF
        val b2 = bytes[i + 2].toInt() and 0xFF
        sb.append(BASE64_URL[b0 shr 2])
        sb.append(BASE64_URL[((b0 and 0x03) shl 4) or (b1 shr 4)])
        sb.append(BASE64_URL[((b1 and 0x0F) shl 2) or (b2 shr 6)])
        sb.append(BASE64_URL[b2 and 0x3F])
        i += 3
    }
    val remaining = bytes.size - i
    if (remaining == 1) {
        val b0 = bytes[i].toInt() and 0xFF
        sb.append(BASE64_URL[b0 shr 2])
        sb.append(BASE64_URL[(b0 and 0x03) shl 4])
    } else if (remaining == 2) {
        val b0 = bytes[i].toInt() and 0xFF
        val b1 = bytes[i + 1].toInt() and 0xFF
        sb.append(BASE64_URL[b0 shr 2])
        sb.append(BASE64_URL[((b0 and 0x03) shl 4) or (b1 shr 4)])
        sb.append(BASE64_URL[(b1 and 0x0F) shl 2])
    }
    return sb.toString()
}

package smoothie.pairing

internal expect object SecureRandom {
    fun fill(bytes: ByteArray)
}

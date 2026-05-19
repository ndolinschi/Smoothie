package smoothie.session

/** Stable handle Swift code uses to tear down a Kotlin Flow subscription. */
interface Subscription {
    fun close()
}

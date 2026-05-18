package smoothie.util

import kotlinx.cinterop.ExperimentalForeignApi
import platform.Foundation.NSDate
import platform.Foundation.timeIntervalSince1970

@OptIn(ExperimentalForeignApi::class)
internal actual fun nowEpochMillis(): Long =
    (NSDate().timeIntervalSince1970 * 1000.0).toLong()

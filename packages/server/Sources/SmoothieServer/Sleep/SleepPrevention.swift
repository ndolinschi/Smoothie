import Foundation
import IOKit
import IOKit.pwr_mgt

/// Prevents system sleep while a Smoothie session is active. The screen is
/// allowed to sleep — only the system-idle assertion is held.
final class SleepPrevention {
    private var assertionID: IOPMAssertionID = 0
    private var active = false

    func enable(reason: String = "Smoothie agent active") {
        guard !active else { return }
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        if result == kIOReturnSuccess { active = true }
    }

    func disable() {
        guard active else { return }
        IOPMAssertionRelease(assertionID)
        active = false
    }

    deinit { disable() }
}

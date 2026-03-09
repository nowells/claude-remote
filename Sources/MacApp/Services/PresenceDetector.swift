import Foundation
import IOKit
import CoreGraphics

/// Determines whether the user is physically present at their Mac.
/// Combines system idle time (IOKit HIDIdleTime) with screen-lock state (CoreGraphics session).
final class PresenceDetector {

    // MARK: - Public API

    /// Returns `true` if the user is considered "at desk":
    /// screen is not locked AND system idle time is below the configured threshold.
    func isAtDesk(idleThreshold: TimeInterval = Config.idleThresholdSeconds) -> Bool {
        guard !isScreenLocked() else { return false }
        return idleTimeSeconds() < idleThreshold
    }

    // MARK: - Idle Time

    /// Returns the number of seconds since the last HID (keyboard/mouse) event.
    func idleTimeSeconds() -> TimeInterval {
        var iter: io_iterator_t = 0
        let matchingDict = IOServiceMatching("IOHIDSystem")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iter) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iter) }

        let entry = IOIteratorNext(iter)
        guard entry != IO_OBJECT_NULL else { return 0 }
        defer { IOObjectRelease(entry) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any],
              let idleNs = props["HIDIdleTime"] as? Int64 else { return 0 }

        return TimeInterval(idleNs) / 1_000_000_000.0
    }

    // MARK: - Screen Lock

    /// Returns `true` if the screen saver / login window is active.
    func isScreenLocked() -> Bool {
        guard let sessionDict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        // CGSSessionScreenIsLocked is set when the screen is locked
        if let locked = sessionDict["CGSSessionScreenIsLocked"] as? Bool {
            return locked
        }
        // Older macOS key
        if let locked = sessionDict["kCGSSessionOnConsoleKey"] as? Bool {
            return !locked
        }
        return false
    }
}

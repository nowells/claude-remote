import Foundation
import CoreGraphics

/// Determines whether the user is physically present at their Mac.
/// Combines system idle time (CoreGraphics event source) with screen-lock state (CoreGraphics session).
final class PresenceDetector {

    // MARK: - Public API

    /// Returns `true` if the user is considered "at desk":
    /// screen is not locked AND system idle time is below the configured threshold.
    func isAtDesk(idleThreshold: TimeInterval = Config.idleThresholdSeconds) -> Bool {
        guard !isScreenLocked() else { return false }
        return idleTimeSeconds() < idleThreshold
    }

    // MARK: - Idle Time

    /// Returns the number of seconds since the last keyboard or mouse event.
    /// Uses CoreGraphics event source, which is sandbox-safe.
    func idleTimeSeconds() -> TimeInterval {
        let eventTypes: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .rightMouseDown,
            .keyDown, .scrollWheel, .tabletPointer
        ]
        return eventTypes
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
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

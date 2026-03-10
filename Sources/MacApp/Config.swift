import Foundation

/// Edit these values before building, or expose them in Settings.
enum Config {
    /// Your iCloud container identifier.
    /// Create it at developer.apple.com → Certificates, IDs & Profiles → Identifiers → iCloud Containers.
    /// Format: "iCloud.<your-bundle-id>"  e.g. "iCloud.com.claude-remote.app"
    static let cloudKitContainerID = "iCloud.com.claude-remote.app"

    /// Unix socket path for IPC between the Python hook script and this Mac app.
    static let socketPath = {
        #if os(macOS)
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent(".claude-remote.sock").path
        #else
        return ""
        #endif
    }()

    /// Seconds of user inactivity before the Mac is considered "away".
    static let idleThresholdSeconds: TimeInterval = 60

    /// Seconds to wait for a local dialog response before escalating to a push notification.
    static let localDialogTimeoutSeconds: TimeInterval = 30

    /// Maximum seconds to wait for the iOS user to respond before denying by default.
    static let remoteResponseTimeoutSeconds: TimeInterval = 300

    /// CloudKit polling interval (seconds) while waiting for iOS response.
    static let pollIntervalSeconds: TimeInterval = 2
}

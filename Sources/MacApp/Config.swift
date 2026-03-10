import Foundation

/// Edit these values before building, or expose them in Settings.
enum Config {
    /// Your iCloud container identifier.
    /// Create it at developer.apple.com → Certificates, IDs & Profiles → Identifiers → iCloud Containers.
    /// Format: "iCloud.<your-bundle-id>"  e.g. "iCloud.com.claude-remote.app"
    static let cloudKitContainerID = "iCloud.com.claude-remote.app"

    /// Unix socket path for IPC between the Python hook script and this Mac app.
    /// Uses /tmp which is accessible from both sandboxed app and external scripts.
    static let socketPath = {
        #if os(macOS)
        // Use /tmp which is shared between sandbox and external processes
        // Include username to avoid conflicts on shared systems
        let username = NSUserName()
        return "/tmp/claude-remote-\(username).sock"
        #else
        return ""
        #endif
    }()
    
    /// Path to a file that contains the actual socket path for discovery by hook scripts.
    /// This is written by the Mac app at startup.
    static let socketPathFile = {
        #if os(macOS)
        let username = NSUserName()
        return "/tmp/claude-remote-\(username).path"
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

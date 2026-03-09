import Foundation
import UserNotifications

/// Manages macOS `UNUserNotificationCenter` for the Mac app.
/// Currently used only for informational toasts; the primary local approval
/// mechanism uses an osascript dialog (see `ApprovalCoordinator`).
final class MacNotificationService: NSObject {

    static let shared = MacNotificationService()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    // MARK: - Informational Toast

    /// Post a non-actionable banner (e.g. "Request sent to iPhone…").
    func postToast(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default

        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }

    /// Notify the user that an iOS response came in.
    func postResponseReceived(request: ApprovalRequest) {
        let verb = request.status == .approved ? "approved" : "denied"
        postToast(
            title: "ClaudeRemote — \(verb)",
            body: "iOS \(verb): \(request.toolName)"
        )
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension MacNotificationService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banners even when app is in foreground
        completionHandler([.banner, .sound])
    }
}

import Foundation
import UserNotifications

/// Manages local notifications on iOS.
/// Registers the approval notification category (with Approve / Deny action buttons)
/// and posts notifications when new requests arrive.
final class iOSNotificationService: NSObject {

    static let shared = iOSNotificationService()

    // Notification category / action identifiers
    enum CategoryID {
        static let approvalRequest = "APPROVAL_REQUEST"
    }
    enum ActionID {
        static let approve = "APPROVE"
        static let deny    = "DENY"
    }

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Setup

    /// Must be called on every app launch (including background wakes) so iOS
    /// knows the valid actions before showing any notification.
    func registerNotificationCategories() {
        let approveAction = UNNotificationAction(
            identifier: ActionID.approve,
            title: "Approve ✓",
            options: [.authorizationRequired]
        )
        let denyAction = UNNotificationAction(
            identifier: ActionID.deny,
            title: "Deny ✗",
            options: [.authorizationRequired, .destructive]
        )
        let category = UNNotificationCategory(
            identifier: CategoryID.approvalRequest,
            actions: [approveAction, denyAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func requestAuthorization() async {
        try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert])
    }

    // MARK: - Post Approval Notification

    /// Post a local actionable notification for an approval request.
    /// This runs both when the app is backgrounded and when the CloudKit push
    /// wakes it. The notification category provides Approve/Deny buttons that
    /// work even from the lock screen and Apple Watch.
    func postApprovalNotification(for request: ApprovalRequest) async {
        let content = UNMutableNotificationContent()
        content.title = "Claude Code — \(request.toolName)"
        content.body  = request.notificationBody
        content.sound = .defaultCritical           // Break through Focus on Apple Watch too
        content.categoryIdentifier = CategoryID.approvalRequest
        content.interruptionLevel  = .timeSensitive // Bypass Focus filters
        content.userInfo = [
            "requestId": request.id,
            "toolName": request.toolName
        ]
        // Badge shows number of pending requests
        let pending = await iOSCloudKitService.shared.fetchAllPending()
        content.badge = NSNumber(value: pending.count)

        let notifRequest = UNNotificationRequest(
            identifier: "approval-\(request.id)",
            content: content,
            trigger: nil  // Deliver immediately
        )
        try? await UNUserNotificationCenter.current().add(notifRequest)
    }

    /// Remove the notification for a request once it has been responded to.
    func dismissNotification(for requestID: String) {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: ["approval-\(requestID)"])
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["approval-\(requestID)"])
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension iOSNotificationService: UNUserNotificationCenterDelegate {

    /// Show the notification banner even while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle action button taps — works even when the app is backgrounded or killed.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo  = response.notification.request.content.userInfo
        guard let requestID = userInfo["requestId"] as? String else {
            completionHandler()
            return
        }

        let decision: ApprovalRequest.Status
        switch response.actionIdentifier {
        case ActionID.approve:
            decision = .approved
        case ActionID.deny:
            decision = .denied
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification body — open app, don't auto-respond
            completionHandler()
            return
        default:
            // Dismissed or unknown
            completionHandler()
            return
        }

        Task {
            do {
                try await iOSCloudKitService.shared.respond(to: requestID, decision: decision)
                self.dismissNotification(for: requestID)

                // Update app badge
                let remaining = await iOSCloudKitService.shared.fetchAllPending()
                await UNUserNotificationCenter.current()
                    .setBadgeCount(remaining.count)
            } catch {
                print("[iOSNotification] Failed to write response: \(error)")
            }
            completionHandler()
        }
    }
}

import SwiftUI
import UserNotifications
import CloudKit

@main
struct ClaudeRemoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = iOSApprovalStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Register notification categories with action buttons.
        // These must be registered on every launch (including background wakeups)
        // so iOS knows the valid actions before showing notifications.
        iOSNotificationService.shared.registerNotificationCategories()

        // Request permission and register for remote notifications
        // (required for CloudKit subscriptions to deliver silent pushes)
        Task {
            await iOSNotificationService.shared.requestAuthorization()
            application.registerForRemoteNotifications()
        }

        // Set up CloudKit subscription so we're notified of new requests
        Task {
            await iOSCloudKitService.shared.setupSubscriptionIfNeeded()
        }

        return true
    }

    // MARK: - Remote Notifications

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // CloudKit handles device token registration internally; nothing to do here.
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[ClaudeRemote] Push registration failed: \(error)")
    }

    /// Called for CloudKit silent pushes (content-available: 1).
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Check if this is a CloudKit notification
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }

        Task {
            let fetched = await iOSCloudKitService.shared.fetchNewPendingRequests()
            if fetched.isEmpty {
                completionHandler(.noData)
            } else {
                // Post local notifications for each new pending request
                for request in fetched {
                    await iOSNotificationService.shared.postApprovalNotification(for: request)
                }
                completionHandler(.newData)
            }
        }
    }
}

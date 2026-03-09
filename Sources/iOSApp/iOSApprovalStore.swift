import Foundation
import Combine

/// Observable store that drives the iOS UI.
@MainActor
final class iOSApprovalStore: ObservableObject {
    @Published var pendingRequests: [ApprovalRequest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let cloudKit = iOSCloudKitService.shared
    private let notifications = iOSNotificationService.shared

    init() {
        Task { await refresh() }
        // Refresh whenever the app comes to the foreground
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        pendingRequests = await cloudKit.fetchAllPending()
    }

    func respond(to request: ApprovalRequest, decision: ApprovalRequest.Status) async {
        do {
            try await cloudKit.respond(to: request.id, decision: decision)
            notifications.dismissNotification(for: request.id)
            pendingRequests.removeAll { $0.id == request.id }
        } catch {
            errorMessage = "Failed to send response: \(error.localizedDescription)"
        }
    }
}

// Required for NotificationCenter observer — import UIKit conditionally
#if canImport(UIKit)
import UIKit
#endif

import AppKit
import Foundation
import SwiftUI
import UserNotifications

/// Central coordinator for the Mac app.
/// Receives approval requests from the Unix socket server, decides whether to
/// handle them locally (osascript dialog) or remotely (CloudKit → iOS push),
/// and returns the decision to the waiting hook script.
@MainActor
final class ApprovalCoordinator: ObservableObject {

    // MARK: - Published State

    @Published var activeRequests: [ApprovalRequest] = []
    @Published var statusMessage: String = "Idle"
    @Published var isConnected: Bool = false
    @Published var cloudKitAvailable: Bool = false

    // MARK: - Services

    private let socketServer  = UnixSocketServer()
    private let presence      = PresenceDetector()
    private let cloudKit      = MacCloudKitService.shared
    private let notifications = MacNotificationService.shared

    // MARK: - Lifecycle

    init() {
        Task { await start() }
    }

    private func start() async {
        // Request notification permission
        await notifications.requestAuthorization()

        // Start the Unix socket server
        do {
            try socketServer.start { [weak self] request in
                guard let self else {
                    return UnixSocketServer.Response(id: request.id, decision: "allow")
                }
                return await self.handle(request)
            }
            isConnected = true
            statusMessage = "Listening on \(Config.socketPath)"
        } catch {
            statusMessage = "Socket error: \(error.localizedDescription)"
        }

        cloudKitAvailable = await cloudKit.checkAccountStatus()
    }

    // MARK: - Core Handler

    /// Called for every incoming request from the Python hook script.
    /// Returns the decision that will be forwarded back over the socket.
    private func handle(_ request: ApprovalRequest) async -> UnixSocketServer.Response {
        await MainActor.run {
            activeRequests.append(request)
            statusMessage = "Pending: \(request.toolName)"
        }
        defer {
            Task { @MainActor in
                activeRequests.removeAll { $0.id == request.id }
                if activeRequests.isEmpty { statusMessage = "Idle" }
            }
        }

        let atDesk = presence.isAtDesk()

        if atDesk {
            // ── Local path: show native dialog (blocks until user responds or times out) ──
            let result = await showLocalDialog(for: request)
            switch result {
            case "approve": return .init(id: request.id, decision: "allow")
            case "deny":    return .init(id: request.id, decision: "deny")
            default: break  // "timeout" → fall through to remote path
            }
        }

        // ── Remote path: publish to CloudKit, poll until iOS responds ──
        await MainActor.run { statusMessage = "Waiting for iOS response…" }

        do {
            try await cloudKit.publishRequest(request)
            let responded = try await cloudKit.pollForResponse(
                requestID: request.id,
                timeout: Config.remoteResponseTimeoutSeconds
            )
            let decision = responded.status == .approved ? "allow" : "deny"
            return .init(id: request.id, decision: decision)
        } catch {
            // Timeout or CloudKit error → deny by default to avoid silent auto-approval
            return .init(id: request.id, decision: "deny")
        }
    }

    // MARK: - Local dialog

    @MainActor
    private func showLocalDialog(for request: ApprovalRequest) async -> String {
        let alert = NSAlert()
        alert.messageText = "Claude Code Permission Request"
        alert.informativeText = "Tool: \(request.toolName)\n\n\(request.notificationBody)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Approve")
        alert.addButton(withTitle: "Deny")

        NSApp.activate(ignoringOtherApps: true)

        let timer = Timer.scheduledTimer(withTimeInterval: Config.localDialogTimeoutSeconds, repeats: false) { _ in
            NSApp.stopModal(withCode: .cancel)
        }
        defer { timer.invalidate() }

        switch alert.runModal() {
        case .alertFirstButtonReturn: return "approve"
        case .alertSecondButtonReturn: return "deny"
        default: return "timeout"
        }
    }
}

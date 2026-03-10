import AppKit
import Foundation
import OSLog
import SwiftUI
import UserNotifications

private let log = Logger(subsystem: "com.claude-remote.app", category: "ApprovalCoordinator")

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

    // MARK: - Menu-bar overrides

    /// Pending continuations keyed by request ID.
    /// Resumed when the user taps Approve/Deny in the menu-bar popover.
    private var pendingOverrides: [String: CheckedContinuation<String, Never>] = [:]

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

    // MARK: - Menu-bar decision API

    /// Called when the user taps Approve/Deny for a request in the menu-bar popover.
    func menuBarDecide(requestID: String, approve: Bool) {
        pendingOverrides.removeValue(forKey: requestID)?
            .resume(returning: approve ? "approve" : "deny")
    }

    // MARK: - Core Handler

    /// Called for every incoming request from the Python hook script.
    /// Returns the decision that will be forwarded back over the socket.
    private func handle(_ request: ApprovalRequest) async -> UnixSocketServer.Response {
        activeRequests.append(request)
        statusMessage = "Pending: \(request.toolName)"

        // Race the normal approval flow against a direct menu-bar decision.
        // Whichever resolves first wins; the other is cancelled/cleaned up.
        let decision = await withTaskGroup(of: String.self) { group in

            // Normal flow: local dialog → (on timeout) → CloudKit remote path
            group.addTask { @MainActor in
                await self.normalFlow(for: request)
            }

            // Menu-bar override: suspends until the user taps Approve/Deny in the popover
            group.addTask { @MainActor in
                await withTaskCancellationHandler(
                    operation: {
                        await withCheckedContinuation { cont in
                            self.pendingOverrides[request.id] = cont
                        }
                    },
                    onCancel: {
                        // Resume with a sentinel so the continuation isn't leaked.
                        // The result is discarded since the task group has already returned.
                        Task { @MainActor in
                            self.pendingOverrides.removeValue(forKey: request.id)?
                                .resume(returning: "__cancelled__")
                        }
                    }
                )
            }

            let first = await group.next()!
            group.cancelAll()
            return first
        }

        // If normal flow won, clean up any un-consumed override continuation.
        pendingOverrides.removeValue(forKey: request.id)?
            .resume(returning: "__cancelled__")

        activeRequests.removeAll { $0.id == request.id }
        if activeRequests.isEmpty { statusMessage = "Idle" }

        switch decision {
        case "approve": return .init(id: request.id, decision: "allow")
        case "deny":    return .init(id: request.id, decision: "deny")
        default:        return .init(id: request.id, decision: "deny")
        }
    }

    // MARK: - Normal flow (dialog → CloudKit)

    private func normalFlow(for request: ApprovalRequest) async -> String {
        let idleSeconds = presence.idleTimeSeconds()
        let atDesk = presence.isAtDesk()
        log.info("handle: tool=\(request.toolName) idle=\(idleSeconds, format: .fixed(precision: 1))s atDesk=\(atDesk)")

        if atDesk {
            // ── Local path: show native dialog (blocks until user responds or times out) ──
            statusMessage = "Local dialog shown (idle \(Int(idleSeconds))s)"
            log.info("handle: showing local dialog")
            let result = await showLocalDialog(for: request)
            log.info("handle: local dialog result=\(result)")
            switch result {
            case "approve": return "approve"
            case "deny":    return "deny"
            default: break  // "timeout" → fall through to remote path
            }
        } else {
            statusMessage = "Away (idle \(Int(idleSeconds))s) → sending to iPhone…"
        }

        // ── Remote path: publish to CloudKit, poll until iOS responds ──
        log.info("handle: entering remote path")
        do {
            try await cloudKit.publishRequest(request)
            log.info("handle: published to CloudKit, polling…")
            statusMessage = "Waiting for iPhone response…"
            let responded = try await cloudKit.pollForResponse(
                requestID: request.id,
                timeout: Config.remoteResponseTimeoutSeconds
            )
            let decision = responded.status == .approved ? "approve" : "deny"
            log.info("handle: iOS responded decision=\(decision)")
            return decision
        } catch {
            log.error("handle: CloudKit error — \(error)")
            statusMessage = "CloudKit error: \(error.localizedDescription)"
            // Timeout or CloudKit error → deny by default to avoid silent auto-approval
            return "deny"
        }
    }

    // MARK: - Local dialog

    private func showLocalDialog(for request: ApprovalRequest) async -> String {
        // Bridge blocking runModal() into async/await via a continuation.
        // Must run on the main thread but outside the Swift concurrency executor
        // so the modal run loop can process events normally.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Claude Code Permission Request"
                alert.informativeText = "Tool: \(request.toolName)\n\n\(request.notificationBody)"
                alert.alertStyle = .warning
                alert.icon = NSApp.applicationIconImage
                alert.addButton(withTitle: "Approve")
                alert.addButton(withTitle: "Deny")

                NSApp.activate(ignoringOtherApps: true)

                // Timer must be added to .modalPanel mode — that is the mode
                // NSAlert.runModal() uses, and timers in .default mode don't fire there.
                let timer = Timer(timeInterval: Config.localDialogTimeoutSeconds, repeats: false) { _ in
                    NSApp.stopModal(withCode: .cancel)
                }
                RunLoop.main.add(timer, forMode: .modalPanel)

                let response = alert.runModal()
                timer.invalidate()

                switch response {
                case .alertFirstButtonReturn: continuation.resume(returning: "approve")
                case .alertSecondButtonReturn: continuation.resume(returning: "deny")
                default:                      continuation.resume(returning: "timeout")
                }
            }
        }
    }
}

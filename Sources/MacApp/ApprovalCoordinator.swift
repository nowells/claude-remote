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

    // MARK: - Local dialog via osascript

    private func showLocalDialog(for request: ApprovalRequest) async -> String {
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let result = await Self.runDialog(for: request)
                continuation.resume(returning: result)
            }
        }
    }

    private static func runDialog(for request: ApprovalRequest) -> String {
        // Escape text for AppleScript string literals
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
        }

        let detail = esc(request.notificationBody)
        let toolName = esc(request.toolName)
        let timeout = Int(Config.localDialogTimeoutSeconds)

        let script = """
        try
            set dlg to (display alert "Claude Code Permission Request" ¬
                message "Tool: \(toolName)\\n\\n\(detail)" ¬
                as warning ¬
                buttons {"Deny", "Approve"} ¬
                default button "Approve" ¬
                giving up after \(timeout))
            if gave up of dlg is true then
                return "timeout"
            else if button returned of dlg is "Approve" then
                return "approve"
            else
                return "deny"
            end if
        on error
            return "timeout"
        end try
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()  // suppress osascript errors

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return output.isEmpty ? "timeout" : output
        } catch {
            return "timeout"
        }
    }
}

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var coordinator: ApprovalCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──────────────────────────────────────────────
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.blue)
                Text("ClaudeRemote")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(coordinator.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // ── Active Requests ──────────────────────────────────────
            if coordinator.activeRequests.isEmpty {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text(coordinator.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else {
                HStack {
                    Text("Pending Requests")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(coordinator.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                ForEach(coordinator.activeRequests) { request in
                    RequestRow(request: request)
                }
            }

            Divider()

            // ── Footer Buttons ───────────────────────────────────────
            HStack {
                if #available(macOS 14.0, *) {
                    SettingsLink {
                        Text("Settings")
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                } else {
                    Button("Settings") {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }

                Spacer()

                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 280)
    }
}

// MARK: - Request Row

private struct RequestRow: View {
    let request: ApprovalRequest
    @EnvironmentObject var coordinator: ApprovalCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: toolIcon(request.toolName))
                    .foregroundStyle(.orange)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(request.toolName)
                        .font(.caption.bold())
                    Text(request.notificationBody)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            HStack(spacing: 6) {
                Button("Approve") {
                    coordinator.menuBarDecide(requestID: request.id, approve: true)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.green)

                Button("Deny") {
                    coordinator.menuBarDecide(requestID: request.id, approve: false)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
            }
            .padding(.leading, 24)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.05))
    }

    private func toolIcon(_ name: String) -> String {
        switch name.lowercased() {
        case "bash":     return "terminal"
        case "write":    return "pencil"
        case "edit":     return "square.and.pencil"
        case "computer": return "desktopcomputer"
        default:         return "wrench.and.screwdriver"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var coordinator: ApprovalCoordinator
    @AppStorage("idleThreshold")   private var idleThreshold: Double = 60
    @AppStorage("dialogTimeout")   private var dialogTimeout: Double = 30

    var body: some View {
        Form {
            Section("Presence Detection") {
                LabeledContent("Away threshold") {
                    HStack {
                        Slider(value: $idleThreshold, in: 10...300, step: 10)
                            .frame(width: 160)
                        Text("\(Int(idleThreshold))s")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Text("If idle longer than this, you're considered away and pushes go to iPhone immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Local Dialog") {
                LabeledContent("Timeout") {
                    HStack {
                        Slider(value: $dialogTimeout, in: 5...120, step: 5)
                            .frame(width: 160)
                        Text("\(Int(dialogTimeout))s")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Text("After this many seconds without a response to the local dialog, the request is escalated to your iPhone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Status") {
                LabeledContent("Socket") {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(coordinator.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(Config.socketPath)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                LabeledContent("CloudKit") {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(coordinator.cloudKitAvailable ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(Config.cloudKitContainerID)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
        .navigationTitle("ClaudeRemote Settings")
    }
}

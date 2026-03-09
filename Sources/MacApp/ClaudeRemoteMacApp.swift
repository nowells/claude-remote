import SwiftUI
import UserNotifications

@main
struct ClaudeRemoteMacApp: App {
    @StateObject private var coordinator = ApprovalCoordinator()

    var body: some Scene {
        // Pure menu-bar app — no Dock icon (set LSUIElement = YES in Info.plist)
        MenuBarExtra {
            MenuBarView()
                .environmentObject(coordinator)
        } label: {
            MenuBarLabel()
                .environmentObject(coordinator)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(coordinator)
        }
    }
}

// MARK: - Menu bar badge label

private struct MenuBarLabel: View {
    @EnvironmentObject var coordinator: ApprovalCoordinator

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: coordinator.activeRequests.isEmpty
                  ? "checkmark.shield"
                  : "exclamationmark.shield.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(coordinator.activeRequests.isEmpty ? .primary : .orange)
            if !coordinator.activeRequests.isEmpty {
                Text("\(coordinator.activeRequests.count)")
                    .font(.caption2.monospacedDigit())
            }
        }
    }
}

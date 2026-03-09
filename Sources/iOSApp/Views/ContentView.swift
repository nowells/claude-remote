import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: iOSApprovalStore

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.pendingRequests.isEmpty {
                    ProgressView("Loading…")
                } else if store.pendingRequests.isEmpty {
                    EmptyStateView()
                } else {
                    requestList
                }
            }
            .navigationTitle("Approvals")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(store.isLoading)
                }
            }
            .refreshable {
                await store.refresh()
            }
            .alert("Error", isPresented: .init(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }

    private var requestList: some View {
        List(store.pendingRequests) { request in
            NavigationLink {
                ApprovalDetailView(request: request)
                    .environmentObject(store)
            } label: {
                RequestSummaryRow(request: request)
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Request Summary Row

struct RequestSummaryRow: View {
    let request: ApprovalRequest

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: toolIcon(request.toolName))
                .font(.title3)
                .foregroundStyle(.orange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(request.toolName)
                        .font(.headline)
                    Spacer()
                    Text(request.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(request.notificationBody)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
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

// MARK: - Empty State

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text("No Pending Requests")
                .font(.title2.bold())
            Text("When Claude Code needs approval, requests will appear here and as notifications.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

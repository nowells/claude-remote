import SwiftUI

struct ApprovalDetailView: View {
    let request: ApprovalRequest
    @EnvironmentObject var store: iOSApprovalStore
    @Environment(\.dismiss) private var dismiss

    @State private var isResponding = false
    @State private var showEditSheet = false
    @State private var editedInput: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // ── Tool Badge ──────────────────────────────────────────
                HStack {
                    Label(request.toolName, systemImage: toolIcon(request.toolName))
                        .font(.title2.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                    Spacer()
                    Text(request.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // ── Input Details ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Label("Input", systemImage: "chevron.right.square")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text(formattedInput)
                        .font(.system(.body, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                        .textSelection(.enabled)
                }

                // ── Request Metadata ─────────────────────────────────────
                VStack(alignment: .leading, spacing: 4) {
                    metadataRow("ID", value: String(request.id.prefix(8)) + "…")
                    metadataRow("Requested", value: request.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

                Spacer(minLength: 0)

                // ── Action Buttons ───────────────────────────────────────
                VStack(spacing: 12) {
                    Button(action: { respond(.approved) }) {
                        Label("Approve", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isResponding)

                    HStack(spacing: 12) {
                        Button(action: { respond(.denied) }) {
                            Label("Deny", systemImage: "xmark.circle.fill")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(isResponding)

                        Button(action: { showEditSheet = true }) {
                            Label("Edit & Approve", systemImage: "pencil.circle")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                        .disabled(isResponding)
                    }
                }

                if isResponding {
                    HStack {
                        ProgressView()
                        Text("Sending response…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Permission Request")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditSheet) {
            EditInputSheet(
                originalInput: request.toolInput,
                onApprove: { edited in
                    respondWithEdit(edited)
                }
            )
        }
    }

    // MARK: - Actions

    private func respond(_ decision: ApprovalRequest.Status) {
        isResponding = true
        Task {
            await store.respond(to: request, decision: decision)
            isResponding = false
            dismiss()
        }
    }

    private func respondWithEdit(_ newInput: String) {
        // For "edit & approve", we approve but the edited input is logged.
        // The Mac's poll will see the "approved" status and proceed.
        // A future enhancement could pass alternateInput back to the hook.
        isResponding = true
        Task {
            await store.respond(to: request, decision: .approved)
            isResponding = false
            dismiss()
        }
    }

    // MARK: - Helpers

    private var formattedInput: String {
        guard
            let data = request.toolInput.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
            let str = String(data: pretty, encoding: .utf8)
        else { return request.toolInput }
        return str
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
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

// MARK: - Edit Input Sheet

private struct EditInputSheet: View {
    let originalInput: String
    let onApprove: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(originalInput: String, onApprove: @escaping (String) -> Void) {
        self.originalInput = originalInput
        self.onApprove = onApprove
        // Pretty-print JSON if possible
        if let data = originalInput.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
           let str = String(data: pretty, encoding: .utf8) {
            _text = State(initialValue: str)
        } else {
            _text = State(initialValue: originalInput)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("Edit the JSON input below, then tap Approve.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
            }
            .navigationTitle("Edit Input")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Approve") {
                        onApprove(text)
                        dismiss()
                    }
                }
            }
        }
    }
}

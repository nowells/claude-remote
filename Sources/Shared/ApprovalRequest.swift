import Foundation
import CloudKit

// MARK: - ApprovalRequest
// Shared model used by both the Mac app (publisher) and iOS app (responder).

public struct ApprovalRequest: Identifiable, Codable, Sendable {
    public let id: String
    public let toolName: String
    public let toolInput: String      // Raw JSON string from Claude Code
    public var status: Status
    public var alternateInput: String? // Modified JSON if user edits the input
    public let createdAt: Date
    public var respondedAt: Date?

    public enum Status: String, Codable, Sendable {
        case pending
        case approved
        case denied
    }

    public init(
        id: String = UUID().uuidString,
        toolName: String,
        toolInput: String,
        status: Status = .pending,
        alternateInput: String? = nil,
        createdAt: Date = Date(),
        respondedAt: Date? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.toolInput = toolInput
        self.status = status
        self.alternateInput = alternateInput
        self.createdAt = createdAt
        self.respondedAt = respondedAt
    }

    // MARK: - Display Helpers

    /// Human-readable summary of the tool input, used in notifications/dialogs.
    public var displaySummary: String {
        guard
            let data = toolInput.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return toolInput }

        switch toolName.lowercased() {
        case "bash":
            if let cmd = obj["command"] as? String { return cmd }
        case "write", "edit":
            if let path = obj["file_path"] as? String { return path }
        case "computer":
            if let action = obj["action"] as? String { return action }
        default:
            break
        }
        return obj.map { "\($0.key): \($0.value)" }.prefix(3).joined(separator: "\n")
    }

    /// Short body suitable for a push notification.
    public var notificationBody: String {
        let summary = displaySummary
        let maxLen = 120
        return summary.count > maxLen ? String(summary.prefix(maxLen)) + "…" : summary
    }
}

// MARK: - CloudKit Serialization

extension ApprovalRequest {
    public static let recordType = "ApprovalRequest"

    /// Build a CKRecord from this request (used by Mac app when publishing).
    public var cloudKitRecord: CKRecord {
        let record = CKRecord(
            recordType: Self.recordType,
            recordID: CKRecord.ID(recordName: id)
        )
        record["toolName"]     = toolName     as CKRecordValue
        record["toolInput"]    = toolInput    as CKRecordValue
        record["status"]       = status.rawValue as CKRecordValue
        record["createdAt"]    = createdAt    as CKRecordValue
        if let alt = alternateInput  { record["alternateInput"] = alt as CKRecordValue }
        if let rAt = respondedAt     { record["respondedAt"]    = rAt as CKRecordValue }
        return record
    }

    /// Reconstruct an ApprovalRequest from a CKRecord (used by both sides).
    public init?(cloudKitRecord record: CKRecord) {
        guard
            let toolName   = record["toolName"]   as? String,
            let toolInput  = record["toolInput"]   as? String,
            let statusRaw  = record["status"]      as? String,
            let status     = Status(rawValue: statusRaw),
            let createdAt  = record["createdAt"]   as? Date
        else { return nil }

        self.id             = record.recordID.recordName
        self.toolName       = toolName
        self.toolInput      = toolInput
        self.status         = status
        self.createdAt      = createdAt
        self.alternateInput = record["alternateInput"] as? String
        self.respondedAt    = record["respondedAt"]    as? Date
    }
}

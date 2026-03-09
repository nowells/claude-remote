import XCTest
import CloudKit
@testable import Shared

final class ApprovalRequestTests: XCTestCase {

    // MARK: - Initialisation

    func testDefaultInitHasPendingStatus() {
        let r = ApprovalRequest(toolName: "Bash", toolInput: "{}")
        XCTAssertEqual(r.status, .pending)
        XCTAssertFalse(r.id.isEmpty)
        XCTAssertNil(r.alternateInput)
        XCTAssertNil(r.respondedAt)
    }

    func testCustomIDIsPreserved() {
        let r = ApprovalRequest(id: "test-123", toolName: "Write", toolInput: "{}")
        XCTAssertEqual(r.id, "test-123")
    }

    // MARK: - displaySummary

    func testDisplaySummaryBashExtractsCommand() {
        let r = ApprovalRequest(toolName: "Bash",
                                toolInput: #"{"command":"rm -rf /tmp/test"}"#)
        XCTAssertEqual(r.displaySummary, "rm -rf /tmp/test")
    }

    func testDisplaySummaryBashCaseInsensitive() {
        let r = ApprovalRequest(toolName: "bash",
                                toolInput: #"{"command":"echo hello"}"#)
        XCTAssertEqual(r.displaySummary, "echo hello")
    }

    func testDisplaySummaryWriteExtractsFilePath() {
        let r = ApprovalRequest(toolName: "Write",
                                toolInput: #"{"file_path":"/tmp/foo.txt","content":"hi"}"#)
        XCTAssertEqual(r.displaySummary, "/tmp/foo.txt")
    }

    func testDisplaySummaryEditExtractsFilePath() {
        let r = ApprovalRequest(toolName: "Edit",
                                toolInput: #"{"file_path":"/src/main.swift","old_string":"x","new_string":"y"}"#)
        XCTAssertEqual(r.displaySummary, "/src/main.swift")
    }

    func testDisplaySummaryComputerExtractsAction() {
        let r = ApprovalRequest(toolName: "Computer",
                                toolInput: #"{"action":"screenshot"}"#)
        XCTAssertEqual(r.displaySummary, "screenshot")
    }

    func testDisplaySummaryUnknownToolShowsKeyValuePairs() {
        let r = ApprovalRequest(toolName: "CustomTool",
                                toolInput: #"{"foo":"bar"}"#)
        XCTAssertTrue(r.displaySummary.contains("foo"))
        XCTAssertTrue(r.displaySummary.contains("bar"))
    }

    func testDisplaySummaryInvalidJSONReturnsRaw() {
        let raw = "not json at all"
        let r = ApprovalRequest(toolName: "Bash", toolInput: raw)
        XCTAssertEqual(r.displaySummary, raw)
    }

    // MARK: - notificationBody

    func testNotificationBodyShortInputUnchanged() {
        let short = "echo hi"
        let r = ApprovalRequest(toolName: "Bash",
                                toolInput: #"{"command":"\#(short)"}"#)
        XCTAssertTrue(r.notificationBody.contains(short))
        XCTAssertFalse(r.notificationBody.hasSuffix("…"))
    }

    func testNotificationBodyTruncatesLongInput() {
        let long = String(repeating: "x", count: 200)
        let r = ApprovalRequest(toolName: "Bash",
                                toolInput: #"{"command":"\#(long)"}"#)
        XCTAssertTrue(r.notificationBody.hasSuffix("…"))
        XCTAssertLessThanOrEqual(r.notificationBody.count, 125) // 120 + "…" (3 bytes, 1 char)
    }

    // MARK: - Codable round-trip

    func testCodableRoundTrip() throws {
        let original = ApprovalRequest(
            id: "round-trip-id",
            toolName: "Bash",
            toolInput: #"{"command":"ls"}"#,
            status: .approved,
            alternateInput: #"{"command":"ls -la"}"#,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            respondedAt: Date(timeIntervalSince1970: 1_700_000_030)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ApprovalRequest.self, from: data)

        XCTAssertEqual(decoded.id,              original.id)
        XCTAssertEqual(decoded.toolName,        original.toolName)
        XCTAssertEqual(decoded.toolInput,       original.toolInput)
        XCTAssertEqual(decoded.status,          original.status)
        XCTAssertEqual(decoded.alternateInput,  original.alternateInput)
        // Dates lose sub-second precision through JSON; compare to within 1 s
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970,
                       original.createdAt.timeIntervalSince1970, accuracy: 1)
    }

    // MARK: - Status

    func testStatusRawValues() {
        XCTAssertEqual(ApprovalRequest.Status.pending.rawValue,  "pending")
        XCTAssertEqual(ApprovalRequest.Status.approved.rawValue, "approved")
        XCTAssertEqual(ApprovalRequest.Status.denied.rawValue,   "denied")
    }

    func testStatusDecodingFromString() throws {
        let json = #"{"id":"x","toolName":"Bash","toolInput":"{}","status":"approved","createdAt":0}"#
        let r = try JSONDecoder().decode(ApprovalRequest.self, from: Data(json.utf8))
        XCTAssertEqual(r.status, .approved)
    }

    // MARK: - CloudKit round-trip

    func testCloudKitRecordPreservesFields() {
        let original = ApprovalRequest(
            id: "ck-test-id",
            toolName: "Write",
            toolInput: #"{"file_path":"/tmp/x"}"#,
            status: .denied,
            alternateInput: nil,
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            respondedAt: Date(timeIntervalSince1970: 1_000_060)
        )

        let record = original.cloudKitRecord

        XCTAssertEqual(record.recordID.recordName, "ck-test-id")
        XCTAssertEqual(record["toolName"]  as? String, "Write")
        XCTAssertEqual(record["toolInput"] as? String, #"{"file_path":"/tmp/x"}"#)
        XCTAssertEqual(record["status"]    as? String, "denied")
        XCTAssertNil(record["alternateInput"])
    }

    func testCloudKitRecordRoundTrip() {
        let original = ApprovalRequest(
            id: "ck-rt-id",
            toolName: "Bash",
            toolInput: #"{"command":"pwd"}"#,
            status: .approved,
            createdAt: Date(timeIntervalSince1970: 1_500_000_000)
        )

        let record = original.cloudKitRecord
        let reconstructed = ApprovalRequest(cloudKitRecord: record)

        XCTAssertNotNil(reconstructed)
        XCTAssertEqual(reconstructed?.id,        original.id)
        XCTAssertEqual(reconstructed?.toolName,  original.toolName)
        XCTAssertEqual(reconstructed?.toolInput, original.toolInput)
        XCTAssertEqual(reconstructed?.status,    original.status)
    }

    func testCloudKitInitReturnsNilForMissingFields() {
        // A record missing required fields should fail gracefully
        let record = CKRecord(recordType: ApprovalRequest.recordType,
                              recordID: CKRecord.ID(recordName: "incomplete"))
        // No toolName, toolInput, status, or createdAt set
        XCTAssertNil(ApprovalRequest(cloudKitRecord: record))
    }

    func testCloudKitInitReturnsNilForBadStatusString() {
        let record = CKRecord(recordType: ApprovalRequest.recordType,
                              recordID: CKRecord.ID(recordName: "bad-status"))
        record["toolName"]  = "Bash" as CKRecordValue
        record["toolInput"] = "{}"   as CKRecordValue
        record["status"]    = "unknown_status" as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        XCTAssertNil(ApprovalRequest(cloudKitRecord: record))
    }
}

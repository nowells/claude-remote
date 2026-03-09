import CloudKit
import Foundation

/// Mac-side CloudKit service.
/// The Mac app acts as the *publisher*: it writes pending ApprovalRequests and
/// polls for responses written by the iOS companion app.
/// (No CloudKit subscription / APNs entitlement needed on the Mac side.)
@MainActor
final class MacCloudKitService {

    static let shared = MacCloudKitService()

    private var container: CKContainer { CKContainer(identifier: Config.cloudKitContainerID) }
    private var db: CKDatabase { container.privateCloudDatabase }

    private init() {}

    // MARK: - Publish Request

    /// Write a pending ApprovalRequest to CloudKit so the iOS app can see it.
    func publishRequest(_ request: ApprovalRequest) async throws {
        let record = request.cloudKitRecord
        _ = try await db.save(record)
    }

    // MARK: - Poll for Response

    /// Repeatedly fetch the record until its status changes from `.pending`,
    /// or until `timeout` seconds have elapsed.
    func pollForResponse(requestID: String, timeout: TimeInterval) async throws -> ApprovalRequest {
        let recordID = CKRecord.ID(recordName: requestID)
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            try Task.checkCancellation()

            do {
                let record = try await db.record(for: recordID)
                if let req = ApprovalRequest(cloudKitRecord: record), req.status != .pending {
                    // Clean up after ourselves
                    Task { try? await self.db.deleteRecord(withID: recordID) }
                    return req
                }
            } catch let ckError as CKError where ckError.code == .unknownItem {
                // Record deleted or never arrived — treat as denied
                throw ckError
            } catch {
                // Transient network error — keep polling
            }

            try await Task.sleep(for: .seconds(Config.pollIntervalSeconds))
        }

        // Timed out — clean up the record so it doesn't linger
        Task { try? await self.db.deleteRecord(withID: recordID) }
        throw CancellationError()
    }

    // MARK: - Cleanup

    /// Remove stale pending records older than `olderThan` seconds.
    /// Call this on startup to avoid accumulating orphaned records.
    func pruneStaleRequests(olderThan seconds: TimeInterval = 3600) async {
        let cutoff = Date().addingTimeInterval(-seconds)
        let predicate = NSPredicate(format: "createdAt < %@", cutoff as CVarArg)
        let query = CKQuery(recordType: ApprovalRequest.recordType, predicate: predicate)

        guard let (results, _) = try? await db.records(matching: query) else { return }
        for (recordID, _) in results {
            _ = try? await db.deleteRecord(withID: recordID)
        }
    }
}

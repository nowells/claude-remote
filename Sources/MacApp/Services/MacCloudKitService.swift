import CloudKit
import Foundation

/// Mac-side CloudKit service.
/// The Mac app acts as the *publisher*: it writes pending ApprovalRequests and
/// polls for responses written by the iOS companion app.
/// (No CloudKit subscription / APNs entitlement needed on the Mac side.)
@MainActor
final class MacCloudKitService {

    static let shared = MacCloudKitService()

    private let container = CKContainer(identifier: Config.cloudKitContainerID)
    private var db: CKDatabase { container.privateCloudDatabase }

    private init() {}

    // MARK: - Account Status

    /// Returns true when the device has an iCloud account and CloudKit is reachable.
    func checkAccountStatus() async -> Bool {
        do {
            let status = try await container.accountStatus()
            return status == .available
        } catch {
            return false
        }
    }

    // MARK: - Zone Setup

    /// Ensure the custom zone exists. CloudKit silently succeeds if it already exists.
    private func ensureZone() async throws {
        let zone = CKRecordZone(zoneID: ApprovalRequest.zoneID)
        _ = try await db.save(zone)
    }

    // MARK: - Publish Request

    /// Write a pending ApprovalRequest to CloudKit so the iOS app can see it.
    func publishRequest(_ request: ApprovalRequest) async throws {
        try await ensureZone()
        let record = request.cloudKitRecord
        _ = try await db.save(record)
    }

    // MARK: - Poll for Response

    /// Repeatedly fetch the record until its status changes from `.pending`,
    /// or until `timeout` seconds have elapsed.
    func pollForResponse(requestID: String, timeout: TimeInterval) async throws -> ApprovalRequest {
        let recordID = CKRecord.ID(recordName: requestID, zoneID: ApprovalRequest.zoneID)
        let deadline = Date().addingTimeInterval(timeout)

        return try await withTaskCancellationHandler {
            while Date() < deadline {
                try Task.checkCancellation()

                do {
                    let record = try await db.record(for: recordID)
                    if let req = ApprovalRequest(cloudKitRecord: record), req.status != .pending {
                        // iOS responded — clean up and return
                        Task { try? await self.db.deleteRecord(withID: recordID) }
                        return req
                    }
                } catch let ckError as CKError where ckError.code == .unknownItem {
                    // Record deleted externally — treat as denied
                    throw ckError
                } catch {
                    // Transient network error — keep polling
                }

                try await Task.sleep(for: .seconds(Config.pollIntervalSeconds))
            }

            // Timed out — clean up
            Task { try? await self.db.deleteRecord(withID: recordID) }
            throw CancellationError()
        } onCancel: {
            // Mac decided via menu bar (or other cancellation) — remove the record
            // so the iOS app stops showing it within one poll cycle.
            Task { try? await self.db.deleteRecord(withID: recordID) }
        }
    }

}

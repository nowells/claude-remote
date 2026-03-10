import CloudKit
import Foundation

/// iOS-side CloudKit service.
/// The iOS app acts as the *responder*: it subscribes to new pending records,
/// fetches them on notification, and writes the user's decision back.
@MainActor
final class iOSCloudKitService: ObservableObject {

    static let shared = iOSCloudKitService()

    // CloudKit container identifier - should match your iCloud container
    private static let cloudKitContainerID = "iCloud.com.claude-remote.app"

    private var container: CKContainer { CKContainer(identifier: Self.cloudKitContainerID) }
    private var db: CKDatabase { container.privateCloudDatabase }

    /// IDs of requests we've already shown a notification for (to avoid duplicates).
    private var notifiedIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "notifiedIDs") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "notifiedIDs") }
    }

    private init() {}

    // MARK: - Subscription

    /// Create a CloudKit subscription so the system delivers a silent push
    /// whenever a new ApprovalRequest record appears in the private DB.
    func setupSubscriptionIfNeeded() async {
        let subID = "pending-approvals-v2"

        // Check if subscription already exists
        do {
            _ = try await db.subscription(for: subID)
            return  // Already set up
        } catch { }

        let subscription = CKRecordZoneSubscription(
            zoneID: ApprovalRequest.zoneID,
            subscriptionID: subID
        )

        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true  // Silent push — app handles local notification
        subscription.notificationInfo = info

        do {
            try await db.save(subscription)
        } catch let ckError as CKError where ckError.code == .zoneNotFound {
            // Zone doesn't exist yet — Mac hasn't published anything.
            // Polling will still work; subscription will be created on next launch after first publish.
        } catch {
            print("[iOSCloudKit] Subscription setup failed: \(error)")
        }
    }

    // MARK: - Fetch

    /// Fetch all pending records created in the last hour that haven't been shown yet.
    func fetchNewPendingRequests() async -> [ApprovalRequest] {
        let requests = (try? await fetchAllPending()) ?? []
        let known = notifiedIDs
        let newRequests = requests.filter { !known.contains($0.id) }
        if !newRequests.isEmpty {
            notifiedIDs = known.union(newRequests.map(\.id))
        }
        return newRequests
    }

    /// Fetch all pending requests (for display in the app UI).
    /// Uses `CKFetchRecordZoneChangesOperation` on a custom zone — this requires
    /// zero CloudKit Dashboard index configuration (unlike CKQuery).
    func fetchAllPending() async throws -> [ApprovalRequest] {
        try await withCheckedThrowingContinuation { continuation in
            let zoneID = ApprovalRequest.zoneID
            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            // nil previousServerChangeToken → fetch all records from scratch

            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: config]
            )
            operation.fetchAllChanges = true

            var fetchedRecords: [CKRecord] = []
            var zoneError: Error?

            operation.recordWasChangedBlock = { _, result in
                if let record = try? result.get() {
                    fetchedRecords.append(record)
                }
            }

            operation.recordZoneFetchResultBlock = { _, result in
                if case .failure(let error) = result {
                    zoneError = error
                }
            }

            operation.fetchRecordZoneChangesResultBlock = { result in
                // Surface the zone-level error (e.g. zoneNotFound) if present
                let effectiveError: Error?
                if case .failure(let err) = result { effectiveError = err }
                else { effectiveError = zoneError }

                if let error = effectiveError {
                    // Zone doesn't exist yet (Mac hasn't published anything) → empty list
                    if let ckErr = error as? CKError,
                       ckErr.code == .zoneNotFound || ckErr.code == .userDeletedZone {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                let oneHourAgo = Date().addingTimeInterval(-3600)
                let pending = fetchedRecords
                    .compactMap { ApprovalRequest(cloudKitRecord: $0) }
                    .filter { $0.status == .pending && $0.createdAt >= oneHourAgo }
                    .sorted { $0.createdAt > $1.createdAt }
                continuation.resume(returning: pending)
            }

            db.add(operation)
        }
    }

    // MARK: - Respond

    /// Write the user's decision back to the CloudKit record so the Mac app can see it.
    func respond(to requestID: String, decision: ApprovalRequest.Status) async throws {
        let recordID = CKRecord.ID(recordName: requestID, zoneID: ApprovalRequest.zoneID)
        let record = try await db.record(for: recordID)
        record["status"]      = decision.rawValue as CKRecordValue
        record["respondedAt"] = Date() as CKRecordValue
        _ = try await db.save(record)

        // Clean up notification tracking
        var known = notifiedIDs
        known.remove(requestID)
        notifiedIDs = known
    }
}

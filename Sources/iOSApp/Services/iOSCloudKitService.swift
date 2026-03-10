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

    /// Server change token — used to fetch only new/updated records incrementally.
    private var changeToken: CKServerChangeToken? {
        get {
            guard let data = UserDefaults.standard.data(forKey: "ckChangeToken"),
                  let token = try? NSKeyedUnarchiver.unarchivedObject(
                      ofClass: CKServerChangeToken.self, from: data)
            else { return nil }
            return token
        }
        set {
            if let token = newValue,
               let data = try? NSKeyedArchiver.archivedData(
                   withRootObject: token, requiringSecureCoding: true) {
                UserDefaults.standard.set(data, forKey: "ckChangeToken")
            } else {
                UserDefaults.standard.removeObject(forKey: "ckChangeToken")
            }
        }
    }

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
        let subID = "pending-approvals-v1"

        // Check if subscription already exists
        do {
            _ = try await db.subscription(for: subID)
            return  // Already set up
        } catch { }

        let predicate = NSPredicate(value: true)  // match all — status filtered in memory
        let subscription = CKQuerySubscription(
            recordType: ApprovalRequest.recordType,
            predicate: predicate,
            subscriptionID: subID,
            options: [.firesOnRecordCreation]
        )

        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true  // Silent push — app handles local notification
        subscription.notificationInfo = info

        do {
            try await db.save(subscription)
        } catch {
            print("[iOSCloudKit] Subscription setup failed: \(error)")
        }
    }

    // MARK: - Fetch

    /// Fetch all pending records created in the last hour that haven't been shown yet.
    func fetchNewPendingRequests() async -> [ApprovalRequest] {
        let requests = await fetchAllPending()
        let known = notifiedIDs
        let newRequests = requests.filter { !known.contains($0.id) }
        if !newRequests.isEmpty {
            notifiedIDs = known.union(newRequests.map(\.id))
        }
        return newRequests
    }

    /// Fetch all pending requests (for display in the app UI).
    /// Uses only the system `creationDate` field in the predicate (always queryable without
    /// custom indexes), then filters by status in memory.
    func fetchAllPending() async -> [ApprovalRequest] {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        // `creationDate` is a CloudKit system field — no custom index needed.
        let predicate = NSPredicate(format: "creationDate >= %@", oneHourAgo as CVarArg)
        let query = CKQuery(recordType: ApprovalRequest.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        guard let (results, _) = try? await db.records(matching: query) else { return [] }
        return results
            .compactMap { (_, result) -> ApprovalRequest? in
                guard let record = try? result.get() else { return nil }
                return ApprovalRequest(cloudKitRecord: record)
            }
            .filter { $0.status == .pending }
    }

    // MARK: - Respond

    /// Write the user's decision back to the CloudKit record so the Mac app can see it.
    func respond(to requestID: String, decision: ApprovalRequest.Status) async throws {
        let recordID = CKRecord.ID(recordName: requestID)
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

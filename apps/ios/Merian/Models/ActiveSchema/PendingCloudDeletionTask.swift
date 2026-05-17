import Foundation
import SwiftData

@Model
public final class PendingCloudDeletionTask {
    @Attribute(.unique) public var scanId: String
    public var timestamp: Date = Date()

    public init(scanId: String, timestamp: Date = Date()) {
        self.scanId = scanId
        self.timestamp = timestamp
    }
}

extension ModelContext {
    /// Ensures a scan has exactly one pending cloud-deletion task queued.
    ///
    /// Re-queue attempts are treated as idempotent so callers can safely delete a record
    /// even if an earlier sync pass already staged its cloud erasure.
    @discardableResult
    func ensurePendingCloudDeletionTask(
        scanId: String,
        timestamp: Date = Date()
    ) throws -> PendingCloudDeletionTask {
        var descriptor = FetchDescriptor<PendingCloudDeletionTask>(
            predicate: #Predicate { $0.scanId == scanId }
        )
        descriptor.fetchLimit = 1

        if let existing = try fetch(descriptor).first {
            return existing
        }

        let task = PendingCloudDeletionTask(scanId: scanId, timestamp: timestamp)
        insert(task)
        return task
    }
}

import Foundation
import SwiftData

extension BackgroundDatabaseActor {
    struct ScanErasurePayload: Sendable {
        let id: String
        let mediaPaths: [String]
    }

    struct ExpiredNonBiologicalPurgeResult: Sendable, Equatable {
        /// Candidates whose local/cloud erasure work was durably accepted.
        /// Includes an already-missing row whose cleanup must remain retryable.
        let committedErasureCount: Int

        /// Persisted scan rows actually removed by this transaction.
        let deletedRecordCount: Int
        let localMediaPaths: [String]
        var childIDs: [String] = []
    }

    struct NonBiologicalDeletionCommit: Sendable {
        let committedErasureCount: Int
        let deletedRecordCount: Int
        let localMediaPaths: [String]
        var childIDs: [String] = []
    }

    /// Deletes non-biological scans and queues their cloud erasure atomically.
    ///
    /// Returns local-only file paths after the database commit succeeds so
    /// callers can purge disk artifacts without risking inconsistent state.
    func bulkDeleteNonBiologicalScans(
        payloads: [ScanErasurePayload], requestingAccountID: UUID? = nil
    ) throws -> [String] {
        try commitNonBiologicalScanDeletion(payloads: payloads, requestingAccountID: requestingAccountID,
                                           origin: .explicitUserDeletion)
            .localMediaPaths
    }

    /// Returns transport cleanup only after the same durable parent/child commit.
    func bulkDeleteNonBiologicalScansWithQueueCleanup(
        payloads: [ScanErasurePayload], requestingAccountID: UUID? = nil
    ) throws -> NonBiologicalDeletionCommit {
        try commitNonBiologicalScanDeletion(payloads: payloads, requestingAccountID: requestingAccountID,
                                           origin: .explicitUserDeletion)
    }

    private func commitNonBiologicalScanDeletion(
        payloads: [ScanErasurePayload], requestingAccountID: UUID?, origin: CloudDeletionIntent.Origin
    ) throws -> NonBiologicalDeletionCommit {
        try ConfirmedSpeciesReviewPersistence.transaction {
            // Share the history-admission gate and refetch after acquisition.
            let context = ModelContext(modelContainer)
            context.autosaveEnabled = false
            return try commitNonBiologicalScanDeletion(payloads: payloads,
                requestingAccountID: requestingAccountID, origin: origin, context: context)
        }
    }

    private func commitNonBiologicalScanDeletion(
        payloads: [ScanErasurePayload], requestingAccountID: UUID?, origin: CloudDeletionIntent.Origin,
        context: ModelContext
    ) throws -> NonBiologicalDeletionCommit {
        var committedErasureCount = 0
        var deletedRecordCount = 0
        var localMediaPathsToDelete: [String] = []
        var childIDs: [String] = []

        do {
            for payload in payloads {
                let scanId = payload.id
                if origin == .nonBiologicalRetention,
                   try ObservationHistoryEnrollmentIntent.protects(scanId, context: context) { continue }
                var descriptor = FetchDescriptor<LocalScanRecord>(
                    predicate: #Predicate { $0.id == scanId }
                )
                descriptor.fetchLimit = 1
                let record = try context.fetch(descriptor).first

                // The UI snapshots eligible rows before crossing into this
                // actor. Revalidate here so a concurrent reconciliation that
                // promotes the row to biological cannot be erased by stale
                // presentation state.
                if let record, record.isBiological ||
                    (origin == .nonBiologicalRetention && record.analysisOwnerAccountID != nil) {
                    continue
                }

                if origin == .explicitUserDeletion {
                    try ObservationHistoryEnrollmentIntent.supersedeForExplicitDeletion(scanId, context: context)
                }
                let children = try ObservationReanalysisErasure.removeChildren(of: scanId, context: context)
                childIDs += children.childIDs
                try ObservationPublicationPersistence.removeForDeletion(scanId, context: context)
                if let record {
                    context.delete(record)
                    deletedRecordCount += 1
                }

                localMediaPathsToDelete.append(
                    contentsOf: payload.mediaPaths.filter {
                        !$0.starts(with: "http")
                    }
                )
                try context.ensurePendingCloudDeletionTask(scanId: scanId,
                    requestingAccountID: requestingAccountID, origin: origin)
                committedErasureCount += 1
            }

            try context.save()
            return NonBiologicalDeletionCommit(
                committedErasureCount: committedErasureCount,
                deletedRecordCount: deletedRecordCount,
                localMediaPaths: localMediaPathsToDelete, childIDs: childIDs
            )
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Deletes non-biological records older than the supplied cutoff.
    ///
    /// The bounded fetch prevents foreground cleanup from loading a pathological
    /// library into memory. The result separates accepted erasure work from
    /// actual row deletion so callers can route durable and presentation effects
    /// independently. A later foreground may process another batch.
    func purgeExpiredNonBiologicalScans(
        cutoffDate: Date,
        limit: Int = NonBiologicalRetentionPolicy.purgeBatchSize,
        requestingAccountID: UUID? = nil
    ) throws -> ExpiredNonBiologicalPurgeResult {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate {
                $0.isBiological == false &&
                    $0.analysisOwnerAccountID == nil &&
                    $0.timestamp < cutoffDate
            },
            sortBy: [SortDescriptor(\.timestamp), SortDescriptor(\.id)]
        )
        descriptor.fetchLimit = limit

        guard limit > 0 else {
            return .init(committedErasureCount: 0, deletedRecordCount: 0, localMediaPaths: [])
        }
        var payloads = [ScanErasurePayload]()
        var offset = 0
        while payloads.count < limit {
            try Task.checkCancellation()
            descriptor.fetchOffset = offset
            // Release held rows after each bounded page instead of retaining the library.
            let read = ModelContext(modelContainer)
            let page = try read.fetch(descriptor)
            for record in page where payloads.count < limit {
                guard try !ObservationHistoryEnrollmentIntent.holds(record.id, context: read) else { continue }
                let media = record.capturedMediaSnapshot
                payloads.append(.init(id: record.id, mediaPaths: media.thumbnailImagePaths + media.audioPaths + media.videoPaths))
            }
            if page.count < limit { break }
            offset += page.count
        }
        guard !payloads.isEmpty else {
            return .init(committedErasureCount: 0, deletedRecordCount: 0, localMediaPaths: [])
        }

        let commit = try commitNonBiologicalScanDeletion(payloads: payloads,
            requestingAccountID: requestingAccountID, origin: .nonBiologicalRetention)
        return ExpiredNonBiologicalPurgeResult(
            committedErasureCount: commit.committedErasureCount,
            deletedRecordCount: commit.deletedRecordCount,
            localMediaPaths: commit.localMediaPaths, childIDs: commit.childIDs
        )
    }
}

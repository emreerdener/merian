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
    }

    private struct NonBiologicalDeletionCommit {
        let committedErasureCount: Int
        let deletedRecordCount: Int
        let localMediaPaths: [String]
    }

    /// Deletes non-biological scans and queues their cloud erasure atomically.
    ///
    /// Returns local-only file paths after the database commit succeeds so
    /// callers can purge disk artifacts without risking inconsistent state.
    func bulkDeleteNonBiologicalScans(
        payloads: [ScanErasurePayload]
    ) throws -> [String] {
        try commitNonBiologicalScanDeletion(payloads: payloads)
            .localMediaPaths
    }

    private func commitNonBiologicalScanDeletion(
        payloads: [ScanErasurePayload]
    ) throws -> NonBiologicalDeletionCommit {
        var committedErasureCount = 0
        var deletedRecordCount = 0
        var localMediaPathsToDelete: [String] = []

        do {
            for payload in payloads {
                let scanId = payload.id
                var descriptor = FetchDescriptor<LocalScanRecord>(
                    predicate: #Predicate { $0.id == scanId }
                )
                descriptor.fetchLimit = 1
                let record = try modelContext.fetch(descriptor).first

                // The UI snapshots eligible rows before crossing into this
                // actor. Revalidate here so a concurrent reconciliation that
                // promotes the row to biological cannot be erased by stale
                // presentation state.
                if let record, record.isBiological {
                    continue
                }

                if let record {
                    modelContext.delete(record)
                    deletedRecordCount += 1
                }

                localMediaPathsToDelete.append(
                    contentsOf: payload.mediaPaths.filter {
                        !$0.starts(with: "http")
                    }
                )
                try modelContext.ensurePendingCloudDeletionTask(scanId: scanId)
                committedErasureCount += 1
            }

            try modelContext.save()
            return NonBiologicalDeletionCommit(
                committedErasureCount: committedErasureCount,
                deletedRecordCount: deletedRecordCount,
                localMediaPaths: localMediaPathsToDelete
            )
        } catch {
            modelContext.rollback()
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
        limit: Int = MerianConfig.nonBiologicalPurgeBatchSize
    ) throws -> ExpiredNonBiologicalPurgeResult {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate {
                $0.isBiological == false &&
                    $0.timestamp < cutoffDate
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        descriptor.fetchLimit = limit

        let expiredRecords = try modelContext.fetch(descriptor)
        guard !expiredRecords.isEmpty else {
            return ExpiredNonBiologicalPurgeResult(
                committedErasureCount: 0,
                deletedRecordCount: 0,
                localMediaPaths: []
            )
        }

        let payloads = expiredRecords.map { record in
            let mediaSnapshot = record.capturedMediaSnapshot
            return ScanErasurePayload(
                id: record.id,
                mediaPaths: mediaSnapshot.thumbnailImagePaths
                    + mediaSnapshot.audioPaths
                    + mediaSnapshot.videoPaths
            )
        }

        let commit = try commitNonBiologicalScanDeletion(payloads: payloads)
        return ExpiredNonBiologicalPurgeResult(
            committedErasureCount: commit.committedErasureCount,
            deletedRecordCount: commit.deletedRecordCount,
            localMediaPaths: commit.localMediaPaths
        )
    }
}

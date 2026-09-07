import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Cloud Deletion Sync", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct CloudDeletionSyncTests {
    @Test func cloudDeletionRequiresExplicitNetworkConfirmation() {
        #expect(
            OfflineQueueManager.cloudDeletionWasConfirmed(error: nil)
        )
        #expect(
            !OfflineQueueManager.cloudDeletionWasConfirmed(
                error: MerianError.invalidResponse
            )
        )
        #expect(
            !OfflineQueueManager.cloudDeletionWasConfirmed(
                error: MerianError.httpError(
                    statusCode: 503,
                    message: "Temporary failure"
                )
            )
        )
        #expect(
            !OfflineQueueManager.cloudDeletionWasConfirmed(
                error: URLError(.notConnectedToInternet)
            )
        )
    }

    @Test func cloudDeletionRetriesNeverEnterAnUnrecoverableState() {
        for status in [
            OfflineJobStatus.needsAttention,
            .complete,
            .cancelled
        ] {
            #expect(
                OfflineQueueManager.cloudDeletionStatusRequiresRecovery(status)
            )
        }
        for status in [
            OfflineJobStatus.pending,
            .running,
            .waiting
        ] {
            #expect(
                !OfflineQueueManager.cloudDeletionStatusRequiresRecovery(status)
            )
        }

        #expect(
            OfflineQueueManager.nextCloudDeletionRetryAttempt(after: -1) == 1
        )
        #expect(
            OfflineQueueManager.nextCloudDeletionRetryAttempt(after: 0) == 1
        )
        #expect(
            OfflineQueueManager.nextCloudDeletionRetryAttempt(
                after: OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts
            ) == OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts
        )
        #expect(
            OfflineQueueManager.nextCloudDeletionRetryAttempt(after: .max)
                == OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts
        )
    }

    @Test func cloudDeletionDrainIsProcessSingleFlight() async throws {
        let manager = OfflineQueueManager.shared
        let originalContext = manager.modelContext
        let originalIsOnline = manager.isOnline
        let originalIsSyncing = manager.isCloudDeletionSyncing
        defer {
            manager.isCloudDeletionSyncing = originalIsSyncing
            manager.isOnline = originalIsOnline
            manager.modelContext = originalContext
        }

        let context = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = context
        let scanId = UUID().uuidString.lowercased()
        context.insert(PendingCloudDeletionTask(scanId: scanId))
        try context.save()
        manager.isOnline = true
        // Simulate a first foreground wake source already owning the drain.
        manager.isCloudDeletionSyncing = true

        await manager.syncPendingDeletions()

        let pending = try context.fetch(
            FetchDescriptor<PendingCloudDeletionTask>()
        )
        let jobs = try context.fetch(FetchDescriptor<OfflineJobRecord>())
        #expect(pending.map(\.scanId) == [scanId])
        #expect(jobs.isEmpty)
        #expect(manager.isCloudDeletionSyncing)
    }
}

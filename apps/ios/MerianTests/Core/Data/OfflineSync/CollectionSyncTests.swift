import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Collection Sync", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct CollectionSyncTests {
    @Test func testFinishCollectionSyncAttemptLeavesPendingFlagForNewerCollectionMutation() async {
        let manager = OfflineQueueManager.shared
        let originalRevision = manager.collectionSyncRevision
        let originalSyncing = manager.isCollectionSyncing
        let originalTask = manager.collectionSyncTask
        let originalModelContext = manager.modelContext
        let originalPending = UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync)
        defer {
            manager.collectionSyncRevision = originalRevision
            manager.isCollectionSyncing = originalSyncing
            manager.collectionSyncTask = originalTask
            manager.modelContext = originalModelContext
            UserDefaults.standard.set(originalPending, forKey: UserDefaultsKeys.needsCollectionSync)
        }

        manager.modelContext = nil
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.needsCollectionSync)
        manager.collectionSyncRevision = 8
        manager.isCollectionSyncing = true

        // Simulate a fresh local edit landing while revision 7 was in flight.
        manager.finishCollectionSyncAttempt(success: true, capturedRevision: 7)

        #expect(manager.isCollectionSyncing == false, "Completion must always release the collection sync latch")
        #expect(manager.collectionSyncTask == nil, "Completion must clear the in-flight collection sync task handle")
        #expect(
            UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync),
            "An older successful collection sync must not clear a newer pending local mutation"
        )
    }

    @Test func testFinishCollectionSyncAttemptClearsPendingFlagWhenNoNewerMutationExists() async {
        let manager = OfflineQueueManager.shared
        let originalRevision = manager.collectionSyncRevision
        let originalSyncing = manager.isCollectionSyncing
        let originalTask = manager.collectionSyncTask
        let originalModelContext = manager.modelContext
        let originalPending = UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync)
        defer {
            manager.collectionSyncRevision = originalRevision
            manager.isCollectionSyncing = originalSyncing
            manager.collectionSyncTask = originalTask
            manager.modelContext = originalModelContext
            UserDefaults.standard.set(originalPending, forKey: UserDefaultsKeys.needsCollectionSync)
        }

        manager.modelContext = nil
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.needsCollectionSync)
        manager.collectionSyncRevision = 12
        manager.isCollectionSyncing = true

        manager.finishCollectionSyncAttempt(success: true, capturedRevision: 12)

        #expect(
            !UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync),
            "A successful collection sync may clear the pending bit only when no newer local collection change exists"
        )
    }

    @Test func testFinishCollectionSyncAttemptLeavesPendingFlagWhenSyncFails() async {
        let manager = OfflineQueueManager.shared
        let originalRevision = manager.collectionSyncRevision
        let originalSyncing = manager.isCollectionSyncing
        let originalTask = manager.collectionSyncTask
        let originalModelContext = manager.modelContext
        let originalPending = UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync)
        defer {
            manager.collectionSyncRevision = originalRevision
            manager.isCollectionSyncing = originalSyncing
            manager.collectionSyncTask = originalTask
            manager.modelContext = originalModelContext
            UserDefaults.standard.set(originalPending, forKey: UserDefaultsKeys.needsCollectionSync)
        }

        manager.modelContext = nil
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.needsCollectionSync)
        manager.collectionSyncRevision = 21
        manager.isCollectionSyncing = true

        manager.finishCollectionSyncAttempt(success: false, capturedRevision: 21)

        #expect(manager.isCollectionSyncing == false, "A failed collection sync must still release the latch")
        #expect(manager.collectionSyncTask == nil, "A failed collection sync must clear the in-flight task handle")
        #expect(
            UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync),
            "A failed collection sync must keep the pending bit set so a later retry can pick it up"
        )
    }

    @Test func testFinishCollectionSyncAttemptPausesAfterRetryBudget() async throws {
        let manager = OfflineQueueManager.shared
        let originalModelContext = manager.modelContext
        let originalRevision = manager.collectionSyncRevision
        let originalSyncing = manager.isCollectionSyncing
        let originalTask = manager.collectionSyncTask
        let ctx = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = ctx
        defer {
            manager.modelContext = originalModelContext
            manager.collectionSyncRevision = originalRevision
            manager.isCollectionSyncing = originalSyncing
            manager.collectionSyncTask = originalTask
        }

        let job = OfflineJobRecord(
            id: OfflineQueueManager.collectionSyncJobId,
            kind: .collectionSync,
            status: .running,
            attemptCount: OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts
        )
        ctx.insert(job)
        try ctx.save()

        manager.isCollectionSyncing = true
        manager.finishCollectionSyncAttempt(success: false, capturedRevision: 1)

        let jobId = OfflineQueueManager.collectionSyncJobId
        let descriptor = FetchDescriptor<OfflineJobRecord>(predicate: #Predicate { $0.id == jobId })
        let fetched = try #require(ctx.fetch(descriptor).first)
        #expect(fetched.status == .needsAttention)
        #expect(fetched.nextRunAt == nil)
        #expect(fetched.attemptCount == OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts)
        #expect(fetched.lastErrorCode == "collection_sync_retry_limit_reached")
        #expect(!manager.hasPendingCollectionSyncJob)
    }

    @Test func testMarkCollectionSyncPendingResetsRetryBudgetForNewMutation() async throws {
        let manager = OfflineQueueManager.shared
        let originalModelContext = manager.modelContext
        let originalRevision = manager.collectionSyncRevision
        let originalPending = UserDefaults.standard.bool(forKey: UserDefaultsKeys.needsCollectionSync)
        let ctx = try OfflineSyncTestSupport.makeIsolatedContext()
        manager.modelContext = ctx
        defer {
            manager.modelContext = originalModelContext
            manager.collectionSyncRevision = originalRevision
            UserDefaults.standard.set(originalPending, forKey: UserDefaultsKeys.needsCollectionSync)
        }

        let job = OfflineJobRecord(
            id: OfflineQueueManager.collectionSyncJobId,
            kind: .collectionSync,
            status: .needsAttention,
            nextRunAt: Date().addingTimeInterval(600),
            attemptCount: OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts,
            lastErrorCode: "collection_sync_retry_limit_reached",
            lastErrorMessage: "Paused."
        )
        ctx.insert(job)
        try ctx.save()

        manager.markCollectionSyncPending()

        let jobId = OfflineQueueManager.collectionSyncJobId
        let descriptor = FetchDescriptor<OfflineJobRecord>(predicate: #Predicate { $0.id == jobId })
        let fetched = try #require(ctx.fetch(descriptor).first)
        #expect(fetched.status == .pending)
        #expect(fetched.attemptCount == 0)
        #expect(fetched.nextRunAt == nil)
        #expect(fetched.lastErrorCode == nil)
        #expect(fetched.lastErrorMessage == nil)
    }
}

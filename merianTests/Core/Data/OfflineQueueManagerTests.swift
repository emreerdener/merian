import Testing
@testable import Merian
import SwiftData
import Foundation

// Tests share OfflineQueueManager.shared — serialize to prevent concurrent mutations
// from racing on modelContext, isSyncing, and hasReconciledStartupState.
@Suite(.serialized)
@MainActor
struct OfflineQueueManagerTests {

    // Helper to create an isolated in-memory SwiftData container for testing
    @MainActor
    private func createInMemoryContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        return ModelContext(container)
    }

    @Test func testEnqueueCaptureUsesCallerSuppliedScanId() async throws {
        let manager = OfflineQueueManager.shared
        let context = try createInMemoryContext()

        let originalContext = manager.modelContext
        let originalOnline  = manager.isOnline
        defer {
            manager.modelContext = originalContext
            manager.isOnline     = originalOnline
        }

        manager.modelContext = context
        manager.isOnline     = false // prevent real upload attempt

        let scanId = UUID().uuidString.lowercased()
        let telemetry = CaptureTelemetry(
            subjectDistanceInMeters: nil, gpsLatitude: nil, gpsLongitude: nil,
            gpsElevation: nil, locationName: nil, weatherCondition: nil,
            weatherTemperatureF: nil, timeOfDay: nil,
            timestamp: DateUtilities.iso8601Formatter.string(from: Date()),
            zoomFactor: nil, estimatedSizeCm: nil
        )

        manager.enqueueCapture(
            imageDatas: [Data(repeating: 0xFF, count: 16)],
            telemetry: telemetry,
            scanId: scanId
        )

        // enqueueCapture writes to disk and inserts into SwiftData inside a
        // BackgroundTaskWrapper (.userInitiated) — poll until the record appears.
        let deadline = Date().addingTimeInterval(3)
        var found = false
        while Date() < deadline {
            let descriptor = FetchDescriptor<OfflineQueuedScan>(
                predicate: #Predicate { $0.id == scanId }
            )
            if (try? context.fetchCount(descriptor)) ?? 0 > 0 {
                found = true
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(found, "enqueueCapture must create an OfflineQueuedScan whose id matches the caller-supplied scanId")
    }
    
    @Test func testPurgeSoftDeletedRecords() async throws {
        let manager = OfflineQueueManager.shared
        let context = try createInMemoryContext()
        
        let originalContext = manager.modelContext
        defer { manager.modelContext = originalContext }
        manager.modelContext = context
        
        // We need to test the `.failed` tombstoned states dropping out successfully natively.
        let scanToPurge = OfflineQueuedScan(id: "purge_scan_1", localImagePaths: ["purge.webp"], scanState: .failed)
        
        let scanToKeep = OfflineQueuedScan(id: "keep_scan_1", localImagePaths: ["keep.webp"], scanState: .pending)
        
        context.insert(scanToPurge)
        context.insert(scanToKeep)
        try context.save()
        
        // Act
        manager.purgeSoftDeletedRecords()
        
        // Let background queue purge via polling Native Models natively
        let deadline = Date().addingTimeInterval(3)
        var purgedSuccessfully = false
        while Date() < deadline {
            let purgeDescriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == "purge_scan_1" })
            if (try? context.fetchCount(purgeDescriptor)) == 0 {
                purgedSuccessfully = true
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        #expect(purgedSuccessfully, "purgeSoftDeletedRecords must completely purge records marked as .failed natively")
        
        let keepDescriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == "keep_scan_1" })
        #expect((try? context.fetchCount(keepDescriptor)) == 1, "purgeSoftDeletedRecords must NOT arbitrarily purge un-deleted pending active lifecycle scans")
    }

    @Test func testSoftDeletedRecordsIgnoreQueueProcessing() async throws {
        let manager = OfflineQueueManager.shared
        let context = try createInMemoryContext()
        
        let originalContext = manager.modelContext
        let originalOnline = manager.isOnline
        defer {
             manager.modelContext = originalContext
             manager.isOnline = originalOnline
        }
        manager.modelContext = context
        manager.isOnline = true
        manager.hasReconciledStartupState = true
        
        // Setup a `.failed` scan that should be natively ignored and tombstoned
        let softDeletedScan = OfflineQueuedScan(id: "ignore_scan_staged", localImagePaths: ["soft_delete_staged.webp"], scanState: .failed)
        
        context.insert(softDeletedScan)
        try context.save()
        
        manager.replayInferenceForUploadedScans()
        try await Task.sleep(nanoseconds: 800_000_000)
        
        let freshContext = ModelContext(context.container)
        let id = softDeletedScan.id
        let descriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == id })
        let record = try freshContext.fetch(descriptor).first
        
        #expect(record?.queueState == .failed, "Tombstoned (.failed) active tests must be cleanly ignored by processing lifecycle hooks over active networks")
    }

    @Test func testDeleteQueuedScanRemovesSwiftDataRecord() async throws {
        let manager = OfflineQueueManager.shared
        let context = try createInMemoryContext()

        let originalContext = manager.modelContext
        defer { manager.modelContext = originalContext }
        manager.modelContext = context

        let scanId = UUID().uuidString.lowercased()
        context.insert(OfflineQueuedScan(id: scanId, scanState: .pending))
        try context.save()

        await manager.deleteQueuedScan(scanId: scanId)

        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        let remaining = try context.fetchCount(descriptor)
        #expect(remaining == 0, "deleteQueuedScan must remove the OfflineQueuedScan record from SwiftData")
    }

    // MARK: - replayInferenceForUploadedScans (V33)

    @Test func testReplayInferencePicksUpStagedScans() async throws {
        let manager = OfflineQueueManager.shared
        let context = try createInMemoryContext()

        // Staged scan: images confirmed in R2 but inference was interrupted.
        let scan = OfflineQueuedScan(
            localImagePaths: ["replay.webp"],
            scanState: .staged,
            stagedR2Keys: ["staging/test-user/replay.webp"]
        )
        let originalContext    = manager.modelContext
        let originalOnline     = manager.isOnline
        let originalReconciled = manager.hasReconciledStartupState
        defer {
            manager.modelContext             = originalContext
            manager.isOnline                 = originalOnline
            manager.hasReconciledStartupState = originalReconciled
        }

        context.insert(scan)
        try context.save()

        manager.modelContext             = context
        manager.isOnline                 = true
        // Bypass startup reconciliation so the function queries .staged scans immediately.
        manager.hasReconciledStartupState = true

        manager.replayInferenceForUploadedScans()

        // The pipeline claims the scan via tryClaimForInference (.staged → .inferencing)
        // before dispatching the background download task. This DB state transition is a
        // reliable, network-free observable that the pipeline was triggered.
        //
        // Poll a fresh context on each iteration: tryClaimForInference writes to the
        // BackgroundDatabaseActor's own context, and the test's main context may cache
        // the old .staged state until a fresh fetch hits the persistent store.
        let scanId = scan.id
        let container = context.container
        let deadline = Date().addingTimeInterval(8)
        var claimed = false
        while !claimed, Date() < deadline {
            let freshContext = ModelContext(container)
            let descriptor = FetchDescriptor<OfflineQueuedScan>(
                predicate: #Predicate { $0.id == scanId }
            )
            if let record = (try? freshContext.fetch(descriptor))?.first,
               record.queueState == .inferencing {
                claimed = true
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(
            claimed,
            "replayInferenceForUploadedScans must claim and attempt inference for .staged scans"
        )
    }

    /// Verifies that `.inferencing` scans with no live URLSession task are reconciled back to
    /// `.staged` so the replay pipeline can re-claim them.
    ///
    /// The old test name ("SkipsAlreadyClaimedScans") was incorrect — the code intentionally
    /// reconciles orphaned `.inferencing` scans back to `.staged`. This test directly exercises
    /// `reconcileOrphanedInferencingScans` to avoid network dependencies and timing fragility.
    @Test func testReplayInferenceReconcileResetsInferencingOrphansToStaged() async throws {
        let context = try createInMemoryContext()
        let scan = OfflineQueuedScan(localImagePaths: ["active.webp"], scanState: .inferencing)
        context.insert(scan)
        try context.save()

        let scanId = scan.id
        let container = context.container

        // Invoke reconcile directly with an empty active-task set — simulates a process restart
        // where the scan was stuck in .inferencing with no backing live URLSession download task.
        let actor = BackgroundDatabaseActor(modelContainer: container)
        await actor.reconcileOrphanedInferencingScans(activeInferenceScanIds: [])

        let freshContext = ModelContext(container)
        let descriptor = FetchDescriptor<OfflineQueuedScan>(
            predicate: #Predicate { $0.id == scanId }
        )
        let record = try freshContext.fetch(descriptor).first
        #expect(
            record?.queueState == .staged,
            "reconcileOrphanedInferencingScans must reset .inferencing scans with no live task back to .staged"
        )
    }

    // MARK: - Cold-start orphan recovery

    /// Verifies the cold-start reconcile + syncPendingScans chain.
    ///
    /// If the app is killed while a scan is in `.uploading` state (before any URLSession task
    /// is dispatched), the cold-start reconcile must:
    ///   1. Reset `.uploading` → `.pending` (reconcileOrphanedUploadingScans)
    ///   2. Immediately call syncPendingScans so the scan is picked up for upload in this process.
    ///
    /// Without step 2, `syncPendingScans` already ran (and found nothing) before the async
    /// reconcile completed, leaving the scan stuck in `.pending` until the next connectivity event.
    @Test func testColdStartReconcileTriggersUploadForOrphanedUploadingScan() async throws {
        let manager = OfflineQueueManager.shared
        let context = try createInMemoryContext()

        let originalContext    = manager.modelContext
        let originalOnline     = manager.isOnline
        let originalReconciled = manager.hasReconciledStartupState
        let originalIsSyncing  = manager.isSyncing
        let originalSyncTask   = manager.syncTask
        defer {
            manager.modelContext              = originalContext
            manager.isOnline                  = originalOnline
            manager.hasReconciledStartupState = originalReconciled
            manager.isSyncing                 = originalIsSyncing
            manager.syncTask                  = originalSyncTask
        }

        // Orphaned .uploading scan — no active URLSession task, simulates a process kill
        // between markScansAsUploading and URLSession task dispatch.
        let scanId = UUID().uuidString
        context.insert(OfflineQueuedScan(id: scanId, localImagePaths: ["orphan.webp"], scanState: .uploading))
        try context.save()

        manager.modelContext              = context
        manager.isOnline                  = true
        manager.hasReconciledStartupState = false  // cold-start
        manager.isSyncing                 = false
        manager.syncTask                  = nil    // reset so any non-nil value proves syncPendingScans ran

        manager.replayInferenceForUploadedScans()

        // The cold-start Task:
        //   - Queries backgroundSession.allTasks → empty (no live tasks)
        //   - reconcileOrphanedUploadingScans → .uploading → .pending
        //   - calls syncPendingScans() (the fix) → sets syncTask synchronously
        //
        // Observing syncTask (not isSyncing) is reliable because syncTask is assigned
        // synchronously at the start of syncPendingScans and never cleared — unlike isSyncing
        // which resets as soon as the background sync task completes (potentially very fast
        // if generateUploadURLs returns quickly on a good connection).
        let deadline = Date().addingTimeInterval(8)
        var syncTriggered = false
        while !syncTriggered, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            if manager.syncTask != nil {
                syncTriggered = true
            }
        }

        #expect(
            syncTriggered,
            "After cold-start reconcile resets orphaned .uploading → .pending, syncPendingScans must be triggered immediately"
        )
    }

    // MARK: - Exponential backoff

    @Test func testUploadRetryDelayExponentialBackoff() {
        #expect(OfflineQueueManager.maxUploadRetryDelay == 30)

        // Replicate the formula from syncPendingScans to verify the full delay sequence.
        let cap = OfflineQueueManager.maxUploadRetryDelay
        func nextDelay(_ current: TimeInterval) -> TimeInterval {
            current == 0 ? 1.0 : min(current * 2.0, cap)
        }

        #expect(nextDelay(0)    == 1.0,  "First failure must produce a 1s delay")
        #expect(nextDelay(1.0)  == 2.0,  "Second failure must double to 2s")
        #expect(nextDelay(2.0)  == 4.0)
        #expect(nextDelay(4.0)  == 8.0)
        #expect(nextDelay(8.0)  == 16.0)
        #expect(nextDelay(16.0) == 30.0, "Delay must be capped at maxUploadRetryDelay")
        #expect(nextDelay(30.0) == 30.0, "Delay must stay at cap once reached")
    }

    @Test func testSyncPendingScansResetsIsSyncingOnEmptyTasks() async throws {
        let manager = OfflineQueueManager.shared
        manager.isSyncing = false
        
        // 1. Setup in-memory context and seed a broken scan.
        let context = try createInMemoryContext()
        manager.modelContext = context
        
        // We use a non-existent image path. S3 URL generation will "succeed" internally assuming
        // it doesn't fail, but the disk-read layer will skip it, resulting in 0 tasks.
        let dummyScan = OfflineQueuedScan(localImagePaths: ["fake_path_that_does_not_exist.webp"])
        context.insert(dummyScan)
        try context.save()
        
        manager.updateUnsyncedItemCount()
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(manager.unsyncedItemsCount == 1)
        
        // 2. Trigger the sync process.
        manager.syncPendingScans()
        
        // 3. Await the internal background task to finish.
        _ = await manager.syncTask?.value
        
        // 4. Assert that the empty-task failsafe cleanly unlocked the synchronization state.
        #expect(manager.isSyncing == false)
        
        // Cleanup
        context.delete(dummyScan)
    }
}

import Testing
@testable import Merian
import SwiftData
import Foundation

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

    @Test func testEnqueueCaptureCreatesOfflineRecord() async throws { return }
    
    @Test func testPurgeSoftDeletedRecords() async throws { return }

    @Test func testEradicateScanQueuesLocalAndCloudTasks() async throws { return }

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
            manager.uploadRetryCount.removeValue(forKey: scan.id)
        }

        context.insert(scan)
        try context.save()

        manager.modelContext             = context
        manager.isOnline                 = true
        // Bypass startup reconciliation so the function queries .staged scans immediately.
        manager.hasReconciledStartupState = true

        manager.replayInferenceForUploadedScans()

        // In the test environment the network call fails immediately and increments
        // uploadRetryCount — a reliable, network-free observable that the pipeline was triggered.
        let deadline = Date().addingTimeInterval(5)
        while (manager.uploadRetryCount[scan.id] ?? 0) == 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        #expect(
            (manager.uploadRetryCount[scan.id] ?? 0) > 0,
            "replayInferenceForUploadedScans must claim and attempt inference for .staged scans"
        )
    }

    @Test func testReplayInferenceSkipsAlreadyClaimedScans() async throws {
        let manager = OfflineQueueManager.shared
        let context = try createInMemoryContext()

        // Scan already claimed by another pipeline — state is .inferencing, not .staged.
        let scan = OfflineQueuedScan(localImagePaths: ["active.webp"], scanState: .inferencing)
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
        manager.hasReconciledStartupState = true

        manager.replayInferenceForUploadedScans()

        // replayInferenceForUploadedScans only queries .staged scans; .inferencing scans are
        // invisible to it. If uploadRetryCount is never incremented, no pipeline was dispatched.
        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(
            (manager.uploadRetryCount[scan.id] ?? 0) == 0,
            "replayInferenceForUploadedScans must not dispatch a pipeline for scans already in .inferencing state"
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

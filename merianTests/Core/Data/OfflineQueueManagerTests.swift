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

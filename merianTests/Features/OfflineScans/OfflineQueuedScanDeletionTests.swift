import Testing
import SwiftData
import Foundation
@testable import Merian

@MainActor
struct OfflineQueuedScanDeletionTests {
    
    private func createIsolatedContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let context = ModelContext(container)
        return context
    }

    @Test func testDeleteQueuedScanCleansDatabaseAndDisk() async throws {
        // Arrange
        let ctx = try createIsolatedContext()
        let scanId = "test_deletion_001"
        
        // Mock image file creation on disk
        let documentsDirectory = URL.documentsDirectory
        let mockImagePath = "mock_image_delete.webp"
        let mockImageURL = documentsDirectory.appendingPathComponent(mockImagePath)
        let mockData = Data("fake_image_data".utf8)
        try mockData.write(to: mockImageURL)
        
        #expect(FileManager.default.fileExists(atPath: mockImageURL.path) == true)
        
        let queuedScan = OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image(.documents(mockImagePath))]), encoding: .utf8)
        )
        
        ctx.insert(queuedScan)
        try ctx.save()
        
        let queueManager = OfflineQueueManager.shared
        queueManager.modelContext = ctx
        
        // Ensure standard state counts
        queueManager.updateUnsyncedItemCount()
        // Wait for @MainActor Task to settle updateUnsyncedItemCount
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(queueManager.unsyncedItemsCount == 1)
        
        // Act - Call the new feature method
        await queueManager.deleteQueuedScan(scanId: scanId)
        
        // Wait for async deletion tasks (e.g. disk I/O, SwiftData save) to settle
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Assert - DB removal
        let assertDescriptor = FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == scanId })
        let items = (try? ctx.fetch(assertDescriptor)) ?? []
        #expect(items.isEmpty == true, "SwiftData entity must be fully deleted")
        
        // Assert - Count propagation
        #expect(queueManager.unsyncedItemsCount == 0, "Unsynced items count must decrement")
        
        // Assert - Disk removal
        #expect(FileManager.default.fileExists(atPath: mockImageURL.path) == false, "Local image artifact must be purged from disk")
    }
    
    @Test func testDeleteQueuedScanCancelsURLSessionTasks() async throws {
        // Arrange
        let ctx = try createIsolatedContext()
        let scanId = "test_network_cancellation_001"
        
        let queuedScan = OfflineQueuedScan(
            id: scanId,
            timestamp: Date(),
            capturedMediaJSON: nil
        )
        
        ctx.insert(queuedScan)
        try ctx.save()
        
        let queueManager = OfflineQueueManager.shared
        queueManager.modelContext = ctx
        
        // Inject a mock task into the backgroundSession manually
        let request = URLRequest(url: URL(string: "https://example.com/upload")!)
        let mockDataURL = URL.cachesDirectory.appendingPathComponent("mock_upload.webp")
        try? Data("fake".utf8).write(to: mockDataURL)
        let mockTask = queueManager.backgroundSession.uploadTask(with: request, fromFile: mockDataURL)
        mockTask.taskDescription = "\(scanId)_0"
        
        // Since we are mocking an in-flight upload, we must resume it to populate background tasks actively
        mockTask.resume()
        
        // To prevent network activity actually attempting, immediately suspend though it remains tracked
        mockTask.suspend()
        
        let tasksBefore = await queueManager.backgroundSession.allTasks
        #expect(tasksBefore.contains(where: { $0.taskDescription == "\(scanId)_0" }) == true)
        
        // Act
        await queueManager.deleteQueuedScan(scanId: scanId)
        
        // Give background URL Session async cancellation a tiny window to resolve
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Assert
        let tasksAfter = await queueManager.backgroundSession.allTasks
        let specificTaskStatus = tasksAfter.first(where: { $0.taskDescription == "\(scanId)_0" })?.state
        
        // URLSession keeps tracking tasks immediately post-cancel, but their state should be 'canceling' or 'completed/cancelled'
        if let state = specificTaskStatus {
            #expect(state == .canceling || state == .completed, "The specific URLSession task MUST be cancelled explicitly")
        } else {
            // Task got entirely removed which is also acceptable
            #expect(true)
        }
    }
}

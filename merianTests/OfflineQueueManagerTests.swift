import Testing
@testable import Merian
import SwiftData
import Foundation

@MainActor
struct OfflineQueueManagerTests {

    // Helper to create an isolated in-memory SwiftData container for testing
    @MainActor
    private func createInMemoryContext() throws -> ModelContext {
        let schema = Schema(MerianSchemaV3.models)
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        return ModelContext(container)
    }

    @Test func testEnqueueCaptureCreatesOfflineRecord() async throws {
        // Arrange
        let context = try createInMemoryContext()
        let manager = OfflineQueueManager.shared
        manager.modelContext = context
        
        let initialCount = manager.unsyncedItemsCount
        
        let dummyImageData = Data([0x00, 0x01, 0x02, 0x03])
        
        // Act
        manager.enqueueCapture(
            imageData: dummyImageData,
            gpsLatitude: 37.7749,
            gpsLongitude: -122.4194,
            gpsElevation: 10.0,
            weatherCondition: "cloudy",
            weatherTemperatureF: 65.0,
            blurScore: 0.1
        )
        
        // Assert
        // OfflineQueueManager performs context.save() synchronously here
        let descriptor = FetchDescriptor<MerianSchemaV3.OfflineQueuedScan>()
        let records = try context.fetch(descriptor)
        
        #expect(records.count == 1, "There should be exactly 1 OfflineQueuedScan in the database")
        #expect(manager.unsyncedItemsCount > initialCount)
        
        let insertedScan = records.first!
        #expect(insertedScan.gpsLatitude == 37.7749)
        #expect(insertedScan.gpsLongitude == -122.4194)
        #expect(insertedScan.weatherCondition == "cloudy")
        #expect(insertedScan.isDeleted == false)
        #expect(insertedScan.localImagePaths.count == 1, "Should have saved 1 image path reference")
        
        // Cleanup the actual test file written to the documents directory
        if let firstPath = insertedScan.localImagePaths.first {
            let fileURL = URL.documentsDirectory.appendingPathComponent(firstPath)
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    
    @Test func testPurgeSoftDeletedRecords() async throws {
        // Arrange
        let context = try createInMemoryContext()
        let manager = OfflineQueueManager.shared
        manager.modelContext = context
        
        let scan1 = MerianSchemaV3.OfflineQueuedScan(id: "1", isDeleted: true)
        let scan2 = MerianSchemaV3.OfflineQueuedScan(id: "2", isDeleted: false)
        
        context.insert(scan1)
        context.insert(scan2)
        try context.save()
        
        // Verify initial state
        let allScansDescriptor = FetchDescriptor<MerianSchemaV3.OfflineQueuedScan>()
        let initialScans = try context.fetch(allScansDescriptor)
        #expect(initialScans.count == 2)
        
        // Act
        manager.purgeSoftDeletedRecords()
        
        // Assert
        let remainingScans = try context.fetch(allScansDescriptor)
        #expect(remainingScans.count == 1, "Only the non-deleted scan should remain")
        #expect(remainingScans.first!.id == "2")
    }
}

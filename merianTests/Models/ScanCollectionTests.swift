import Testing
import SwiftData
import Foundation
@testable import Merian

@Suite("ScanCollection SwiftData Operations")
@MainActor
struct ScanCollectionTests {
    let container: ModelContainer
    let context: ModelContext
    
    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try ModelContainer(
            for: LocalScanRecord.self, ScanCollection.self,
            OfflineQueuedScan.self, PendingCloudDeletionTask.self,
            configurations: config
        )
        self.context = container.mainContext
    }
    
    @Test("Creates a new collection securely in SwiftData")
    func testCollectionCreation() throws {
        // Arrange
        let collectionName = "Expedition Alpha"
        
        // Act
        let collection = ScanCollection(name: collectionName)
        context.insert(collection)
        try context.save()
        
        // Assert
        let fetchDescriptor = FetchDescriptor<ScanCollection>()
        let fetchedCollections = try context.fetch(fetchDescriptor)
        
        #expect(fetchedCollections.count == 1)
        #expect(fetchedCollections.first?.name == collectionName)
        #expect(fetchedCollections.first?.id != nil)
        #expect(fetchedCollections.first?.createdAt != nil)
    }
    
    @Test("Updates a collection's name implicitly overriding its state")
    func testCollectionRename() throws {
        // Arrange
        let originalName = "Old Collection"
        let newName = "New Collection"
        let collection = ScanCollection(name: originalName)
        context.insert(collection)
        try context.save()
        
        // Act
        collection.name = newName
        try context.save()
        
        // Assert
        let fetchDescriptor = FetchDescriptor<ScanCollection>()
        let fetchedCollections = try context.fetch(fetchDescriptor)
        
        #expect(fetchedCollections.first?.name == newName)
    }
    
    @Test("Hard deletes a collection explicitly off disk")
    func testCollectionDeletion() throws {
        // Arrange
        let collection = ScanCollection(name: "Delete Me")
        context.insert(collection)
        try context.save()
        
        var descriptor = FetchDescriptor<ScanCollection>()
        #expect(try context.fetch(descriptor).count == 1)
        
        // Act
        context.delete(collection)
        try context.save()
        
        // Assert
        descriptor = FetchDescriptor<ScanCollection>()
        #expect(try context.fetch(descriptor).count == 0)
    }
    
    @Test("Binds ScanCollection natively to a LocalScanRecord many-to-many relationship")
    func testCollectionScanRelationship() throws {
        // Arrange
        let collection = ScanCollection(name: "My Bugs")
        let scan = LocalScanRecord(
            id: UUID().uuidString,
            speciesId: UUID().uuidString,
            scientificName: "Testus buggus",
            commonName: "Test Bug",
            insightDescription: "A bug for testing.",
            timestamp: Date(),
            localImagePath: nil,
            semanticTags: [],
            isPoisonous: false,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "Testing",
            wikipediaUrl: nil,
            referenceImageUrl: nil,
            confidenceScore: 0.99,
            locationName: "Test Lab",
            weatherCondition: "Clear",
            weatherTemperatureF: 72.0
        )
        
        context.insert(collection)
        context.insert(scan)
        
        // Act
        if collection.scans == nil {
            collection.scans = []
        }
        collection.scans?.append(scan)
        
        if scan.collections == nil {
            scan.collections = []
        }
        scan.collections?.append(collection)
        
        try context.save()
        
        // Assert
        let collectionDescriptor = FetchDescriptor<ScanCollection>()
        let fetchedCollections = try context.fetch(collectionDescriptor)
        
        #expect(fetchedCollections.first?.scans?.count == 1)
        #expect(fetchedCollections.first?.scans?.first?.scientificName == "Testus buggus")
        
        let scanDescriptor = FetchDescriptor<LocalScanRecord>()
        let fetchedScans = try context.fetch(scanDescriptor)
        
        #expect(fetchedScans.first?.collections?.count == 1)
        #expect(fetchedScans.first?.collections?.first?.name == "My Bugs")
    }
}

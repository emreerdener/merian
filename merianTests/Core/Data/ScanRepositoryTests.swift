import Testing
import SwiftData
import Foundation
@testable import Merian

@MainActor
struct ScanRepositoryTests {
    
    // Helper to create an isolated SwiftData container caching out to disk due to iOS 18 simulator array appending bugs.
    @MainActor
    private func createIsolatedContext() throws -> ModelContext {
        let schema = Schema(MerianSchemaV9.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let modelConfiguration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let context = ModelContext(container)
        ScanRepository.shared.configure(with: context) // Mock offline dependencies
        return context
    }

    @Test func testCollectionRelationshipsRetainProperReferences() async throws {
        // Arrange
        let ctx = try createIsolatedContext()
        
        let record = LocalScanRecord(
            speciesId: "test-species",
            scientificName: "Test scientific",
            commonName: "Test common",
            insightDescription: "Test description"
        )
        ctx.insert(record)
        
        let collection = ScanCollection(name: "Test Extracted Collection")
        ctx.insert(collection)
        
        // Assert bi-directional boundary execution without triggering SwiftData duplicate tracking loops
        collection.scans?.append(record)
        record.collections?.append(collection)
        
        try ctx.save()
        
        // Verify relationship boundaries effectively bounded the model properly natively
        let collectionId = collection.id
        let refetchedCollectionDescriptor = FetchDescriptor<ScanCollection>(predicate: #Predicate { $0.id == collectionId })
        let fetchedCollection = try ctx.fetch(refetchedCollectionDescriptor).first
        
        #expect(fetchedCollection?.scans?.count == 1, "Collection must append LocalScanRecord instance locally without failure")
        #expect(fetchedCollection?.scans?.first?.id == record.id, "Appended scan must match original insertion bounds")
        
        let recordId = record.id
        let refetchedRecordDescriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == recordId })
        let fetchedRecord = try ctx.fetch(refetchedRecordDescriptor).first
        
        #expect(fetchedRecord?.collections?.count == 1, "Record must inversely append ScanCollection")
        #expect(fetchedRecord?.collections?.first?.id == collection.id, "Inversely appended collection must match bounds")
    }
    
    @Test func testArchiveMigrationBooleanTogglesCorrectly() async throws {
        // Arrange
        let ctx = try createIsolatedContext()
        
        let record = LocalScanRecord(
            speciesId: "test-species-archive",
            scientificName: "Archive Phase",
            commonName: "Test Archive state",
            insightDescription: "Archive test scope"
        )
        ctx.insert(record)
        
        // Base state assertion ensures the boolean initializes as `false` cleanly matching 90-day retention policies
        #expect(record.isLocallyArchived == false, "Initial scan mapping must NOT be locally archived")
        
        // Act: Mutate manually migrating execution out of the 90-day bounds
        record.isLocallyArchived = true
        try ctx.save()
        
        // Assert permanence in storage
        let recordId = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == recordId })
        let fetched = try ctx.fetch(descriptor).first
        
        #expect(fetched?.isLocallyArchived == true, "Scan model must persist locally_archived flag reliably beyond offline boundaries")
    }
}

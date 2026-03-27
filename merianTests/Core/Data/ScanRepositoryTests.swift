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

    // Helper for V15-schema tests (aiReasoning, habitatDescription, globalDistributionRegionsJson).
    @MainActor
    private func createV15IsolatedContext() throws -> ModelContext {
        let schema = Schema(MerianSchemaV15.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let modelConfiguration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let context = ModelContext(container)
        ScanRepository.shared.configure(with: context)
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

    // MARK: - V15 Premium Insights persistence

    @Test func testV15AiReasoningPersistsRoundTrip() async throws {
        let ctx = try createV15IsolatedContext()
        let record = LocalScanRecord(
            speciesId: "v15-species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly",
            insightDescription: "The orange-black wing pattern is diagnostic.",
            aiReasoning: "Orange and black wing pattern with white marginal spots confirms Danaus plexippus."
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try ctx.fetch(descriptor).first

        #expect(fetched?.aiReasoning?.contains("Danaus plexippus") == true)
    }

    @Test func testV15HabitatDescriptionPersistsRoundTrip() async throws {
        let ctx = try createV15IsolatedContext()
        let record = LocalScanRecord(
            speciesId: "v15-habitat",
            scientificName: "Photinus pyralis",
            commonName: "Firefly",
            insightDescription: "A bioluminescent beetle.",
            habitatDescription: "Warm temperate meadows and forest edges near standing water."
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try ctx.fetch(descriptor).first

        #expect(fetched?.habitatDescription?.contains("meadows") == true)
    }

    @Test func testV15GlobalDistributionRegionsJsonRoundTrip() async throws {
        let ctx = try createV15IsolatedContext()
        let regions = ["US-TX", "US-CA", "MX"]
        let regionsJson = try String(data: JSONEncoder().encode(regions), encoding: .utf8)!
        let record = LocalScanRecord(
            speciesId: "v15-regions",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly",
            insightDescription: "A migratory butterfly.",
            globalDistributionRegionsJson: regionsJson
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try ctx.fetch(descriptor).first
        let fetchedJson = try #require(fetched?.globalDistributionRegionsJson)
        let decoded = try JSONDecoder().decode([String].self, from: Data(fetchedJson.utf8))

        #expect(decoded == regions)
    }

    @Test func testV15PremiumFieldsDefaultToNilOnLegacyRecord() async throws {
        let ctx = try createV15IsolatedContext()
        let record = LocalScanRecord(
            speciesId: "v15-legacy",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            insightDescription: "A medium-sized mammal."
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try ctx.fetch(descriptor).first

        #expect(fetched?.aiReasoning == nil, "aiReasoning must default to nil for records without premium data")
        #expect(fetched?.habitatDescription == nil, "habitatDescription must default to nil")
        #expect(fetched?.globalDistributionRegionsJson == nil, "globalDistributionRegionsJson must default to nil")
    }
}

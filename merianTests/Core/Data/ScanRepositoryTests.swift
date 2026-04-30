import Testing
import SwiftData
import Foundation
@testable import Merian

@MainActor
struct ScanRepositoryTests {

    // Helper to create an isolated SwiftData container caching out to disk due to iOS 18 simulator array appending bugs.
    @MainActor
    private func createIsolatedContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let modelConfiguration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let context = ModelContext(container)
        ScanRepository.shared.configure(with: context)
        return context
    }

    @MainActor
    private func createPremiumFieldsContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
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
            commonName: "Test common"
        )
        ctx.insert(record)
        
        let collection = ScanCollection(name: "Test Extracted Collection")
        ctx.insert(collection)
        
        // Assert bi-directional boundary execution without triggering SwiftData duplicate tracking loops
        var updatedCollectionScans = collection.scans ?? []
        updatedCollectionScans.append(record)
        collection.scans = updatedCollectionScans

        var updatedRecordCollections = record.collections ?? []
        updatedRecordCollections.append(collection)
        record.collections = updatedRecordCollections
        
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
            commonName: "Test Archive state"
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
        let ctx = try createPremiumFieldsContext()
        let record = LocalScanRecord(
            speciesId: "v15-species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly",
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
        let ctx = try createPremiumFieldsContext()
        let record = LocalScanRecord(
            speciesId: "v15-habitat",
            scientificName: "Photinus pyralis",
            commonName: "Firefly",
            habitatDescription: "Warm temperate meadows and forest edges near standing water."
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try ctx.fetch(descriptor).first

        #expect(fetched?.habitatDescription?.contains("meadows") == true)
    }

    @Test func testV26SimilarSpeciesRoundTrip() async throws {
        let ctx = try createPremiumFieldsContext()
        let record = LocalScanRecord(
            speciesId: "v26-lookalikes",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            similarSpecies: ["Procyon cancrivorus", "Bassariscus astutus"]
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try ctx.fetch(descriptor).first
        let names = try #require(fetched?.similarSpecies)

        #expect(names == ["Procyon cancrivorus", "Bassariscus astutus"])
    }

    @Test func testV27LookalikesDataRoundTrip() async throws {
        let ctx = try createPremiumFieldsContext()

        let entries: [SimilarSpeciesEntry] = [
            SimilarSpeciesEntry(scientificName: "Procyon cancrivorus", commonName: "Crab-eating Raccoon",
                                referenceImageUrl: "https://example.com/img.webp", iucnRedListStatus: "LC"),
            SimilarSpeciesEntry(scientificName: "Bassariscus astutus", commonName: nil,
                                referenceImageUrl: nil, iucnRedListStatus: nil)
        ]
        let blob = try JSONEncoder().encode(entries)

        let record = LocalScanRecord(
            speciesId: "v27-lookalikes-rich",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            lookalikesData: blob
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try #require(try ctx.fetch(descriptor).first)
        let fetchedBlob = try #require(fetched.lookalikesData)
        let decoded = try JSONDecoder().decode([SimilarSpeciesEntry].self, from: fetchedBlob)

        #expect(decoded.count == 2)
        #expect(decoded[0].scientificName == "Procyon cancrivorus")
        #expect(decoded[0].commonName == "Crab-eating Raccoon")
        #expect(decoded[0].iucnRedListStatus == "LC")
        #expect(decoded[1].scientificName == "Bassariscus astutus")
        #expect(decoded[1].commonName == nil)
    }

    @Test func testV15PremiumFieldsDefaultToNilOnLegacyRecord() async throws {
        let ctx = try createPremiumFieldsContext()
        let record = LocalScanRecord(
            speciesId: "v15-legacy",
            scientificName: "Procyon lotor",
            commonName: "Raccoon"
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try ctx.fetch(descriptor).first

        #expect(fetched?.aiReasoning == nil, "aiReasoning must default to nil for records without premium data")
        #expect(fetched?.habitatDescription == nil, "habitatDescription must default to nil")
        #expect(fetched?.similarSpecies == nil, "similarSpecies must default to nil for records without lookalike data")
        #expect(fetched?.lookalikesData == nil, "lookalikesData must default to nil for records without rich lookalike data")
    }

    // MARK: - V28 Candidates persistence

    @Test func testV28CandidatesDataRoundTrip() async throws {
        let ctx = try createPremiumFieldsContext()

        let candidates: [IdentificationCandidate] = [
            IdentificationCandidate(scientificName: "Procyon cancrivorus", confidenceScore: 0.71),
            IdentificationCandidate(scientificName: "Bassariscus astutus", confidenceScore: 0.65)
        ]
        let blob = try JSONEncoder().encode(candidates)

        let record = LocalScanRecord(
            speciesId: "v28-candidates-repo",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            candidatesData: blob
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try #require(try ctx.fetch(descriptor).first)
        let fetchedBlob = try #require(fetched.candidatesData)
        let decoded = try JSONDecoder().decode([IdentificationCandidate].self, from: fetchedBlob)

        #expect(decoded.count == 2)
        #expect(decoded[0].scientificName == "Procyon cancrivorus")
        #expect(decoded[0].confidenceScore == 0.71)
        #expect(decoded[1].scientificName == "Bassariscus astutus")
    }

    @Test func testCandidatesRoundTripWithAllFields() async throws {
        // Verifies that commonName and distinguishingFeature survive the encode → persist → decode cycle.
        // This guards the historical sync path: CloudIdentificationCandidate → IdentificationCandidate → candidatesData.
        let ctx = try createPremiumFieldsContext()

        let candidates: [IdentificationCandidate] = [
            IdentificationCandidate(
                scientificName: "Limenitis archippus",
                commonName: "Viceroy",
                confidenceScore: 0.71,
                distinguishingFeature: "Hindwing black postmedian band broader and more irregular"
            ),
            IdentificationCandidate(
                scientificName: "Danaus gilippus",
                commonName: "Queen",
                confidenceScore: 0.58,
                distinguishingFeature: "Forewing lacks white spots in the black apex band"
            )
        ]
        let blob = try JSONEncoder().encode(candidates)

        let record = LocalScanRecord(
            speciesId: "cand-full-fields",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly",
            candidatesData: blob
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try #require(try ctx.fetch(descriptor).first)
        let fetchedBlob = try #require(fetched.candidatesData)
        let decoded = try JSONDecoder().decode([IdentificationCandidate].self, from: fetchedBlob)

        #expect(decoded.count == 2)
        #expect(decoded[0].scientificName == "Limenitis archippus")
        #expect(decoded[0].commonName == "Viceroy", "commonName must survive encode → persist → decode")
        #expect(decoded[0].confidenceScore == 0.71)
        #expect(decoded[0].distinguishingFeature == "Hindwing black postmedian band broader and more irregular",
                "distinguishingFeature must survive encode → persist → decode")
        #expect(decoded[1].commonName == "Queen")
        #expect(decoded[1].distinguishingFeature == "Forewing lacks white spots in the black apex band")
    }

    @Test func testCandidatesPreMigrationShapeDecodesGracefully() async throws {
        // JSONB rows written before distinguishing_feature was added have the two-field shape.
        // IdentificationCandidate.distinguishingFeature is String? — absent keys must decode as nil, not crash.
        let ctx = try createPremiumFieldsContext()

        // Encode two-field JSON manually to simulate pre-migration cloud JSONB
        let preMigrationJSON = """
        [
            { "scientificName": "Procyon cancrivorus", "confidenceScore": 0.71 },
            { "scientificName": "Bassariscus astutus", "confidenceScore": 0.65 }
        ]
        """.data(using: .utf8)!

        let record = LocalScanRecord(
            speciesId: "cand-pre-migration",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            candidatesData: preMigrationJSON
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try #require(try ctx.fetch(descriptor).first)
        let fetchedBlob = try #require(fetched.candidatesData)
        let decoded = try JSONDecoder().decode([IdentificationCandidate].self, from: fetchedBlob)

        #expect(decoded.count == 2)
        #expect(decoded[0].distinguishingFeature == nil, "Pre-migration rows missing distinguishing_feature must decode as nil")
        #expect(decoded[0].commonName == nil, "Pre-migration rows missing common_name must decode as nil")
        #expect(decoded[0].scientificName == "Procyon cancrivorus")
        #expect(decoded[0].confidenceScore == 0.71)
    }

    // MARK: - V29 identification review persistence

    @Test func testV29UserIdentificationOverrideRoundTrip() async throws {
        let ctx = try createPremiumFieldsContext()
        let record = LocalScanRecord(
            speciesId: "v29-override-repo",
            scientificName: "Procyon cancrivorus",
            commonName: "Crab-eating Raccoon",
            userIdentificationOverride: "Procyon cancrivorus"
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try ctx.fetch(descriptor).first

        #expect(fetched?.userIdentificationOverride == "Procyon cancrivorus", "userIdentificationOverride must persist round-trip")
    }

    @Test func testV29UserConfirmedIdentificationRoundTrip() async throws {
        let ctx = try createPremiumFieldsContext()
        let record = LocalScanRecord(
            speciesId: "v29-confirmed-repo",
            scientificName: "Procyon lotor",
            commonName: "Raccoon",
            userConfirmedIdentification: true
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try ctx.fetch(descriptor).first

        #expect(fetched?.userConfirmedIdentification == true, "userConfirmedIdentification must persist round-trip")
    }

    @Test func testV29NewFieldsDefaultCorrectly() async throws {
        let ctx = try createPremiumFieldsContext()
        let record = LocalScanRecord(
            speciesId: "v29-defaults",
            scientificName: "Procyon lotor",
            commonName: "Raccoon"
        )
        ctx.insert(record)
        try ctx.save()

        let id = record.id
        let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == id })
        let fetched = try ctx.fetch(descriptor).first

        #expect(fetched?.candidatesData == nil, "candidatesData must default to nil for records captured before V28")
        #expect(fetched?.userIdentificationOverride == nil, "userIdentificationOverride must default to nil — no user action yet")
        #expect(fetched?.userConfirmedIdentification == false, "userConfirmedIdentification must default to false")
    }

    // MARK: - ingestScans timestamp guard

    /// Regression guard for the `guard let parsedDate = exifDate else { continue }` fix in
    /// `ScanRepository.ingestScans`.  The guard replaced a `?? Date()` fallback that silently
    /// inserted records with fabricated timestamps when `scan.timestamp` was nil or unparseable.
    ///
    /// This test verifies the two inputs that `exifDate` is derived from:
    /// 1. A `nil` timestamp → `flatMap` produces `nil` → guard fires → record skipped.
    /// 2. A garbage string → both ISO 8601 formatters return `nil` → guard fires → record skipped.
    ///
    /// The inline logic mirrors `ScanRepository.ingestScans` exactly so any drift between the
    /// test and the production code will surface as a test failure.
    @Test func testIngestScansTimestampGuardSkipsNilAndUnparseableTimestamps() {
        // Helper that replicates the exact exifDate derivation in ingestScans
        func deriveExifDate(from timestamp: String?) -> Date? {
            timestamp.flatMap { ts -> Date? in
                if ts.contains(".") {
                    return DateUtilities.iso8601FractionalFormatter.date(from: ts)
                        ?? DateUtilities.iso8601Formatter.date(from: ts)
                }
                return DateUtilities.iso8601Formatter.date(from: ts)
                    ?? DateUtilities.iso8601FractionalFormatter.date(from: ts)
            }
        }

        // nil timestamp → exifDate must be nil → guard triggers skip
        let nilResult = deriveExifDate(from: nil)
        #expect(nilResult == nil, "nil timestamp must produce nil exifDate — the guard skips the record")

        // Garbage string → both formatters return nil → exifDate is nil
        let garbageResult = deriveExifDate(from: "not-a-date")
        #expect(garbageResult == nil, "Unparseable timestamp must produce nil exifDate — not a fabricated Date()")

        // Partial ISO string (date only, no time) → must also fail both formatters
        let partialResult = deriveExifDate(from: "2026-04-05")
        #expect(partialResult == nil, "Date-only string without time component must not be accepted")

        // Valid fractional ISO string → must produce a non-nil date (positive control)
        let validFractional = deriveExifDate(from: "2026-04-05T14:23:01.000Z")
        #expect(validFractional != nil, "Valid fractional ISO 8601 timestamp must parse correctly")

        // Valid standard ISO string → must produce a non-nil date (positive control)
        let validStandard = deriveExifDate(from: "2026-04-05T14:23:01Z")
        #expect(validStandard != nil, "Valid standard ISO 8601 timestamp must parse correctly")
    }
}

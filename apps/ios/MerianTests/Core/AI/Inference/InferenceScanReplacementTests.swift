import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
@Suite("Inference Scan Replacement")
struct InferenceScanReplacementTests {
    @Test func onlyPersistedOutcomesAuthorizeReplacement() throws {
        let context = try makeContext()
        let original = try insertRecord(id: "original", into: context)
        let replacement = try insertRecord(id: "replacement", into: context)
        original.customTags = ["garden"]
        try context.save()

        for outcome in [
            InferenceLiveResultService.Outcome.persistenceRejected,
            .completedWithoutRecord(result(id: replacement.id, confidence: 0))
        ] {
            #expect(InferenceScanReplacement.transferMetadata(
                from: original.id, after: outcome, modelContext: context
            ) == nil)
            #expect(replacement.customTags.isEmpty)
        }
        #expect(try context.fetchCount(FetchDescriptor<LocalScanRecord>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<PendingCloudDeletionTask>()) == 0)
    }

    @Test(arguments: [nil, "", "   ", "original", "ORIGINAL", "missing"] as [String?])
    func invalidOrMissingReplacementPreservesOriginal(replacementId: String?) throws {
        let context = try makeContext()
        let original = try insertRecord(id: "original", into: context)
        #expect(InferenceScanReplacement.transferMetadata(
            from: original.id,
            after: .persisted(result(id: replacementId)),
            modelContext: context
        ) == nil)
        #expect(try context.fetchCount(FetchDescriptor<LocalScanRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<PendingCloudDeletionTask>()) == 0)
    }

    @Test func pendingReplacementInsertIsNotDurableProof() throws {
        let context = try makeContext()
        let original = try insertRecord(id: "original", into: context)
        let replacement = LocalScanRecord(
            id: "replacement", speciesId: "replacement-species", scientificName: "Unknown", commonName: "Test subject"
        )
        context.insert(replacement)

        #expect(InferenceScanReplacement.transferMetadata(
            from: original.id,
            after: .persisted(result(id: replacement.id)),
            modelContext: context
        ) == nil)
        #expect(context.hasChanges)
        let reader = ModelContext(context.container)
        #expect(try reader.fetchCount(FetchDescriptor<LocalScanRecord>()) == 1)
    }

    @Test func missingOriginalOrContextDoesNotMutateReplacement() throws {
        let context = try makeContext()
        let replacement = try insertRecord(id: "replacement", into: context)
        for originalId: String? in [nil, "", "missing"] {
            #expect(InferenceScanReplacement.transferMetadata(
                from: originalId,
                after: .persisted(result(id: replacement.id)),
                modelContext: context
            ) == nil)
        }
        #expect(InferenceScanReplacement.transferMetadata(
            from: "original", after: .persisted(result(id: replacement.id)), modelContext: nil
        ) == nil)
        #expect(!context.hasChanges)
    }

    @Test(arguments: [false, true])
    func metadataIsDurableBeforeDeletionAndReviewStateResets(hasReplacementNotes: Bool) throws {
        let context = try makeContext()
        let original = try insertRecord(id: "original", into: context)
        let replacement = try insertRecord(id: "replacement", into: context)
        let collection = ScanCollection(name: "Garden")
        context.insert(collection)
        original.collections = [collection]
        original.customTags = ["backyard", "spring"]
        original.fieldNotes = "  Original field note  "
        original.userIdentificationOverride = "Original identification"
        original.userConfirmedIdentification = true
        original.isFlagged = true
        replacement.fieldNotes = hasReplacementNotes ? "Replacement field note" : " \n "
        try context.save()

        let approvedOriginal = InferenceScanReplacement.transferMetadata(
            from: original.id,
            after: .persisted(result(id: replacement.id)),
            modelContext: context
        )

        #expect(approvedOriginal === original)
        let reader = ModelContext(context.container)
        let persisted = try #require(reader.fetch(FetchDescriptor<LocalScanRecord>()).first { $0.id == replacement.id })
        #expect(persisted.customTags == ["backyard", "spring"])
        #expect(persisted.collections?.map(\.id) == [collection.id])
        #expect(persisted.fieldNotes == (hasReplacementNotes ? "Replacement field note" : "  Original field note  "))
        #expect(persisted.userIdentificationOverride == nil)
        #expect(!persisted.userConfirmedIdentification)
        #expect(!persisted.isFlagged)
        #expect(try reader.fetchCount(FetchDescriptor<LocalScanRecord>()) == 2)
        #expect(try reader.fetchCount(FetchDescriptor<PendingCloudDeletionTask>()) == 0)
    }

    @Test func saveFailureRestoresStagedValuesWithoutDiscardingUserEdits() throws {
        let context = try makeContext()
        let original = try insertRecord(id: "original", into: context)
        let replacement = try insertRecord(id: "replacement", into: context)
        original.customTags = ["original-tag"]
        original.fieldNotes = "Original note"
        replacement.customTags = ["replacement-tag"]
        let originalCollection = ScanCollection(name: "Original collection")
        let replacementCollection = ScanCollection(name: "Replacement collection")
        context.insert(originalCollection)
        context.insert(replacementCollection)
        original.collections = [originalCollection]
        replacement.collections = [replacementCollection]
        try context.save()
        original.fieldNotes = "New unsaved user note"

        let approvedOriginal = InferenceScanReplacement.transferMetadata(
            from: original.id,
            after: .persisted(result(id: replacement.id)),
            modelContext: context,
            saveMetadata: { _ in throw SaveFailure.expected }
        )

        #expect(approvedOriginal == nil)
        #expect(replacement.customTags == ["replacement-tag"])
        #expect(replacement.fieldNotes == nil)
        #expect(replacement.collections?.map(\.id) == [replacementCollection.id])
        #expect(original.fieldNotes == "New unsaved user note")
        let reader = ModelContext(context.container)
        #expect(try reader.fetchCount(FetchDescriptor<LocalScanRecord>()) == 2)
        #expect(try reader.fetchCount(FetchDescriptor<PendingCloudDeletionTask>()) == 0)
    }

    private enum SaveFailure: Error { case expected }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func insertRecord(id: String, into context: ModelContext) throws -> LocalScanRecord {
        let record = LocalScanRecord(
            id: id, speciesId: "\(id)-species", scientificName: "Unknown", commonName: "Test subject"
        )
        context.insert(record)
        try context.save()
        return record
    }

    private func result(id: String?, confidence: Double = 0.95) -> InferenceLiveResultService.CompletedResult {
        .init(
            speciesData: SpeciesData(
                scanId: id, commonName: "Test subject", scientificName: "Unknown",
                insightData: InsightData(aiReasoning: "Test observation", hazardType: "none"),
                confidenceScore: confidence, isBiological: false
            ),
            isNewDiscovery: false, savedImagePaths: [], planUsed: nil
        )
    }
}

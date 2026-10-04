import Foundation
import SwiftData
import Testing

@testable import Merian

@Suite("Field Notes Repository")
@MainActor
struct FieldNotesRepositoryTests {
    private var dependencies: FieldNotesRepository.Dependencies {
        .init(allowsMutation: { true }, ownerID: { UUID(uuidString: "20000000-0000-4000-8000-000000000001") }, didCommit: { _ in })
    }
    @Test func closedAdmissionPreservesNoteAndCreatesNoOperation() throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture", fieldNotes: "Before")
        context.insert(record)
        try context.save()
        var fenced = dependencies
        fenced.allowsMutation = { false }
        #expect(!FieldNotesRepository.setFieldNotes("After", for: record.id, modelContext: context, dependencies: fenced))
        #expect(record.fieldNotes == "Before")
        #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
    }

    @Test func deletedActiveRecordFallsBackToLegacyBridge() async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "deleted_field_notes_species",
            scientificName: "Deleted specimen",
            commonName: "Deleted scan",
            fieldNotes: "Original note"
        )

        context.insert(record)
        try context.save()

        let recordID = record.id
        let bridgedNote = "Recovered bridge note"
        FieldNotesStore.setFieldNotes(bridgedNote, for: recordID)
        defer { FieldNotesStore.setFieldNotes(nil, for: recordID) }

        // This suite owns note fallback after a local deletion, not the
        // repository's upload tombstone or cloud-deletion workers.
        context.delete(record)
        try context.save()

        let resolvedNotes = FieldNotesRepository.fieldNotes(
            for: recordID,
            modelContext: context, dependencies: dependencies
        )

        #expect(resolvedNotes == bridgedNote)
    }

    @Test func legacyBridgePromotesIntoLocalRecord() async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "legacy_field_notes_species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch"
        )
        let legacyNotes = "Legacy bridged note"

        context.insert(record)
        try context.save()
        FieldNotesStore.setFieldNotes(legacyNotes, for: record.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: record.id) }

        let resolvedNotes = FieldNotesRepository.fieldNotes(
            for: record.id,
            modelContext: context, dependencies: dependencies
        )

        #expect(resolvedNotes == legacyNotes)
        #expect(record.fieldNotes == legacyNotes)
        #expect(FieldNotesStore.fieldNotes(for: record.id) == legacyNotes)
    }

    @Test func restoredEmptyNoteDoesNotPromoteStaleLegacyValue() throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
        context.insert(record)
        try LibraryDetailsSyncService.stage(record, ownerID: #require(dependencies.ownerID()), context: context)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        job.id = "library-details:baseline:\(record.id)"
        job.status = .complete
        try context.save()
        FieldNotesStore.setFieldNotes("Stale private note", for: record.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: record.id) }
        #expect(FieldNotesRepository.fieldNotes(for: record.id, modelContext: context, dependencies: dependencies) == nil)
        #expect(record.fieldNotes == nil)
        #expect(FieldNotesStore.fieldNotes(for: record.id) == nil)
        #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
    }

    @Test(arguments: [OfflineJobStatus.pending, .complete])
    func tagOnlyOperationDoesNotDiscardLegacyNote(status: OfflineJobStatus) throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
        record.customTags = ["tag"]
        context.insert(record)
        try LibraryDetailsSyncService.stage(record, ownerID: #require(dependencies.ownerID()), context: context)
        let job = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        job.status = status
        try context.save()
        FieldNotesStore.setFieldNotes("Legacy note", for: record.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: record.id) }
        #expect(FieldNotesRepository.fieldNotes(for: record.id, modelContext: context, dependencies: dependencies) == "Legacy note")
        #expect(record.fieldNotes == "Legacy note")
        #expect(try context.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 2)
    }

    @Test func clearingUpdatesLocalRecordAndLegacyBridge() async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "clear_field_notes_species",
            scientificName: "Amanita muscaria",
            commonName: "Fly Agaric",
            fieldNotes: "Private note to clear"
        )

        context.insert(record)
        try context.save()
        FieldNotesStore.setFieldNotes(record.fieldNotes, for: record.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: record.id) }

        FieldNotesRepository.setFieldNotes(
            "   ",
            for: record.id,
            modelContext: context, dependencies: dependencies
        )

        #expect(record.fieldNotes == nil)
        #expect(FieldNotesStore.fieldNotes(for: record.id) == nil)
    }

    @Test func unchangedLocalRecordMirrorsIntoLegacyBridge() async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "unchanged_field_notes_species",
            scientificName: "Taraxacum officinale",
            commonName: "Common Dandelion",
            fieldNotes: "Already saved locally"
        )

        context.insert(record)
        try context.save()
        FieldNotesStore.setFieldNotes(nil, for: record.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: record.id) }

        let changed = FieldNotesRepository.setFieldNotes(
            "Already saved locally",
            for: record.id,
            modelContext: context, dependencies: dependencies
        )

        #expect(!changed)
        #expect(record.fieldNotes == "Already saved locally")
        #expect(
            FieldNotesStore.fieldNotes(for: record.id) == "Already saved locally"
        )
    }

    @Test func missingSwiftDataRecordPersistsOnlyToBridge() async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let scanID = "bridge_only_field_notes_scan"

        FieldNotesStore.setFieldNotes(nil, for: scanID)
        defer { FieldNotesStore.setFieldNotes(nil, for: scanID) }

        let changed = FieldNotesRepository.setFieldNotes(
            "Bridge-only note",
            for: scanID,
            modelContext: context, dependencies: dependencies
        )

        #expect(changed)
        #expect(FieldNotesStore.fieldNotes(for: scanID) == "Bridge-only note")
    }
}

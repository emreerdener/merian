import SwiftData
import Testing

@testable import Merian

@MainActor
struct FieldNotesRepositoryTests {
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

        ScanRepository.shared.eradicateScan(
            record: record,
            modelContext: context
        )

        let resolvedNotes = FieldNotesRepository.fieldNotes(
            for: recordID,
            modelContext: context
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
            modelContext: context
        )

        #expect(resolvedNotes == legacyNotes)
        #expect(record.fieldNotes == legacyNotes)
        #expect(FieldNotesStore.fieldNotes(for: record.id) == legacyNotes)
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
            modelContext: context
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
            modelContext: context
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
            modelContext: context
        )

        #expect(changed)
        #expect(FieldNotesStore.fieldNotes(for: scanID) == "Bridge-only note")
    }
}

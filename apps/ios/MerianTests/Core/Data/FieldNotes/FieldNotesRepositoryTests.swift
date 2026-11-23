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

    @Test func legacyTagMutationCannotMaskRestoredClear() throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let ownerID = try #require(dependencies.ownerID())
        let record = LocalScanRecord(speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture")
        context.insert(record)
        try LibraryDetailsSyncService.stage(record, ownerID: ownerID, context: context)
        let baseline = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        baseline.id = "library-details:baseline:\(record.id)"
        baseline.status = .complete
        record.customTags = ["Legacy tag"]
        try LibraryDetailsSyncService.stage(record, ownerID: ownerID, context: context)
        let pending = try #require(context.fetch(FetchDescriptor<OfflineJobRecord>()).first { $0.status == .pending })
        var legacyMutation = try JSONDecoder().decode(LibraryDetailsSyncService.Mutation.self, from: Data(#require(pending.metadataJSON).utf8))
        legacyMutation.fieldNotesAuthoritative = nil
        pending.metadataJSON = String(bytes: try JSONEncoder().encode(legacyMutation), encoding: .utf8)
        try context.save()
        FieldNotesStore.setFieldNotes("Stale bridge", for: record.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: record.id) }
        try LibraryDetailsSyncService.stageLegacyDetails(context: context, ownerID: ownerID, scanID: record.id)
        #expect(FieldNotesRepository.fieldNotes(for: record.id, modelContext: context, dependencies: dependencies) == nil)
        #expect(record.fieldNotes == nil)
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

    @Test(arguments: [OfflineJobStatus.pending, .complete], [false, true])
    func savedClearSurvivesStaleBridge(status: OfflineJobStatus, laterTagEdit: Bool) async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(speciesId: "fixture", scientificName: "Fixture", commonName: "Fixture", fieldNotes: "Seed")
        context.insert(record)
        try context.save()
        let scanID = record.id
        defer { FieldNotesStore.setFieldNotes(nil, for: scanID) }
        #expect(FieldNotesRepository.setFieldNotes(nil, for: scanID, modelContext: context, dependencies: dependencies))
        if laterTagEdit {
            record.customTags = ["Later tag"]
            try LibraryDetailsSyncService.stage(record, ownerID: #require(dependencies.ownerID()), context: context)
        }
        for job in try context.fetch(FetchDescriptor<OfflineJobRecord>()) { job.status = status }
        try context.save()
        // Model a process stopping after its database save but before clearing
        // the legacy preference, then reopening before any server acknowledgment.
        FieldNotesStore.setFieldNotes("Stale seed", for: scanID)
        let reopened = ModelContext(context.container)
        try LibraryDetailsSyncService.stageLegacyDetails(context: reopened, ownerID: #require(dependencies.ownerID()), scanID: scanID)
        let restored = try #require(reopened.fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(restored.fieldNotes == nil)
        #expect(FieldNotesRepository.fieldNotes(for: scanID, modelContext: reopened, dependencies: dependencies) == nil)
        #expect(FieldNotesStore.fieldNotes(for: scanID) == nil)
        let jobs = try reopened.fetch(FetchDescriptor<OfflineJobRecord>())
        #expect(jobs.count == (laterTagEdit ? 2 : 1))
        for job in jobs {
            let mutation = try JSONDecoder().decode(LibraryDetailsSyncService.Mutation.self, from: Data(#require(job.metadataJSON).utf8))
            #expect(mutation.fieldNotes == nil)
            #expect(mutation.fieldNotesAuthoritative == true)
        }
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

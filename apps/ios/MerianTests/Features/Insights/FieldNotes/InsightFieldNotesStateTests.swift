import Combine
import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
struct InsightFieldNotesStateTests {
    @Test func testFieldNotesRepositoryDoesNotTouchDeletedActiveRecord() async throws {
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "deleted_field_notes_species",
            scientificName: "Deleted specimen",
            commonName: "Deleted scan",
            fieldNotes: "Original note"
        )

        ctx.insert(record)
        try ctx.save()

        let recordId = record.id
        let bridgedNote = "Recovered bridge note"
        FieldNotesStore.setFieldNotes(bridgedNote, for: recordId)
        defer { FieldNotesStore.setFieldNotes(nil, for: recordId) }

        ScanRepository.shared.eradicateScan(record: record, modelContext: ctx)

        let resolvedNotes = FieldNotesRepository.fieldNotes(
            for: recordId,
            modelContext: ctx
        )

        #expect(resolvedNotes == bridgedNote)
    }

    @Test func testRefreshSharedExploreStateClearsMissingCache() async throws {
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        let record = LocalScanRecord(speciesId: "shared_refresh_test", scientificName: "Quercus", commonName: "Oak")

        ctx.insert(record)
        try ctx.save()

        viewModel.fetchLocalRecord(for: record.id, modelContext: ctx)
        viewModel.state.sharedExplorePostId = "stale_post_id"

        ExploreShareStateStore.setSharedPostId(nil, for: record.id)
        viewModel.refreshSharedExploreStateFromLocalCache()

        #expect(viewModel.state.sharedExplorePostId == nil)
    }

    @Test func testLocalCacheRefreshPreservesRestoredCommunityRequestState() async throws {
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        let record = LocalScanRecord(speciesId: "community_refresh_test", scientificName: "Rosa", commonName: "Rose")

        ctx.insert(record)
        try ctx.save()

        viewModel.fetchLocalRecord(for: record.id, modelContext: ctx)
        viewModel.state.sharedCommunityIdentificationRequestId = "request_refresh_test"
        viewModel.state.sharedCommunityIdentificationStatus = .needsId

        ExploreShareStateStore.setSharedPostId(nil, for: record.id)
        viewModel.refreshSharedExploreStateFromLocalCache()

        #expect(viewModel.state.sharedCommunityIdentificationRequestId == "request_refresh_test")
        #expect(viewModel.state.sharedCommunityIdentificationStatus == .needsId)
        #expect(viewModel.state.sharedExplorePostId == nil)
    }

    @Test func testPublishedExploreFieldNotesPromoteWhenLocalRecordIsEmpty() async throws {
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        let record = LocalScanRecord(
            speciesId: "field_notes_repair_species",
            scientificName: "Quercus alba",
            commonName: "White Oak"
        )
        let notes = "Observed along the shaded creek edge."

        ctx.insert(record)
        try ctx.save()
        FieldNotesStore.setFieldNotes(nil, for: record.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: record.id) }

        viewModel.inferenceEngine = InsightSheetTestSupport.biologicalEngine(scanId: record.id)
        viewModel.bindPresentedRecord(record, modelContext: ctx)
        #expect(viewModel.fieldNotesText.isEmpty)

        viewModel.promotePublishedExploreFieldNotesIfLocalMissing(
            "  \(notes)  ",
            modelContext: ctx
        )

        #expect(viewModel.fieldNotesText == notes)
        #expect(record.fieldNotes == notes)
        #expect(FieldNotesStore.fieldNotes(for: record.id) == notes)
    }

    @Test func testPublishedExploreFieldNotesDoNotOverwriteLocalPrivateNotes() async throws {
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        let record = LocalScanRecord(
            speciesId: "field_notes_private_species",
            scientificName: "Acer rubrum",
            commonName: "Red Maple",
            fieldNotes: "Private local note"
        )

        ctx.insert(record)
        try ctx.save()
        FieldNotesStore.setFieldNotes(nil, for: record.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: record.id) }

        viewModel.inferenceEngine = InsightSheetTestSupport.biologicalEngine(scanId: record.id)
        viewModel.bindPresentedRecord(record, modelContext: ctx)
        viewModel.promotePublishedExploreFieldNotesIfLocalMissing(
            "Published Explore note",
            modelContext: ctx
        )

        #expect(viewModel.fieldNotesText == "Private local note")
        #expect(record.fieldNotes == "Private local note")
        #expect(FieldNotesStore.fieldNotes(for: record.id) == "Private local note")
    }

    @Test func testShareComposerFieldNotesSyncImmediatelyIntoInsightState() async throws {
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        let record = LocalScanRecord(
            speciesId: "share_composer_field_notes_species",
            scientificName: "Cyprinella lutrensis",
            commonName: "Red Shiner"
        )
        let notes = "Schooling in a shallow creek after rain."

        ctx.insert(record)
        try ctx.save()
        FieldNotesStore.setFieldNotes(nil, for: record.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: record.id) }

        viewModel.inferenceEngine = InsightSheetTestSupport.biologicalEngine(scanId: record.id)
        viewModel.bindPresentedRecord(record, modelContext: ctx)
        viewModel.state.dismissedFieldNotesCardScanId = record.id

        viewModel.syncComposerFieldNotes(notes, modelContext: ctx)

        #expect(viewModel.fieldNotesText == notes)
        #expect(record.fieldNotes == notes)
        #expect(FieldNotesStore.fieldNotes(for: record.id) == notes)
        #expect(viewModel.state.dismissedFieldNotesCardScanId == nil)
    }

    @Test func testFieldNotesRepositoryPromotesLegacyStoreIntoLocalRecord() async throws {
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "legacy_field_notes_species",
            scientificName: "Danaus plexippus",
            commonName: "Monarch"
        )
        let legacyNotes = "Legacy bridged note"

        ctx.insert(record)
        try ctx.save()
        FieldNotesStore.setFieldNotes(legacyNotes, for: record.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: record.id) }

        let resolvedNotes = FieldNotesRepository.fieldNotes(
            for: record.id,
            modelContext: ctx
        )

        #expect(resolvedNotes == legacyNotes)
        #expect(record.fieldNotes == legacyNotes)
        #expect(FieldNotesStore.fieldNotes(for: record.id) == legacyNotes)
    }

    @Test func testFieldNotesRepositoryClearsLocalRecordAndLegacyBridgeTogether() async throws {
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "clear_field_notes_species",
            scientificName: "Amanita muscaria",
            commonName: "Fly Agaric",
            fieldNotes: "Private note to clear"
        )

        ctx.insert(record)
        try ctx.save()
        FieldNotesStore.setFieldNotes(record.fieldNotes, for: record.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: record.id) }

        FieldNotesRepository.setFieldNotes(
            "   ",
            for: record.id,
            modelContext: ctx
        )

        #expect(record.fieldNotes == nil)
        #expect(FieldNotesStore.fieldNotes(for: record.id) == nil)
    }

    @Test func testFieldNotesRepositoryMirrorsUnchangedLocalRecordIntoLegacyBridge() async throws {
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
        let record = LocalScanRecord(
            speciesId: "unchanged_field_notes_species",
            scientificName: "Taraxacum officinale",
            commonName: "Common Dandelion",
            fieldNotes: "Already saved locally"
        )

        ctx.insert(record)
        try ctx.save()
        FieldNotesStore.setFieldNotes(nil, for: record.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: record.id) }

        let changed = FieldNotesRepository.setFieldNotes(
            "Already saved locally",
            for: record.id,
            modelContext: ctx
        )

        #expect(changed == false)
        #expect(record.fieldNotes == "Already saved locally")
        #expect(FieldNotesStore.fieldNotes(for: record.id) == "Already saved locally")
    }

    @Test func testFieldNotesRepositoryPersistsBridgeOnlyWhenNoSwiftDataRecordExists() async throws {
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
        let scanId = "bridge_only_field_notes_scan"

        FieldNotesStore.setFieldNotes(nil, for: scanId)
        defer { FieldNotesStore.setFieldNotes(nil, for: scanId) }

        let changed = FieldNotesRepository.setFieldNotes(
            "Bridge-only note",
            for: scanId,
            modelContext: ctx
        )

        #expect(changed == true)
        #expect(FieldNotesStore.fieldNotes(for: scanId) == "Bridge-only note")
    }

    @Test func testQueuedScanFieldNotesPersistToOfflineRecord() async throws {
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
        let queuedScan = OfflineQueuedScan(id: "queued_field_notes_scan")

        ctx.insert(queuedScan)
        try ctx.save()
        FieldNotesStore.setFieldNotes(nil, for: queuedScan.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: queuedScan.id) }

        let viewModel = InsightSheetViewModel(queuedContext: QueuedScanContext(from: queuedScan))
        viewModel.syncFieldNotesFromCurrentScan(modelContext: ctx)
        #expect(viewModel.currentFieldNotesScanId == queuedScan.id)
        #expect(viewModel.shouldShowFieldNotesCard == true)

        viewModel.updateFieldNotes("Queued field note", modelContext: ctx)

        #expect(viewModel.fieldNotesText == "Queued field note")
        #expect(queuedScan.fieldNotes == "Queued field note")
        #expect(FieldNotesStore.fieldNotes(for: queuedScan.id) == "Queued field note")
    }

    @Test func testFieldNotesRejectChangedPresentationIdentity() async throws {
        let ctx = try InsightSheetTestSupport.createIsolatedContext()
        let queuedScan = OfflineQueuedScan(id: "current_field_notes_scan")
        ctx.insert(queuedScan)
        try ctx.save()
        FieldNotesStore.setFieldNotes(nil, for: queuedScan.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: queuedScan.id) }

        let viewModel = InsightSheetViewModel(
            queuedContext: QueuedScanContext(from: queuedScan)
        )
        viewModel.syncFieldNotesFromCurrentScan(modelContext: ctx)

        viewModel.presentFieldNotes(expectedScanId: "previous_field_notes_scan")
        viewModel.updateFieldNotes(
            "Stale note",
            expectedScanId: "previous_field_notes_scan",
            modelContext: ctx
        )

        #expect(viewModel.state.isFieldNotesSheetPresented == false)
        #expect(viewModel.state.fieldNotesPresentationScanId == nil)
        #expect(viewModel.state.fieldNotesPresentationGeneration == nil)
        #expect(viewModel.fieldNotesText.isEmpty)
        #expect(queuedScan.fieldNotes == nil)

        viewModel.presentFieldNotes(expectedScanId: queuedScan.id)

        #expect(viewModel.state.isFieldNotesSheetPresented)
        #expect(viewModel.state.fieldNotesPresentationScanId == queuedScan.id)
        #expect(
            viewModel.state.fieldNotesPresentationGeneration ==
                viewModel.scanBoundActionGeneration
        )
    }

}

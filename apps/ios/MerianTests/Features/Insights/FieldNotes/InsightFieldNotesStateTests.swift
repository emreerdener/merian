import SwiftData
import Testing

@testable import Merian

@MainActor
struct InsightFieldNotesStateTests {
    @Test func testPublishedExploreFieldNotesPromoteWhenLocalRecordIsEmpty() async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        let record = LocalScanRecord(
            speciesId: "field_notes_repair_species",
            scientificName: "Quercus alba",
            commonName: "White Oak"
        )
        let notes = "Observed along the shaded creek edge."

        context.insert(record)
        try context.save()
        FieldNotesStore.setFieldNotes(nil, for: record.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: record.id) }

        viewModel.inferenceEngine = InsightSheetTestSupport.biologicalEngine(
            scanId: record.id
        )
        viewModel.bindPresentedRecord(record, modelContext: context)
        #expect(viewModel.fieldNotesText.isEmpty)

        viewModel.promotePublishedExploreFieldNotesIfLocalMissing(
            "  \(notes)  ",
            modelContext: context
        )

        #expect(viewModel.fieldNotesText == notes)
        #expect(record.fieldNotes == notes)
        #expect(FieldNotesStore.fieldNotes(for: record.id) == notes)
    }

    @Test func testPublishedExploreFieldNotesDoNotOverwriteLocalPrivateNotes() async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        let record = LocalScanRecord(
            speciesId: "field_notes_private_species",
            scientificName: "Acer rubrum",
            commonName: "Red Maple",
            fieldNotes: "Private local note"
        )

        context.insert(record)
        try context.save()
        FieldNotesStore.setFieldNotes(nil, for: record.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: record.id) }

        viewModel.inferenceEngine = InsightSheetTestSupport.biologicalEngine(
            scanId: record.id
        )
        viewModel.bindPresentedRecord(record, modelContext: context)
        viewModel.promotePublishedExploreFieldNotesIfLocalMissing(
            "Published Explore note",
            modelContext: context
        )

        #expect(viewModel.fieldNotesText == "Private local note")
        #expect(record.fieldNotes == "Private local note")
        #expect(
            FieldNotesStore.fieldNotes(for: record.id) == "Private local note"
        )
    }

    @Test func testShareComposerFieldNotesSyncImmediatelyIntoInsightState() async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        let record = LocalScanRecord(
            speciesId: "share_composer_field_notes_species",
            scientificName: "Cyprinella lutrensis",
            commonName: "Red Shiner"
        )
        let notes = "Schooling in a shallow creek after rain."

        context.insert(record)
        try context.save()
        FieldNotesStore.setFieldNotes(nil, for: record.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: record.id) }

        viewModel.inferenceEngine = InsightSheetTestSupport.biologicalEngine(
            scanId: record.id
        )
        viewModel.bindPresentedRecord(record, modelContext: context)
        viewModel.state.dismissedFieldNotesCardScanId = record.id

        viewModel.syncComposerFieldNotes(notes, modelContext: context)

        #expect(viewModel.fieldNotesText == notes)
        #expect(record.fieldNotes == notes)
        #expect(FieldNotesStore.fieldNotes(for: record.id) == notes)
        #expect(viewModel.state.dismissedFieldNotesCardScanId == nil)
    }

    @Test func testQueuedScanFieldNotesPersistToOfflineRecord() async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let queuedScan = OfflineQueuedScan(id: "queued_field_notes_scan")

        context.insert(queuedScan)
        try context.save()
        FieldNotesStore.setFieldNotes(nil, for: queuedScan.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: queuedScan.id) }

        let viewModel = InsightSheetViewModel(
            queuedContext: QueuedScanContext(from: queuedScan)
        )
        viewModel.syncFieldNotesFromCurrentScan(modelContext: context)
        #expect(viewModel.currentFieldNotesScanId == queuedScan.id)
        #expect(viewModel.shouldShowFieldNotesCard)

        viewModel.updateFieldNotes(
            "Queued field note",
            modelContext: context
        )

        #expect(viewModel.fieldNotesText == "Queued field note")
        #expect(queuedScan.fieldNotes == "Queued field note")
        #expect(
            FieldNotesStore.fieldNotes(for: queuedScan.id) == "Queued field note"
        )
    }

    @Test func testFieldNotesRejectChangedPresentationIdentity() async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let queuedScan = OfflineQueuedScan(id: "current_field_notes_scan")
        context.insert(queuedScan)
        try context.save()
        FieldNotesStore.setFieldNotes(nil, for: queuedScan.id)
        defer { FieldNotesStore.setFieldNotes(nil, for: queuedScan.id) }

        let viewModel = InsightSheetViewModel(
            queuedContext: QueuedScanContext(from: queuedScan)
        )
        viewModel.syncFieldNotesFromCurrentScan(modelContext: context)

        viewModel.presentFieldNotes(expectedScanId: "previous_field_notes_scan")
        viewModel.updateFieldNotes(
            "Stale note",
            expectedScanId: "previous_field_notes_scan",
            modelContext: context
        )

        #expect(!viewModel.state.isFieldNotesSheetPresented)
        #expect(viewModel.state.fieldNotesPresentationScanId == nil)
        #expect(viewModel.state.fieldNotesPresentationGeneration == nil)
        #expect(viewModel.fieldNotesText.isEmpty)
        #expect(queuedScan.fieldNotes == nil)

        viewModel.presentFieldNotes(expectedScanId: queuedScan.id)

        #expect(viewModel.state.isFieldNotesSheetPresented)
        #expect(
            viewModel.state.fieldNotesPresentationScanId == queuedScan.id
        )
        #expect(
            viewModel.state.fieldNotesPresentationGeneration == viewModel.scanBoundActionGeneration
        )
    }

    @Test func injectedDependenciesOwnPersistenceAndFeedback() async throws {
        let context = try InsightSheetTestSupport.createIsolatedContext()
        let queuedScan = OfflineQueuedScan(id: "injected_field_notes_scan")
        context.insert(queuedScan)
        try context.save()

        var readIDs: [String] = []
        var writes: [(String?, String)] = []
        var promotionIDs: [String] = []
        var feedbackCount = 0
        let dependencies = InsightFieldNotesDependencies(
            fieldNotes: { scanID, suppliedContext in
                #expect(suppliedContext === context)
                readIDs.append(scanID)
                return "Injected note"
            },
            setFieldNotes: { text, scanID, suppliedContext in
                #expect(suppliedContext === context)
                writes.append((text, scanID))
                return true
            },
            promoteExternalFieldNotesIfLocalMissing: { text, scanID, suppliedContext in
                #expect(suppliedContext === context)
                promotionIDs.append(scanID)
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            },
            cardDismissFeedback: { feedbackCount += 1 }
        )
        let viewModel = InsightSheetViewModel(
            queuedContext: QueuedScanContext(from: queuedScan),
            fieldNotesDependencies: dependencies
        )

        viewModel.syncFieldNotesFromCurrentScan(modelContext: context)
        viewModel.updateFieldNotes("Updated note", modelContext: context)
        viewModel.dismissFieldNotesCard(expectedScanId: queuedScan.id)
        viewModel.state.fieldNotesText = ""
        viewModel.promotePublishedExploreFieldNotesIfLocalMissing(
            "  Published note  ",
            modelContext: context
        )

        #expect(readIDs == [queuedScan.id])
        #expect(writes.count == 1)
        #expect(writes[0].0 == "Updated note")
        #expect(writes[0].1 == queuedScan.id)
        #expect(promotionIDs == [queuedScan.id])
        #expect(feedbackCount == 1)
        #expect(viewModel.fieldNotesText == "Published note")
    }
}

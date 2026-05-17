import Testing
import SwiftData
import Foundation
@testable import Merian

@MainActor
struct InsightSheetViewModelTests {

    private func createIsolatedContext() throws -> ModelContext {
        let schema = Schema(CurrentSchema.models)
        let tempURL = URL.cachesDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let modelConfiguration = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let context = ModelContext(container)
        ScanRepository.shared.configure(with: context)
        return context
    }

    @Test func testEvaluateScrollOffset() {
        let viewModel = InsightSheetViewModel()
        #expect(viewModel.state.isCommonNameScrolledPast == false)
        
        viewModel.evaluateScrollOffset(minY: 40.0)
        #expect(viewModel.state.isCommonNameScrolledPast == true)
        
        viewModel.evaluateScrollOffset(minY: 60.0)
        #expect(viewModel.state.isCommonNameScrolledPast == false)
    }

    @Test func testToggleScanInCollection() async throws {
        let ctx = try createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        
        let record = LocalScanRecord(speciesId: "scan_toggle", scientificName: "Test", commonName: "Test")
        ctx.insert(record)
        
        let collection = ScanCollection(name: "Favorites")
        ctx.insert(collection)
        try ctx.save()
        
        viewModel.activeLocalRecord = record
        
        viewModel.toggleScanInCollection(collection, modelContext: ctx)
        #expect(record.collections?.contains(where: { $0.id == collection.id }) == true)
        #expect(viewModel.state.toastMessage?.contains("Added to Favorites") == true)
        
        viewModel.toggleScanInCollection(collection, modelContext: ctx)
        #expect(record.collections?.contains(where: { $0.id == collection.id }) == false)
        #expect(viewModel.state.toastMessage?.contains("Removed from Favorites") == true)
    }

    @Test func testComputedHeaderProperties() async throws {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        
        let insightData = InsightData(aiReasoning: "A test object.\nWith multiple lines.", hazardType: "venomous")
        engine.speciesData = SpeciesData(
            scanId: "comp_1",
            commonName: "Common Name",
            scientificName: "Sci Name",
            insightData: insightData,
            confidenceScore: 0.99,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )
        viewModel.inferenceEngine = engine
        
        #expect(viewModel.resolvedHeaderTitle == "Common Name")
        #expect(viewModel.headerSubtitle == "Sci Name")
        #expect(viewModel.hazardType == "venomous")
        #expect(viewModel.isHazardous == true)
        #expect(viewModel.headerParagraphs.count == 2)
        #expect(viewModel.headerParagraphs.first == "A test object.")
    }

    @Test func testFetchLocalRecord() async throws {
        // Validation that the viewmodel gracefully pulls state and assigns local memory
        let ctx = try createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        viewModel.inferenceEngine = InferenceEngine()
        
        // Assert initial unassigned state
        #expect(viewModel.activeLocalRecord == nil)
        
        let record = LocalScanRecord(speciesId: "fetch_test_1", scientificName: "Equus caballus", commonName: "Horse")
        // Overriding default initializer value manually to test the read receipt flip logic isolated.
        record.hasBeenViewed = false
        
        let recordId = record.id
        ctx.insert(record)
        try ctx.save()
        
        viewModel.fetchLocalRecord(for: recordId, modelContext: ctx)
        
        #expect(viewModel.activeLocalRecord?.id == recordId)
        #expect(viewModel.activeLocalRecord?.hasBeenViewed == true, "fetchLocalRecord must actively flag the read-receipt to false the unread states across the app ecosystem")
    }

    @Test func testFetchLocalRecordHydratesSharedExplorePostIdFromCache() async throws {
        let ctx = try createIsolatedContext()
        let viewModel = InsightSheetViewModel()
        let record = LocalScanRecord(speciesId: "shared_fetch_test", scientificName: "Rosa", commonName: "Rose")
        let sharedPostId = "post_\(UUID().uuidString)"

        ctx.insert(record)
        try ctx.save()
        ExploreShareStateStore.setSharedPostId(sharedPostId, for: record.id)
        defer { ExploreShareStateStore.setSharedPostId(nil, for: record.id) }

        viewModel.fetchLocalRecord(for: record.id, modelContext: ctx)

        #expect(viewModel.activeLocalRecord?.id == record.id)
        #expect(viewModel.state.sharedExplorePostId == sharedPostId)
    }

    @Test func testRefreshSharedExploreStateClearsMissingCache() async throws {
        let ctx = try createIsolatedContext()
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

    @Test func testPublishedExploreFieldNotesPromoteWhenLocalRecordIsEmpty() async throws {
        let ctx = try createIsolatedContext()
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
        let ctx = try createIsolatedContext()
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

        viewModel.bindPresentedRecord(record, modelContext: ctx)
        viewModel.promotePublishedExploreFieldNotesIfLocalMissing(
            "Published Explore note",
            modelContext: ctx
        )

        #expect(viewModel.fieldNotesText == "Private local note")
        #expect(record.fieldNotes == "Private local note")
        #expect(FieldNotesStore.fieldNotes(for: record.id) == "Private local note")
    }

    @Test func testFieldNotesRepositoryPromotesLegacyStoreIntoLocalRecord() async throws {
        let ctx = try createIsolatedContext()
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
            modelContext: ctx,
            activeRecord: record
        )

        #expect(resolvedNotes == legacyNotes)
        #expect(record.fieldNotes == legacyNotes)
        #expect(FieldNotesStore.fieldNotes(for: record.id) == legacyNotes)
    }

    @Test func testFieldNotesRepositoryClearsLocalRecordAndLegacyBridgeTogether() async throws {
        let ctx = try createIsolatedContext()
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
            modelContext: ctx,
            activeRecord: record
        )

        #expect(record.fieldNotes == nil)
        #expect(FieldNotesStore.fieldNotes(for: record.id) == nil)
    }

    @Test func testFieldNotesRepositoryMirrorsUnchangedLocalRecordIntoLegacyBridge() async throws {
        let ctx = try createIsolatedContext()
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
            modelContext: ctx,
            activeRecord: record
        )

        #expect(changed == false)
        #expect(record.fieldNotes == "Already saved locally")
        #expect(FieldNotesStore.fieldNotes(for: record.id) == "Already saved locally")
    }

    @Test func testFieldNotesRepositoryPersistsBridgeOnlyWhenNoSwiftDataRecordExists() async throws {
        let ctx = try createIsolatedContext()
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
        let ctx = try createIsolatedContext()
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

    @Test func testTotalImagesWithReferenceImageLoading() async throws {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        viewModel.inferenceEngine = engine
        
        // Base state: 1 live captured image, no reference image yet
        engine.activeMedia = ActiveScanMedia(items: [.liveImage(Data())], referenceState: .empty)
        engine.speciesData = SpeciesData(
            scanId: "load_test",
            commonName: "Test",
            scientificName: "Test",
            insightData: InsightData(aiReasoning: "", hazardType: "none"),
            confidenceScore: 0.9,
            referenceImageUrl: nil,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown"
        )
        
        #expect(viewModel.totalImages == 1, "Should count 1 live image only when not loading")
        
        // Toggle hydration flag
        engine.activeMedia.referenceState = .loading
        #expect(viewModel.totalImages == 2, "Should append +1 for the loading skeleton")
        
        // Simulate network resolving and injecting a URL while task clears
        engine.activeMedia.referenceState = .loaded(["https://example.com/gbif.jpg"])
        #expect(viewModel.totalImages == 2, "Should count the real URL and drop skeleton")
        
        engine.activeMedia.referenceState = .loaded(["https://example.com/gbif.jpg"])
        #expect(viewModel.totalImages == 2, "Final state should remain 2 after task cleanup")
    }

    @Test func testPersistentScanIdUsesActiveScanIdDuringLiveAnalysis() {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        engine.activeScanId = "scan_in_flight_123"
        viewModel.inferenceEngine = engine

        #expect(viewModel.persistentScanId == "scan_in_flight_123", "Carousel identity should stay stable before speciesData arrives")

        engine.speciesData = SpeciesData(
            scanId: "scan_in_flight_123",
            commonName: "Test subject",
            scientificName: "Testus subjectus",
            insightData: InsightData(aiReasoning: "", hazardType: "none"),
            confidenceScore: 0.8,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )
        engine.activeScanId = nil

        #expect(viewModel.persistentScanId == "scan_in_flight_123", "Carousel identity should remain the same after inference completes")
    }

    @Test func testHasLiveRetainsStatePostInference() async throws {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        viewModel.inferenceEngine = engine
        
        // 1. Simulate initial live capture state
        engine.activeMedia = ActiveScanMedia(items: [.liveImage(Data())])
        #expect(viewModel.activeMedia.liveImageData != nil, "hasLive should be true when activeImageData is present")
        
        // 2. Simulate background task populating validHistoricImagePaths (the previous bug trigger)
        engine.activeMedia.items.append(.image("sandbox/UUID.webp"))
        
        // 3. Assert the Carousel structural teardown is prevented
        #expect(viewModel.activeMedia.liveImageData != nil, "hasLive MUST remain true even when valid paths are populated to prevent LiveCapturePageView from tearing down and causing image disappearance")
        
        // 4. Verify queued scans still correctly override to false
        let queuedScan = OfflineQueuedScan(id: "offline", capturedMediaJSON: try! String(data: JSONEncoder().encode([SerializedMediaItem.image("test.webp")]), encoding: .utf8))
        viewModel.queuedContext = QueuedScanContext(from: queuedScan)
        #expect(viewModel.activeMedia.liveImageData == nil, "hasLive should evaluate to false when viewing a queued scan")
    }

    @Test func testAudioCarouselPagesPersistAfterInferenceCompletes() {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        let scanId = "audio_handoff_scan"
        let audioPath = "documents/audio_handoff.wav"
        let imagePath = "documents/audio_handoff.webp"

        engine.activeScanId = scanId
        engine.activeMedia = ActiveScanMedia(items: [.audio(audioPath), .image(imagePath)])
        viewModel.inferenceEngine = engine

        let analyzingPageIDs = CarouselPageBuilder.buildPages(
            for: viewModel.activeMedia,
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        ).map(\.id)

        #expect(viewModel.persistentScanId == scanId)
        #expect(analyzingPageIDs == ["audio-\(audioPath)", "image-\(imagePath)"])

        engine.speciesData = SpeciesData(
            scanId: scanId,
            commonName: "Northern Cardinal",
            scientificName: "Cardinalis cardinalis",
            insightData: InsightData(aiReasoning: "", hazardType: "none"),
            confidenceScore: 0.97,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )
        engine.activeScanId = nil

        let completedPageIDs = CarouselPageBuilder.buildPages(
            for: viewModel.activeMedia,
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        ).map(\.id)

        #expect(viewModel.persistentScanId == scanId, "The carousel key should remain stable across the analysis-to-result handoff")
        #expect(completedPageIDs == analyzingPageIDs, "Audio and mixed-media page identity must remain unchanged after inference finishes")
    }

    @Test func testReferenceCarouselPagesCarryAttributionLabels() {
        let media = ActiveScanMedia(referenceState: .loaded([
            "https://media.merian.app/reference.webp",
            "https://upload.wikimedia.org/species.jpg",
            "https://static.inaturalist.org/photos/1/original.jpg"
        ]))

        let pages = CarouselPageBuilder.buildPages(
            for: media,
            referenceWikipediaUrl: "https://en.wikipedia.org/wiki/Test_species",
            onImageFailure: { _ in },
            onDescriptionTap: nil
        )

        #expect(pages.map(\.referenceAttributionLabel) == ["Merian", "Wikipedia", "GBIF"])
    }

    @Test func testNativeCarouselResetsDataSourceWhenReferencesAppendAfterAudioPage() {
        let audioPath = "documents/audio_only.wav"
        let audioOnlyPages = CarouselPageBuilder.buildPages(
            for: ActiveScanMedia(items: [.audio(audioPath)]),
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        )

        let withReferencePages = CarouselPageBuilder.buildPages(
            for: ActiveScanMedia(
                items: [.audio(audioPath)],
                referenceState: .loaded(["https://example.com/field-sparrow.jpg"])
            ),
            referenceWikipediaUrl: nil,
            onImageFailure: { _ in },
            onDescriptionTap: nil
        )

        #expect(audioOnlyPages.map(\.id) == ["audio-\(audioPath)"])
        #expect(withReferencePages.map(\.id) == ["audio-\(audioPath)", "reference-https://example.com/field-sparrow.jpg"])
        #expect(NativePageCarousel.Coordinator.requiresDataSourceReset(previousPages: audioOnlyPages, nextPages: withReferencePages))
    }
}

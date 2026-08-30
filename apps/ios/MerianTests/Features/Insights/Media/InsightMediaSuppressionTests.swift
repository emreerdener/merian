import Combine
import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
struct InsightMediaSuppressionTests {
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

    @Test func testHumanSubjectSuppressesReferenceImagesButKeepsUserMedia() {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        viewModel.inferenceEngine = engine

        engine.activeMedia = ActiveScanMedia(
            items: [.image("documents/human-capture.webp"), .audio("documents/context.m4a")],
            referenceState: .loaded([
                "https://upload.wikimedia.org/human.jpg",
                "https://static.inaturalist.org/photos/human.jpg"
            ])
        )
        engine.speciesData = SpeciesData(
            scanId: "human_reference_suppression",
            commonName: "Human",
            scientificName: "Homo sapiens",
            insightData: InsightData(aiReasoning: "", hazardType: "none"),
            confidenceScore: 0.96,
            referenceImageUrl: "https://upload.wikimedia.org/human.jpg,https://static.inaturalist.org/photos/human.jpg",
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )

        #expect(viewModel.refUrls.isEmpty)
        #expect(viewModel.activeMedia.items == [.image("documents/human-capture.webp"), .audio("documents/context.m4a")])
        #expect(viewModel.activeMedia.referenceState == .empty)
        #expect(viewModel.totalImages == 2)
    }

    @Test func testDomesticCatAndDogSubjectsSuppressReferenceImagesButKeepUserMedia() {
        let subjects = [
            (commonName: "Domestic cat", scientificName: "Felis catus"),
            (commonName: "Domestic dog", scientificName: "Canis lupus familiaris")
        ]

        for subject in subjects {
            let viewModel = InsightSheetViewModel()
            let engine = InferenceEngine()
            viewModel.inferenceEngine = engine
            engine.activeMedia = ActiveScanMedia(
                items: [.image("documents/user-capture.webp")],
                referenceState: .loaded(["https://example.com/unsuitable-reference.jpg"])
            )
            engine.speciesData = SpeciesData(
                scanId: "domestic_reference_suppression",
                commonName: subject.commonName,
                scientificName: subject.scientificName,
                insightData: InsightData(aiReasoning: "", hazardType: "none"),
                confidenceScore: 0.96,
                referenceImageUrl: "https://example.com/unsuitable-reference.jpg"
            )

            #expect(viewModel.refUrls.isEmpty)
            #expect(viewModel.activeMedia.items == [.image("documents/user-capture.webp")])
            #expect(viewModel.activeMedia.referenceState == .empty)
            #expect(viewModel.totalImages == 1)
        }
    }

    @Test func testWildCatKeepsReferenceImages() {
        let viewModel = InsightSheetViewModel()
        let engine = InferenceEngine()
        viewModel.inferenceEngine = engine
        engine.activeMedia = ActiveScanMedia(
            items: [.image("documents/user-capture.webp")],
            referenceState: .loaded(["https://example.com/wildcat-reference.jpg"])
        )
        engine.speciesData = SpeciesData(
            scanId: "wildcat_reference_gallery",
            commonName: "European wildcat",
            scientificName: "Felis silvestris",
            insightData: InsightData(aiReasoning: "", hazardType: "none"),
            confidenceScore: 0.96,
            referenceImageUrl: "https://example.com/wildcat-reference.jpg",
            taxonomy: TaxonomyData(
                kingdom: "Animalia",
                phylum: "Chordata",
                className: "Mammalia",
                order: "Carnivora",
                family: "Felidae",
                genus: "Felis"
            )
        )

        #expect(viewModel.refUrls == ["https://example.com/wildcat-reference.jpg"])
        #expect(viewModel.activeMedia.referenceState == .loaded(["https://example.com/wildcat-reference.jpg"]))
        #expect(viewModel.totalImages == 2)
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

    @Test func liveQueueHandoffKeepsInMemoryCarouselMediaForSameScan() {
        let scanId = "live_queue_media_handoff"
        let engine = InferenceEngine()
        let liveImage = Data([0x01, 0x02, 0x03])
        engine.simulateProgressiveAnalyzing(automaticallyAdvances: false)
        engine.activeMedia = ActiveScanMedia(items: [.liveImage(liveImage)])
        #expect(engine.debugTransitionProgressiveAnalyzingToQueue(
            scanId: scanId
        ))

        let queuedContext = QueuedScanContext(
            id: scanId,
            capturedMediaItems: [.image(.documents("persisted.webp"))],
            queueState: .inferencing,
            timestamp: Date()
        )
        let viewModel = InsightSheetViewModel(
            queuedContext: queuedContext,
            inferenceEngine: engine
        )

        #expect(viewModel.activeMedia.liveImageData == liveImage)
        #expect(viewModel.resolvedMedia(
            for: queuedContext
        ).liveImageData == liveImage)
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

        #expect(pages.map(\.referenceAttributionLabel) == ["Naturebook", "Wikipedia", "GBIF"])
        #expect(pages.map(\.imageOrigin) == [.reference, .reference, .reference])
    }

    @Test func testOriginalPhotoUnavailablePresentationExplainsRetainedIdentification() {
        let presentation = UnavailableVisualContext.originalPhoto.presentation(isOffline: false)

        #expect(presentation.systemImage == "photo.badge.exclamationmark")
        #expect(presentation.title == "Original photo unavailable")
        #expect(presentation.message == "We couldn’t load your photo, but your identification is still available.")
        #expect(
            presentation.accessibilityLabel
                == "Original photo unavailable. We couldn’t load your photo, but your identification is still available."
        )
    }

    @Test func testRemoteOriginalPhotoUnavailablePresentationExplainsOfflineRetry() {
        let presentation = UnavailableVisualContext.originalPhoto.presentation(isOffline: true)

        #expect(presentation.systemImage == "wifi.slash")
        #expect(presentation.title == "Original photo unavailable")
        #expect(presentation.message == "Reconnect to load your photo. Your identification is still available.")
        #expect(
            presentation.accessibilityLabel
                == "Original photo unavailable while offline. Reconnect to load your photo. Your identification is still available."
        )
    }

}

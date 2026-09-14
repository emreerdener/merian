import Foundation
import Observation
import os
import Testing

@testable import Merian

@MainActor
@Suite("Inference Presentation State")
struct InferencePresentationStateTests {
    @Test func prepareForNewScanClearsPresentationAndEveryTelemetryValue() {
        let state = InferencePresentationState()
        state.replaceActiveMedia(ActiveScanMedia(items: [.image("old.webp")]))
        state.replaceSpeciesData(makeSpeciesData(scanId: "old-scan"))
        state.setQueuedPresentationScanId("old-scan")
        state.setEnrichmentLoading(true)
        state.setLookalikesLoading(true)
        state.applyVisualTelemetry(makeTelemetry(distance: 0.42))

        state.prepareForNewScan(defaultScanningPhrase: "Analyzing subject")

        #expect(state.queuedPresentationScanId == nil)
        #expect(state.isProcessing)
        #expect(state.scanningPhaseText == "Analyzing subject")
        #expect(state.activeMedia.isEmpty)
        #expect(state.speciesData == nil)
        #expect(!state.isEnrichmentLoading)
        #expect(!state.isLookalikesLoading)
        #expect(state.activeLatitude == nil)
        #expect(state.activeLongitude == nil)
        #expect(state.activeElevation == nil)
        #expect(state.activeLocationName == nil)
        #expect(state.activeWeatherCondition == nil)
        #expect(state.activeTemperatureF == nil)
        #expect(state.activeFlashFired == nil)
        #expect(state.activeDistanceInMeters == nil)
    }

    @Test func nonVisualTelemetryCannotInheritVisualDistance() {
        let state = InferencePresentationState()
        state.applyVisualTelemetry(makeTelemetry(distance: 0.42))
        #expect(state.activeDistanceInMeters == 0.42)

        state.applyNonVisualTelemetry(makeTelemetry(distance: 9.9))

        #expect(state.activeLatitude == 41.88)
        #expect(state.activeLocationName == "Chicago")
        #expect(state.activeDistanceInMeters == nil)
    }

    @Test func successfulResultPublishesPersistedMediaAndReferenceState() throws {
        let state = InferencePresentationState()
        state.setQueuedPresentationScanId("scan-a")
        state.setProcessing(true)
        state.replaceActiveMedia(ActiveScanMedia(
            items: [.liveImage(Data([0x01]))],
            referenceState: .loading
        ))
        let result = makeSpeciesData(
            scanId: "scan-a",
            referenceImageURL: "https://example.com/reference.webp"
        )

        state.publishSuccessfulResult(
            result,
            persistedMediaItems: [.image("capture.webp")]
        )

        #expect(state.queuedPresentationScanId == nil)
        #expect(state.activeMedia.items == [.image("capture.webp")])
        #expect(state.activeMedia.referenceState == .loaded([
            "https://example.com/reference.webp"
        ]))
        #expect(state.speciesData?.scanId == "scan-a")
        #expect(!state.isProcessing)
    }

    @Test func queueHandoffPreservesMediaWhileEndingResultPresentation() {
        let state = InferencePresentationState()
        let media = ActiveScanMedia(items: [.liveImage(Data([0x01]))])
        state.replaceActiveMedia(media)
        state.replaceSpeciesData(makeSpeciesData(scanId: "scan-a"))
        state.setProcessing(true)

        state.beginQueueHandoff(scanningPhrases: ["Reviewing wing pattern"])
        state.setQueuedPresentationScanId("scan-a")
        state.finishQueueHandoff()

        #expect(state.scanningPhaseText == "Reviewing wing pattern")
        #expect(state.queuedPresentationScanId == "scan-a")
        #expect(state.activeMedia == media)
        #expect(state.speciesData == nil)
        #expect(!state.isProcessing)
    }

    @Test func cancellationReturnsPresentationToCleanIdleState() {
        let state = InferencePresentationState()
        state.setProcessing(true)
        state.setScanningPhaseText("Listening")
        state.setQueuedPresentationScanId("scan-a")
        state.replaceActiveMedia(ActiveScanMedia(items: [.audio("audio.wav")]))
        state.replaceSpeciesData(makeSpeciesData(scanId: "scan-a"))
        state.setEnrichmentLoading(true)
        state.setLookalikesLoading(true)
        state.applyVisualTelemetry(makeTelemetry(distance: 0.42))

        state.beginCancellation()
        #expect(!state.isProcessing)
        state.finishCancellation(defaultScanningPhrase: "Analyzing subject")

        #expect(state.scanningPhaseText == "Analyzing subject")
        #expect(state.queuedPresentationScanId == nil)
        #expect(state.activeMedia.isEmpty)
        #expect(state.speciesData == nil)
        #expect(!state.isEnrichmentLoading)
        #expect(!state.isLookalikesLoading)
        #expect(state.activeDistanceInMeters == nil)
    }

    @Test func historicalProjectionReplacesReleasedLiveMedia() {
        let state = InferencePresentationState()
        state.setQueuedPresentationScanId("queued-scan")
        state.setEnrichmentLoading(true)
        state.setLookalikesLoading(true)
        state.replaceActiveMedia(ActiveScanMedia(
            items: [.liveImage(Data([0x01]))]
        ))

        state.beginHistoricalLoad()
        #expect(state.isProcessing)
        #expect(state.queuedPresentationScanId == nil)
        #expect(!state.isEnrichmentLoading)
        #expect(!state.isLookalikesLoading)
        state.releaseLiveMedia()
        #expect(state.activeMedia.isEmpty)

        let historicalMedia = ActiveScanMedia(items: [.image("history.webp")])
        state.publishHistoricalProjection(
            media: historicalMedia,
            speciesData: makeSpeciesData(scanId: "history-scan")
        )

        #expect(state.activeMedia == historicalMedia)
        #expect(state.speciesData?.scanId == "history-scan")
        #expect(!state.isProcessing)
    }

    @Test func engineReadThroughRetainsSwiftObservationInvalidation() {
        let engine = InferenceEngine()
        let processingChanges = OSAllocatedUnfairLock(initialState: 0)

        withObservationTracking {
            _ = engine.isProcessing
        } onChange: {
            processingChanges.withLock { $0 += 1 }
        }

        engine.isProcessing = true

        #expect(processingChanges.withLock { $0 } == 1)
        #expect(engine.isProcessing)

        let mediaChanges = OSAllocatedUnfairLock(initialState: 0)
        withObservationTracking {
            _ = engine.activeMedia.referenceState
        } onChange: {
            mediaChanges.withLock { $0 += 1 }
        }

        engine.activeMedia.referenceState = .loading

        #expect(mediaChanges.withLock { $0 } == 1)
        #expect(engine.activeMedia.referenceState == .loading)
    }

    private func makeTelemetry(distance: Float?) -> CaptureTelemetry {
        CaptureTelemetry(
            subjectDistanceInMeters: distance,
            gpsLatitude: 41.88,
            gpsLongitude: -87.63,
            gpsElevation: 181,
            locationName: "Chicago",
            weatherCondition: "Clear",
            weatherTemperatureF: 72,
            timeOfDay: "afternoon",
            timestamp: "2026-09-13T12:00:00Z",
            zoomFactor: nil,
            estimatedSizeCm: nil
        )
    }

    private func makeSpeciesData(
        scanId: String,
        referenceImageURL: String? = nil
    ) -> SpeciesData {
        SpeciesData(
            scanId: scanId,
            commonName: "Monarch",
            scientificName: "Danaus plexippus",
            insightData: InsightData(
                aiReasoning: "Orange wings",
                hazardType: "none"
            ),
            confidenceScore: 0.94,
            referenceImageUrl: referenceImageURL,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "terrestrial",
            aiScientificName: "Danaus plexippus"
        )
    }
}

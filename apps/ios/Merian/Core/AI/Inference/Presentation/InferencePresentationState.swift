import Foundation
import Observation

/// Owns the observable values published by `InferenceEngine`.
///
/// Lifecycle identity, task ownership, networking, persistence, logging, and
/// durable queue effects remain outside this state owner. The engine keeps its
/// source-compatible property surface as read-through accessors so existing
/// SwiftUI observation follows these individually tracked values.
@MainActor
@Observable
final class InferencePresentationState {
    private(set) var queuedPresentationScanId: String?
    private(set) var isProcessing = false
    private(set) var scanningPhaseText = "Analyzing subject"
    private(set) var activeMedia = ActiveScanMedia()
    private(set) var speciesData: SpeciesData?

    private(set) var activeLatitude: Double?
    private(set) var activeLongitude: Double?
    private(set) var activeElevation: Double?
    private(set) var activeLocationName: String?
    private(set) var activeWeatherCondition: String?
    private(set) var activeTemperatureF: Double?
    private(set) var activeFlashFired: Bool?
    private(set) var activeDistanceInMeters: Float?

    private(set) var isEnrichmentLoading = false
    private(set) var isLookalikesLoading = false

    func replaceActiveMedia(_ media: ActiveScanMedia) {
        activeMedia = media
    }

    func replaceSpeciesData(_ data: SpeciesData?) {
        speciesData = data
    }

    func setProcessing(_ processing: Bool) {
        isProcessing = processing
    }

    func setScanningPhaseText(_ text: String) {
        scanningPhaseText = text
    }

    func setEnrichmentLoading(_ loading: Bool) {
        isEnrichmentLoading = loading
    }

    func setLookalikesLoading(_ loading: Bool) {
        isLookalikesLoading = loading
    }

    func replaceReferenceState(_ state: ReferenceState) {
        activeMedia.referenceState = state
    }

    func clearForAuthTransition(defaultScanningPhrase: String) {
        queuedPresentationScanId = nil
        scanningPhaseText = defaultScanningPhrase
        activeMedia = ActiveScanMedia()
    }

    func prepareForNewScan(defaultScanningPhrase: String) {
        queuedPresentationScanId = nil
        isProcessing = true
        scanningPhaseText = defaultScanningPhrase
        clearLoadingState()
        speciesData = nil
        activeMedia = ActiveScanMedia()
        resetTelemetry()
    }

    func clearLoadingState() {
        isEnrichmentLoading = false
        isLookalikesLoading = false
    }

    func stageVisualMedia(_ media: ActiveScanMedia) {
        activeMedia = media
        speciesData = nil
    }

    func applyVisualTelemetry(_ telemetry: CaptureTelemetry) {
        applyEnvironmentTelemetry(telemetry)
        activeDistanceInMeters = telemetry.subjectDistanceInMeters
    }

    func applyNonVisualTelemetry(_ telemetry: CaptureTelemetry) {
        applyEnvironmentTelemetry(telemetry)
        activeDistanceInMeters = nil
    }

    func publishSuccessfulResult(
        _ data: SpeciesData,
        persistedMediaItems: [MediaItem]?
    ) {
        queuedPresentationScanId = nil
        if let persistedMediaItems {
            activeMedia.items = persistedMediaItems
        }
        speciesData = data
        applyReferenceStateIfAvailable(from: data)
        isProcessing = false
    }

    func beginQueueHandoff(scanningPhrases: [String]) {
        if let firstPhrase = scanningPhrases.first {
            scanningPhaseText = firstPhrase
        }
    }

    func setQueuedPresentationScanId(_ scanId: String?) {
        queuedPresentationScanId = scanId
    }

    func finishQueueHandoff() {
        speciesData = nil
        isProcessing = false
    }

    func dismissAnalyzingPresentation(defaultScanningPhrase: String) {
        queuedPresentationScanId = nil
        scanningPhaseText = defaultScanningPhrase
        activeMedia = ActiveScanMedia()
    }

    func beginCancellation() {
        isProcessing = false
    }

    func finishCancellation(defaultScanningPhrase: String) {
        scanningPhaseText = defaultScanningPhrase
        clearLoadingState()
        speciesData = nil
        queuedPresentationScanId = nil
        activeMedia = ActiveScanMedia()
        resetTelemetry()
    }

    func beginHistoricalLoad() {
        queuedPresentationScanId = nil
        isProcessing = true
        // The displaced hydration generation cannot clear these flags later.
        clearLoadingState()
    }

    func releaseLiveMedia() {
        activeMedia = ActiveScanMedia()
    }

    func publishHistoricalProjection(
        media: ActiveScanMedia,
        speciesData: SpeciesData
    ) {
        activeMedia = media
        self.speciesData = speciesData
        isProcessing = false
    }

    func markAlternativesExhausted() {
        speciesData?.alternativesExhausted = true
    }

    private func applyEnvironmentTelemetry(_ telemetry: CaptureTelemetry) {
        activeLatitude = telemetry.gpsLatitude
        activeLongitude = telemetry.gpsLongitude
        activeElevation = telemetry.gpsElevation
        activeLocationName = telemetry.locationName
        activeWeatherCondition = telemetry.weatherCondition
        activeTemperatureF = telemetry.weatherTemperatureF
    }

    private func applyReferenceStateIfAvailable(from data: SpeciesData) {
        guard !data.shouldSuppressReferenceImages else {
            activeMedia.referenceState = .empty
            return
        }
        let references = ExternalReferenceImagePolicy.allowedURLStrings(
            from: data.referenceImageUrl
        )
        if !references.isEmpty {
            activeMedia.referenceState = .loaded(references)
        }
    }

    private func resetTelemetry() {
        activeLatitude = nil
        activeLongitude = nil
        activeElevation = nil
        activeLocationName = nil
        activeWeatherCondition = nil
        activeTemperatureF = nil
        activeFlashFired = nil
        activeDistanceInMeters = nil
    }
}

import Combine
import CoreImage
import Foundation
import ImageIO
import os
import SwiftData
import SwiftUI

// MARK: - Identification Review Request

private struct ReviewSyncRPCParameters: Encodable, Sendable {
    let scanId: String
    let override: String?
    let confirmed: Bool
    let confirmedSpeciesId: String?
    let userReviewState: String

    enum CodingKeys: String, CodingKey {
        case scanId = "p_scan_id"
        case override = "p_override"
        case confirmed = "p_confirmed"
        case confirmedSpeciesId = "p_confirmed_species_id"
        case userReviewState = "p_user_review_state"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scanId, forKey: .scanId)
        if let override {
            try container.encode(override, forKey: .override)
        } else {
            try container.encodeNil(forKey: .override)
        }
        try container.encode(confirmed, forKey: .confirmed)
        if let confirmedSpeciesId {
            try container.encode(confirmedSpeciesId, forKey: .confirmedSpeciesId)
        } else {
            try container.encodeNil(forKey: .confirmedSpeciesId)
        }
        try container.encode(userReviewState, forKey: .userReviewState)
    }
}

// MARK: - Inference Engine

/// Drives the live AI taxonomy pipeline and manages all active scan state.
@MainActor
@Observable final class InferenceEngine {

    enum ScanPresentationModality: Sendable {
        case visual
        case nonVisual
    }

    enum QueuedPresentationSource: Sendable {
        case prepared(attemptGeneration: UUID)
        case active(attemptGeneration: UUID)
    }

    private struct AnalysisPresentationOwner: Sendable {
        let scanId: String?
        let attemptGeneration: UUID
        let modality: ScanPresentationModality

        func matches(scanId: String, attemptGeneration: UUID) -> Bool {
            self.attemptGeneration == attemptGeneration &&
                self.scanId?.caseInsensitiveCompare(scanId) == .orderedSame
        }
    }

    // MARK: - Pipeline State
    @ObservationIgnored var inferenceTask: Task<Void, Error>?
    /// The client scan ID passed to `analyze()` — matches the `OfflineQueuedScan.id` for the
    /// same capture. Used by the background offline path to detect when it completes the same
    /// scan and should hydrate the engine instead of leaving `isProcessing = true` forever.
    @ObservationIgnored var activeScanId: String?
    /// Unique owner of the current foreground pipeline. This is distinct from
    /// `activeScanId` because the same queued scan can be retried or replaced.
    @ObservationIgnored var activeLiveInferenceAttemptGeneration: UUID?
    /// Durable generation written on the queued scan-ingestion job. `nil` only
    /// for direct queue-less API uses.
    @ObservationIgnored var activeForegroundInferenceGeneration: UUID?
    /// Exact queued scan whose live presentation ended with an ambiguous
    /// response. Retained after the active task's defer clears `activeScanId`
    /// so a later URLSession or status-recovery winner can replace the local
    /// error placeholder without overwriting a newer scan presentation.
    @ObservationIgnored var recoverablePresentationScanId: String?
    /// Exact durable scan whose live request relinquished foreground ownership
    /// and should now use the queue-aware Insight presentation. Unlike
    /// `recoverablePresentationScanId`, this value is observable because the
    /// visible sheet uses it to bind the matching `OfflineQueuedScan` snapshot.
    private(set) var queuedPresentationScanId: String?
    /// Exact queued visual presentation that may continue the foreground
    /// phrase deck. Nonvisual and stale handoffs never populate this owner.
    @ObservationIgnored private var queuedVisualPresentationScanId: String?
    /// Only an exact active visual handoff may surface the in-memory carousel.
    /// Prepared handoffs use durable queue media even though they inherit the
    /// generic visual phrase deck.
    @ObservationIgnored private var queuedPresentationCarriesLiveMedia = false
    /// Ephemeral phrase order transferred with an exact live-to-queue
    /// presentation. It is never persisted, logged, or included in analytics.
    @ObservationIgnored private var queuedPresentationScanningPhrases: [String] = []
    @ObservationIgnored private var pendingFirstRenderMetric: (scanId: String, startedAt: CFAbsoluteTime)?
    var isProcessing: Bool = false
    var scanningPhaseText: String = "Analyzing subject"
    var activeMedia = ActiveScanMedia()
    var speciesData: SpeciesData?
    // MARK: - Environmental Telemetry State
    private(set) var activeLatitude: Double?
    private(set) var activeLongitude: Double?
    private(set) var activeElevation: Double?
    private var activeDeviceLocale: String?
    private var activeCurrentMonth: Int?
    private var activeTimeOfDay: String?
    private(set) var activeLocationName: String?
    private(set) var activeWeatherCondition: String?
    private(set) var activeTemperatureF: Double?
    private(set) var activeFlashFired: Bool?
    private(set) var activeDistanceInMeters: Float?

    /// True while the "enrichment" scope call (habitat, taxonomy, GBIF key) is in flight.
    var isEnrichmentLoading: Bool = false
    /// True while the "lookalikes" scope call (similar species cards) is in flight.
    var isLookalikesLoading: Bool = false
    // isReferenceImageLoading has been removed. Use activeMedia.referenceState.
    // MARK: - Background Rescue State
    /// One-time global reset guard for stale locally cached lookalikes.
    @ObservationIgnored private static var localLookalikesCacheResetInFlight = false
    @ObservationIgnored private let localAnalysisCoordinator:
        InferenceLocalAnalysisCoordinator
    @ObservationIgnored private let requestPaywall: @MainActor () -> Void
    @ObservationIgnored private let speciesReferenceService:
        SpeciesReferenceHydrationService
    @ObservationIgnored private let hydrationCoordinator:
        InferenceHydrationCoordinator
    @ObservationIgnored private let writeCoordinator = InferenceWriteCoordinator()
    @ObservationIgnored private var preparedPresentationOwner:
        AnalysisPresentationOwner?
    @ObservationIgnored private var activePresentationOwner:
        AnalysisPresentationOwner?
    var scanPresentationGeneration: UInt64 { writeCoordinator.generation }

    init(
        visionSubjectClassifier: any VisionSubjectClassifying = AppleVisionSubjectClassifier(),
        localVisualTraitExtractor: any LocalVisualTraitExtracting = AppleImageVisualTraitExtractor(),
        foundationVisualCueProvider: any FoundationVisualCueProviding = UnavailableFoundationVisualCueProvider(),
        foundationVisualCueEligibilityChecker: any FoundationVisualCueEligibilityChecking = SystemFoundationCueEligibility(),
        scanningPhraseSleeper: any ScanningPhraseSleeping = ContinuousScanningPhraseSleeper(),
        localAnalysisStartFeedback: @escaping @MainActor () -> Void = {},
        speciesReferenceService: SpeciesReferenceHydrationService = .live,
        hydrationCoordinator: InferenceHydrationCoordinator? = nil,
        requestPaywall: @escaping @MainActor () -> Void = {
            UsageManager.shared.showPaywall = true
        }
    ) {
        self.localAnalysisCoordinator = InferenceLocalAnalysisCoordinator(
            dependencies: .init(
                classifier: visionSubjectClassifier,
                traitExtractor: localVisualTraitExtractor,
                foundationCueProvider: foundationVisualCueProvider,
                foundationCueEligibilityChecker:
                    foundationVisualCueEligibilityChecker,
                phraseSleeper: scanningPhraseSleeper,
                startFeedback: localAnalysisStartFeedback
            )
        )
        self.speciesReferenceService = speciesReferenceService
        self.hydrationCoordinator = hydrationCoordinator
            ?? InferenceHydrationCoordinator()
        self.requestPaywall = requestPaywall
    }

    private enum LiveReferenceHydrationPolicy: Sendable, Equatable {
        case none
        case showLoadingWhenReferenceMissing
    }

    private func resetTrackedBackgroundWrites() {
        writeCoordinator.resetPresentationWrites()
    }

    private func beginIdentificationReviewAction(scanId: String) -> UInt64 {
        writeCoordinator.beginIdentificationAction(
            scanId: scanId,
            channel: .review
        )
    }

    private func beginIdentificationConfirmationAction(
        scanId: String
    ) -> UInt64 {
        writeCoordinator.beginIdentificationAction(
            scanId: scanId,
            channel: .confirmation
        )
    }

    private func isIdentificationReviewActionCurrent(
        scanId: String,
        generation: UInt64
    ) -> Bool {
        writeCoordinator.isIdentificationActionCurrent(
            scanId: scanId,
            generation: generation,
            channel: .review
        )
    }

    private func beginIdentificationFlagAction(scanId: String) -> UInt64 {
        writeCoordinator.beginIdentificationAction(
            scanId: scanId,
            channel: .legacyFlag
        )
    }

    private func isIdentificationFlagActionCurrent(
        scanId: String,
        generation: UInt64
    ) -> Bool {
        writeCoordinator.isIdentificationActionCurrent(
            scanId: scanId,
            generation: generation,
            channel: .legacyFlag
        )
    }

    @discardableResult
    private func enqueueIdentificationWrite(
        scanId: String,
        actionGeneration: UInt64,
        channel: InferenceWriteCoordinator.IdentificationChannel = .review,
        operation: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never>? {
        writeCoordinator.enqueueIdentificationWrite(
            scanId: scanId,
            actionGeneration: actionGeneration,
            channel: channel,
            operation: operation
        )
    }

    private func isLiveSpeciesPresentation(
        scanId: String,
        scientificName: String,
        presentationGeneration: UInt64? = nil,
        reviewActionGeneration: UInt64? = nil
    ) -> Bool {
        guard let current = speciesData,
              current.scanId?.caseInsensitiveCompare(scanId) == .orderedSame,
              current.scientificName.caseInsensitiveCompare(scientificName) == .orderedSame else {
            return false
        }
        if let presentationGeneration,
           writeCoordinator.generation != presentationGeneration {
            return false
        }
        guard let reviewActionGeneration else { return true }
        return isIdentificationReviewActionCurrent(
            scanId: scanId,
            generation: reviewActionGeneration
        )
    }

    private func cancelSpeciesHydrationForIdentificationChange() {
        hydrationCoordinator.cancelAllTasks()
        isEnrichmentLoading = false
        isLookalikesLoading = false
    }

    private func executeSpeciesMetadataWrite(
        scanId: String,
        scientificName: String,
        presentationGeneration: UInt64,
        reviewActionGeneration: UInt64?,
        operation: @escaping @Sendable () async -> Void
    ) {
        guard !writeCoordinator.isAuthTransitionFenceActive else { return }
        let guardedOperation: @Sendable () async -> Void = { [weak self] in
            guard !Task.isCancelled,
                  let self,
                  await self.isLiveSpeciesPresentation(
                      scanId: scanId,
                      scientificName: scientificName,
                      presentationGeneration: presentationGeneration,
                      reviewActionGeneration: reviewActionGeneration
                  ) else {
                return
            }
            await operation()
        }

        if let reviewActionGeneration {
            enqueueIdentificationWrite(
                scanId: scanId,
                actionGeneration: reviewActionGeneration,
                operation: guardedOperation
            )
        } else {
            writeCoordinator.enqueueBackgroundWrite(guardedOperation)
        }
    }

    /// Synchronously closes new presentation writes at Auth-transition
    /// admission and cancels every existing producer. Ephemeral local visual
    /// work is fenced and released here; only durable write owners participate
    /// in the async quiescence drain.
    func beginAuthTransitionWriteFence() {
        guard writeCoordinator.beginAuthTransitionFence() else { return }
        _ = hydrationCoordinator.beginAuthTransitionFence()
        inferenceTask?.cancel()
        cancelLocalVisualAnalysis()
        preparedPresentationOwner = nil
        activePresentationOwner = nil
        recoverablePresentationScanId = nil
        queuedPresentationScanId = nil
        queuedVisualPresentationScanId = nil
        queuedPresentationCarriesLiveMedia = false
        queuedPresentationScanningPhrases = []
        scanningPhaseText = ScanningPhraseCoordinator.genericPhrases[0]
        activeMedia = ActiveScanMedia()
        resetTrackedBackgroundWrites()
    }

    func awaitAuthTransitionWriteQuiescence() async {
        guard writeCoordinator.isAuthTransitionFenceActive else { return }

        _ = await inferenceTask?.result
        await hydrationCoordinator.awaitQuiescence()
        await writeCoordinator.awaitQuiescence()

        inferenceTask = nil
        localAnalysisCoordinator.cancel()
        preparedPresentationOwner = nil
        activePresentationOwner = nil
        queuedVisualPresentationScanId = nil
        queuedPresentationCarriesLiveMedia = false
    }

    func finishAuthTransitionWriteFence() {
        hydrationCoordinator.finishAuthTransitionFence()
        writeCoordinator.finishAuthTransitionFence()
    }

    private func hasUsableLookalikeTaxonomy(_ taxonomy: TaxonomyData?) -> Bool {
        taxonomy?.hasUsableLookalikeValidation == true
    }

    nonisolated static func plannedEnrichmentScopes(
        needsMetadata: Bool,
        needsLookalikes: Bool,
        speciesIsEnriched: Bool
    ) -> (metadata: Bool, lookalikes: Bool) {
        (
            metadata: needsMetadata && !speciesIsEnriched,
            lookalikes: needsLookalikes
        )
    }

    private func shouldResetLocalLookalikesCache() -> Bool {
        UserDefaults.standard.integer(forKey: UserDefaultsKeys.localLookalikesCacheResetVersion) <
        MerianConfig.localLookalikesCacheResetVersion
    }

    private func scheduleLocalLookalikesCacheResetIfNeeded(modelContext: ModelContext?) {
        guard shouldResetLocalLookalikesCache(),
              !Self.localLookalikesCacheResetInFlight,
              let container = modelContext?.container else { return }

        Self.localLookalikesCacheResetInFlight = true
        Task.detached(priority: .utility) {
            let dbActor = BackgroundDatabaseActor(modelContainer: container)
            await dbActor.clearAllLocalLookalikesCache()
            await MainActor.run {
                UserDefaults.standard.set(
                    MerianConfig.localLookalikesCacheResetVersion,
                    forKey: UserDefaultsKeys.localLookalikesCacheResetVersion
                )
                Self.localLookalikesCacheResetInFlight = false
            }
        }
    }

    // MARK: - Live Inference Pipeline

    /// Synchronously resets all display state so the content router sees
    /// `isProcessing == true && speciesData == nil` from the very first frame
    /// when the insight sheet opens — even when the previous scan was a library
    /// load that had already finished (`isProcessing == false`, `speciesData != nil`).
    ///
    /// Called by `CaptureWorkspaceViewModel.submitStagedCapture(...)` before `activeSheet = .insight`.
    /// `analyze()` will subsequently overwrite image and telemetry fields with the
    /// new scan's data once the async telemetry Task resolves.
    ///
    /// Contrast with `cancelActiveRequest()`, which resets to idle with no upcoming scan.
    func prepareForNewScan(
        scanId: String? = nil,
        attemptGeneration: UUID? = nil,
        modality: ScanPresentationModality = .visual
    ) {
        guard !writeCoordinator.isAuthTransitionFenceActive else { return }
        // Cancel all in-flight async work before the new scan claims the engine.
        invalidateActiveLiveInferenceAttempt(
            resumeBackground: true,
            reason: "live_scan_replaced"
        )
        self.inferenceTask?.cancel()
        self.hydrationCoordinator.cancelAllTasks()
        self.hydrationCoordinator.resetEnrichmentRateLimit()
        self.cancelLocalVisualAnalysis()
        self.resetTrackedBackgroundWrites()

        // Reset scan identity and processing flags.
        self.activeScanId = nil
        self.activePresentationOwner = nil
        self.recoverablePresentationScanId = nil
        self.queuedPresentationScanId = nil
        self.queuedVisualPresentationScanId = nil
        self.queuedPresentationCarriesLiveMedia = false
        self.queuedPresentationScanningPhrases = []
        if let scanId, let attemptGeneration {
            self.preparedPresentationOwner = AnalysisPresentationOwner(
                scanId: scanId,
                attemptGeneration: attemptGeneration,
                modality: modality
            )
        } else {
            self.preparedPresentationOwner = nil
        }
        self.pendingFirstRenderMetric = nil
        self.isProcessing = true
        self.scanningPhaseText = ScanningPhraseCoordinator.genericPhrases[0]
        self.isEnrichmentLoading = false
        self.isLookalikesLoading = false
        self.speciesData = nil
        self.activeMedia = ActiveScanMedia()

        // Clear telemetry so stale GPS/weather cannot bleed into the new scan's display.
        self.activeLatitude = nil
        self.activeLongitude = nil
        self.activeElevation = nil
        self.activeLocationName = nil
        self.activeWeatherCondition = nil
        self.activeTemperatureF = nil
    }

    private func filteredObservationContexts(_ observationContexts: [ObservationContext]) -> [ObservationContext] {
        observationContexts.filter { !$0.isEmpty }
    }

    private func observationContextJSONStrings(from observationContexts: [ObservationContext]) -> [String] {
        observationContexts.compactMap { context in
            (try? JSONEncoder().encode(context)).flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    private func resolvedAudioPath(for audioFilePath: String) -> String {
        let normalizedPath = audioFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedPath.hasPrefix("/") {
            if FileManager.default.fileExists(atPath: normalizedPath) {
                return normalizedPath
            }
            let filename = URL(fileURLWithPath: normalizedPath).lastPathComponent
            let documentsPath = URL.documentsDirectory.appendingPathComponent(filename).path
            if FileManager.default.fileExists(atPath: documentsPath) {
                return documentsPath
            }
            return normalizedPath
        }
        let docsPath = URL.documentsDirectory.appendingPathComponent(normalizedPath).path
        let tempPath = FileManager.default.temporaryDirectory.appendingPathComponent(normalizedPath).path
        return FileManager.default.fileExists(atPath: docsPath) ? docsPath : tempPath
    }

    private func resolvedVideoPath(for videoFilePath: String) -> String? {
        let normalizedPath = videoFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedPath.hasPrefix("http://") || normalizedPath.hasPrefix("https://") {
            return SecureTransportPolicy.httpsURL(
                from: normalizedPath
            )?.absoluteString
        }
        if normalizedPath.hasPrefix("/") {
            if FileManager.default.fileExists(atPath: normalizedPath) {
                return normalizedPath
            }
            let filename = URL(fileURLWithPath: normalizedPath).lastPathComponent
            let documentsPath = URL.documentsDirectory.appendingPathComponent(filename).path
            if FileManager.default.fileExists(atPath: documentsPath) {
                return documentsPath
            }
            return normalizedPath
        }
        let docsPath = URL.documentsDirectory.appendingPathComponent(normalizedPath).path
        let tempPath = FileManager.default.temporaryDirectory.appendingPathComponent(normalizedPath).path
        return FileManager.default.fileExists(atPath: docsPath) ? docsPath : tempPath
    }

    nonisolated static func normalizedReferenceURLs(from rawValue: String?) -> [String] {
        ExternalReferenceImagePolicy.allowedURLStrings(from: rawValue)
    }

    private func mediaItems(
        from mediaTimeline: [CaptureSubmissionMediaItem],
        liveImageDatas: [Data]?,
        persistedImagePaths: [String]?
    ) -> [MediaItem] {
        var items: [MediaItem] = []

        for (timelineIndex, item) in mediaTimeline.enumerated() {
            switch item {
            case .image(let imageIndex):
                if mediaTimeline.indices.contains(timelineIndex + 1),
                   case .video = mediaTimeline[timelineIndex + 1] {
                    continue
                }
                if let liveImageDatas, liveImageDatas.indices.contains(imageIndex) {
                    items.append(.liveImage(liveImageDatas[imageIndex]))
                } else if let persistedImagePaths, persistedImagePaths.indices.contains(imageIndex) {
                    items.append(.image(persistedImagePaths[imageIndex]))
                }
            case .audio(let audioFilePath):
                items.append(.audio(resolvedAudioPath(for: audioFilePath)))
            case .video(let videoFilePath, let posterImageIndex, _):
                let fallbackImage = posterImageIndex.flatMap { imageIndex -> VideoFallbackImageSource? in
                    if let liveImageDatas, liveImageDatas.indices.contains(imageIndex) {
                        return .liveImage(liveImageDatas[imageIndex])
                    }
                    if let persistedImagePaths, persistedImagePaths.indices.contains(imageIndex) {
                        return .imagePath(persistedImagePaths[imageIndex])
                    }
                    return nil
                }
                if let videoPath = resolvedVideoPath(for: videoFilePath) {
                    items.append(.video(
                        videoPath,
                        fallbackImage: fallbackImage
                    ))
                } else if let fallbackImage {
                    switch fallbackImage {
                    case .liveImage(let data):
                        items.append(.liveImage(data))
                    case .imagePath(let path):
                        items.append(.image(path))
                    }
                }
            case .description(let context):
                guard !context.isEmpty else { continue }
                items.append(.description(context))
            }
        }

        return items
    }

    private func applyNewDiscoveryIfNeeded(_ isNewDiscovery: Bool, to mappedData: inout SpeciesData) {
        guard isNewDiscovery else { return }
        mappedData.isNewDiscovery = true
        GamificationManager.shared.recordNewSpeciesDiscovered()
    }

    private func transferReplacementMetadataIfNeeded(
        from oldScanId: String?,
        to newScanId: String?,
        modelContext: ModelContext?
    ) {
        guard let oldScanId else { return }
        guard let context = modelContext else {
            assertionFailure("targetEradicationScanId provided but modelContext is nil")
            return
        }
        var oldDescriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == oldScanId }
        )
        oldDescriptor.fetchLimit = 1
        guard let oldRecord = try? context.fetch(oldDescriptor).first else { return }

        // Transfer user-generated metadata to the new scan before the old record is deleted.
        // Review state intentionally resets because this is a fresh analysis.
        if let newScanId {
            let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == newScanId })
            if let newRecord = try? context.fetch(descriptor).first {
                newRecord.customTags = oldRecord.customTags
                if let oldCollections = oldRecord.collections, !oldCollections.isEmpty {
                    newRecord.collections = oldCollections
                }
                let newRecordHasFieldNotes = !(newRecord.fieldNotes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                if let oldFieldNotes = oldRecord.fieldNotes?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !oldFieldNotes.isEmpty,
                   !newRecordHasFieldNotes {
                    newRecord.fieldNotes = oldRecord.fieldNotes
                }
            }
        }

        ScanRepository.shared.eradicateScan(record: oldRecord, modelContext: context)
    }

    private func applyReferenceStateIfAvailable(from mappedData: SpeciesData) {
        guard !mappedData.shouldSuppressReferenceImages else {
            activeMedia.referenceState = .empty
            return
        }
        let refs = Self.normalizedReferenceURLs(from: mappedData.referenceImageUrl)
        if !refs.isEmpty {
            activeMedia.referenceState = .loaded(refs)
        }
    }

    /// Publishes a completed core identification as one main-actor state transition.
    /// Result content is assigned before `isProcessing` clears so observers cannot render
    /// a completed carousel alongside the analyzing content subtree. The owner check also
    /// prevents a cancelled task from committing over a newer scan.
    @discardableResult
    func commitSuccessfulResult(
        for ownedScanId: String?,
        attemptGeneration: UUID,
        foregroundInferenceGeneration: UUID?,
        speciesData: SpeciesData,
        persistedMediaItems: [MediaItem]? = nil
    ) -> Bool {
        guard isLiveInferenceAttemptCurrent(
            scanId: ownedScanId,
            attemptGeneration: attemptGeneration,
            foregroundInferenceGeneration: foregroundInferenceGeneration
        ) else {
            return false
        }

        publishSuccessfulResult(
            speciesData,
            persistedMediaItems: persistedMediaItems
        )
        if speciesData.isBiological, let completedScanId = speciesData.scanId {
            AppDIContainer.shared.appEventPublisher.send(
                .foregroundBiologicalScanCompleted(scanId: completedScanId)
            )
        }
        return true
    }

    /// Publishes a terminal background result only when it replaces the exact
    /// live presentation attempt that relinquished durable ownership.
    ///
    /// Background recovery owns a different inference generation, so it cannot
    /// satisfy the foreground job-generation check above. Instead, the caller
    /// must prove the old presentation UUID still owns the engine and that no
    /// foreground generation currently owns this scan.
    @discardableResult
    func commitRecoveredBackgroundResult(
        for scanId: String,
        replacingAttemptGeneration: UUID,
        expectedForegroundGeneration: UUID?,
        speciesData: SpeciesData
    ) -> Bool {
        guard isLocalLiveInferenceAttemptCurrent(
            scanId: scanId,
            attemptGeneration: replacingAttemptGeneration
        ),
              activeForegroundInferenceGeneration
                == expectedForegroundGeneration,
              OfflineQueueManager.shared
                .foregroundInferenceGenerations[scanId] == nil else {
            return false
        }

        // Transfer the presentation slot before the caller cooperatively cancels
        // the old task. Otherwise that task can resume an error handler, still
        // pass its local UUID check, and overwrite this recovered result.
        activeScanId = nil
        activeLiveInferenceAttemptGeneration = nil
        activeForegroundInferenceGeneration = nil
        cancelLocalVisualAnalysis()
        publishSuccessfulResult(speciesData)
        return true
    }

    /// Publishes a queued/background response after the corresponding live
    /// request already exited with an ambiguous transport or idempotency
    /// result. The retained scan ID is the presentation fence once the live
    /// task's local UUID has been cleared.
    @discardableResult
    func commitRecoveredQueuedResult(
        for scanId: String,
        speciesData: SpeciesData
    ) -> Bool {
        guard recoverablePresentationScanId == scanId,
              speciesData.scanId?.caseInsensitiveCompare(scanId)
                == .orderedSame,
              activeScanId == nil || activeScanId == scanId else {
            return false
        }

        activeScanId = nil
        activeLiveInferenceAttemptGeneration = nil
        activeForegroundInferenceGeneration = nil
        recoverablePresentationScanId = nil
        cancelLocalVisualAnalysis()
        publishSuccessfulResult(speciesData)
        return true
    }

    /// Rehydrates a status-recovered owner row into the still-presented live
    /// sheet. `load(from:)` supplies the complete persisted media and metadata
    /// mapping, while the retained ID prevents a stale recovery from replacing
    /// another scan.
    @discardableResult
    func commitRecoveredQueuedRecord(
        _ record: LocalScanRecord,
        for scanId: String
    ) -> Bool {
        guard recoverablePresentationScanId == scanId,
              record.id == scanId,
              activeScanId == nil || activeScanId == scanId else {
            return false
        }

        recoverablePresentationScanId = nil
        load(from: record)
        return true
    }

    private func publishSuccessfulResult(
        _ speciesData: SpeciesData,
        persistedMediaItems: [MediaItem]? = nil
    ) {
        preparedPresentationOwner = nil
        activePresentationOwner = nil
        recoverablePresentationScanId = nil
        queuedPresentationScanId = nil
        queuedVisualPresentationScanId = nil
        queuedPresentationCarriesLiveMedia = false
        queuedPresentationScanningPhrases = []
        if let persistedMediaItems {
            activeMedia.items = persistedMediaItems
        }
        self.speciesData = speciesData
        applyReferenceStateIfAvailable(from: speciesData)
        isProcessing = false
    }

    private func isLocalLiveInferenceAttemptCurrent(
        scanId: String?,
        attemptGeneration: UUID
    ) -> Bool {
        activeScanId == scanId &&
            activeLiveInferenceAttemptGeneration == attemptGeneration
    }

    private func isLiveInferenceAttemptCurrent(
        scanId: String?,
        attemptGeneration: UUID,
        foregroundInferenceGeneration: UUID?
    ) -> Bool {
        guard isLocalLiveInferenceAttemptCurrent(
            scanId: scanId,
            attemptGeneration: attemptGeneration
        ) else {
            return false
        }
        guard activeForegroundInferenceGeneration
                == foregroundInferenceGeneration else {
            return false
        }
        guard let scanId, let foregroundInferenceGeneration else {
            return foregroundInferenceGeneration == nil
        }
        return OfflineQueueManager.shared
            .isForegroundInferenceAttemptCurrent(
                scanId: scanId,
                generation: foregroundInferenceGeneration
            )
    }

    private func checkLiveInferenceAttempt(
        scanId: String?,
        attemptGeneration: UUID,
        foregroundInferenceGeneration: UUID?
    ) throws {
        try Task.checkCancellation()
        guard isLiveInferenceAttemptCurrent(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundInferenceGeneration: foregroundInferenceGeneration
        ) else {
            throw CancellationError()
        }
    }

    private func invalidateActiveLiveInferenceAttempt(
        resumeBackground: Bool,
        reason: String
    ) {
        let scanId = activeScanId
        let foregroundGeneration = activeForegroundInferenceGeneration
        activeScanId = nil
        activeLiveInferenceAttemptGeneration = nil
        activeForegroundInferenceGeneration = nil

        guard let scanId, let foregroundGeneration else { return }
        OfflineQueueManager.shared.releaseDeferredLiveUpload(
            scanId: scanId,
            foregroundInferenceGeneration: foregroundGeneration,
            reason: reason
        )
        OfflineQueueManager.shared.retireForegroundInference(
            scanId: scanId,
            generation: foregroundGeneration,
            resumeBackground: resumeBackground,
            reason: reason
        )
    }

    private func isDuplicateActiveForegroundAttempt(
        scanId: String,
        generation: UUID
    ) -> Bool {
        activeScanId == scanId &&
            activeForegroundInferenceGeneration == generation &&
            activeLiveInferenceAttemptGeneration != nil
    }

    private func retireForegroundInferenceIfCurrent(
        scanId: String?,
        attemptGeneration: UUID,
        foregroundInferenceGeneration: UUID?,
        resumeBackground: Bool,
        reason: String
    ) {
        guard let scanId, let foregroundInferenceGeneration,
              isLocalLiveInferenceAttemptCurrent(
                  scanId: scanId,
                  attemptGeneration: attemptGeneration
              ),
              activeForegroundInferenceGeneration
                == foregroundInferenceGeneration else {
            return
        }

        OfflineQueueManager.shared.retireForegroundInference(
            scanId: scanId,
            generation: foregroundInferenceGeneration,
            resumeBackground: resumeBackground,
            reason: reason
        )
        if isLocalLiveInferenceAttemptCurrent(
            scanId: scanId,
            attemptGeneration: attemptGeneration
        ) {
            activeForegroundInferenceGeneration = nil
        }
    }

    @discardableResult
    private func completeQueuedLiveInferenceIfNeeded(
        scanId: String?,
        attemptGeneration: UUID,
        foregroundInferenceGeneration: UUID?,
        mediaPathsToKeep: [String]
    ) async -> Bool {
        guard let scanId, let foregroundInferenceGeneration else {
            return true
        }

        // Queue removal, URLSession cancellation, and disk cleanup all compare
        // the durable foreground generation under the per-scan persistence lock.
        let didDelete = await OfflineQueueManager.shared.deleteQueuedScan(
            scanId: scanId,
            explicitlyAdoptedMediaPaths: mediaPathsToKeep,
            preservePreferredGoalHint: true,
            foregroundInferenceExpectation:
                ForegroundInferenceGenerationExpectation(
                    generation: foregroundInferenceGeneration
                )
        )
        if didDelete {
            if isLocalLiveInferenceAttemptCurrent(
                scanId: scanId,
                attemptGeneration: attemptGeneration
            ) {
                activeForegroundInferenceGeneration = nil
            }
            return true
        }

        retireForegroundInferenceIfCurrent(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundInferenceGeneration: foregroundInferenceGeneration,
            resumeBackground: true,
            reason: "live_cleanup_failed_or_replaced"
        )
        return false
    }

    private func sendInferenceCompleteNotificationIfEnabled(for mappedData: SpeciesData) {
        guard AppSettings.shared.isPushNotificationsEnabled,
              let scanId = mappedData.scanId else { return }

        PushNotificationManager.shared.sendInferenceCompleteNotification(
            speciesName: mappedData.commonName,
            scanId: scanId
        )
    }

    private func schedulePostInferenceHydrationIfNeeded(
        for mappedData: SpeciesData,
        modelContext: ModelContext?,
        referencePolicy: LiveReferenceHydrationPolicy
    ) {
        guard mappedData.hasResolvedBiologicalIdentification,
              !mappedData.isHumanSubject,
              let capturedScanId = mappedData.scanId else {
            return
        }

        let capturedScientificName = mappedData.scientificName
        let capturedPresentationGeneration = writeCoordinator.generation
        let reviewActionGeneration =
            beginIdentificationReviewAction(scanId: capturedScanId)
        let capturedGbifKey = mappedData.gbifTaxonKey
        let capturedHasWikipedia = mappedData.wikipediaOverview != nil
        let shouldShowReferenceLoading = referencePolicy == .showLoadingWhenReferenceMissing &&
            capturedGbifKey != nil &&
            Self.normalizedReferenceURLs(from: mappedData.referenceImageUrl).isEmpty

        hydrationCoordinator.replaceTask(in: .live) { [weak self] in
            guard let self else { return }
            defer {
                if shouldShowReferenceLoading,
                   self.speciesData?.scanId == capturedScanId,
                   self.activeMedia.referenceState == .loading {
                    self.activeMedia.referenceState = .empty
                }
            }

            if shouldShowReferenceLoading {
                self.activeMedia.referenceState = .loading
            }

            let capturedIsEnriched = self.hydrationCoordinator
                .isSpeciesEnriched(capturedScientificName)
            let plannedScopes = Self.plannedEnrichmentScopes(
                needsMetadata: true,
                needsLookalikes: true,
                speciesIsEnriched: capturedIsEnriched
            )

            await withTaskGroup(of: Void.self) { group in
                if !capturedHasWikipedia {
                    group.addTask { @MainActor [weak self] in
                        guard let self else { return }
                        await self.fetchWikipediaAndHydrate(
                            for: capturedScientificName,
                            scanId: capturedScanId,
                            presentationGeneration: capturedPresentationGeneration,
                            reviewActionGeneration: reviewActionGeneration,
                            modelContext: modelContext
                        )
                    }
                }

                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    var taxonKeyToUse = capturedGbifKey

                    if plannedScopes.metadata || plannedScopes.lookalikes {
                        await self.fetchAndApplyEnrichment(
                            modelContext: modelContext,
                            needsMetadata: plannedScopes.metadata,
                            needsLookalikes: plannedScopes.lookalikes,
                            reviewActionGeneration: reviewActionGeneration
                        )
                        taxonKeyToUse = self.speciesData?.gbifTaxonKey ?? taxonKeyToUse
                    }

                    guard !Task.isCancelled else { return }

                    if let key = taxonKeyToUse {
                        await self.fetchGBIFImagesAndHydrate(
                            for: key,
                            scanId: capturedScanId,
                            scientificName: capturedScientificName,
                            presentationGeneration: capturedPresentationGeneration,
                            reviewActionGeneration: reviewActionGeneration,
                            modelContext: modelContext
                        )
                    }
                }
            }

            // Only mark the species as enriched when the call actually succeeded.
            if !capturedIsEnriched && !Task.isCancelled,
               self.speciesData?.habitatDescription != nil,
               self.hasUsableLookalikeTaxonomy(self.speciesData?.taxonomy) {
                self.hydrationCoordinator.markSpeciesEnriched(
                    capturedScientificName
                )
            }
        }
    }

    /// Runs the live AI taxonomy pipeline for a new scan submission.
    ///
    /// Dispatches the Gemini inference request, parses and persists the result, updates all
    /// observable state for the insight sheet, and registers one structured
    /// post-inference hydration operation for Wikipedia, enrichment, and GBIF
    /// images.
    ///
    /// The method is idempotent with respect to in-flight work — calling it cancels any
    /// existing inference and live-hydration work before starting the new pipeline.
    ///
    /// - Parameters:
    ///   - scanId: The `OfflineQueuedScan.id` for this capture. Passed to the Edge function
    ///     so the backend can correlate the live response with the queued upload.
    ///   - imageDatas: 1024 px inference-quality images. Sent to Gemini as base64.
    ///   - displayDatas: 2048 px display-quality images. Written to disk so the insight
    ///     sheet renders without JPEG blocking artifacts. Never sent to AI.
    ///     Falls back to `imageDatas` when empty (e.g. offline-queue reprocessing path).
    ///   - telemetry: GPS, weather, and device context bundled at capture time.
    ///   - modelContext: The SwiftData context for persisting the parsed scan record locally.
    ///   - targetEradicationScanId: An optional historic scan ID passed exclusively when replacing a scan with a fresh analysis.
    ///   - observationContexts: Structured descriptions staged alongside the capture.
    func analyze(
        scanId: String? = nil,
        foregroundInferenceGeneration: UUID? = nil,
        imageDatas: [Data],
        displayDatas: [Data] = [],
        audioFilePaths: [String]? = nil,
        videoFilePaths: [String]? = nil,
        telemetry: CaptureTelemetry,
        observationContexts: [ObservationContext] = [],
        mediaTimeline: [CaptureSubmissionMediaItem]? = nil,
        visualMediaItems: [IdentifyVisualMediaItem]? = nil,
        preferredGoal: FieldTripPreferredGoal? = nil,
        modelContext: ModelContext? = nil,
        targetEradicationScanId: String? = nil,
        userPerceivedStart: CFAbsoluteTime? = nil
    ) {
        guard !writeCoordinator.isAuthTransitionFenceActive else {
            if let scanId, let foregroundInferenceGeneration {
                OfflineQueueManager.shared.releaseDeferredLiveUpload(
                    scanId: scanId,
                    foregroundInferenceGeneration:
                        foregroundInferenceGeneration,
                    reason: "auth_transition_active"
                )
                OfflineQueueManager.shared.retireForegroundInference(
                    scanId: scanId,
                    generation: foregroundInferenceGeneration,
                    resumeBackground: true,
                    reason: "auth_transition_active"
                )
            }
            return
        }
        guard !imageDatas.isEmpty else {
            if let scanId, let foregroundInferenceGeneration {
                OfflineQueueManager.shared.releaseDeferredLiveUpload(
                    scanId: scanId,
                    foregroundInferenceGeneration:
                        foregroundInferenceGeneration,
                    reason: "live_visual_payload_empty"
                )
                OfflineQueueManager.shared.retireForegroundInference(
                    scanId: scanId,
                    generation: foregroundInferenceGeneration,
                    resumeBackground: true,
                    reason: "live_visual_payload_empty"
                )
            }
            return
        }
        if let scanId {
            guard let foregroundInferenceGeneration else {
                MerianLog.general.debug(
                    "analyze: rejected missing foreground owner scanId=\(scanId, privacy: .public)"
                )
                return
            }
            guard !isDuplicateActiveForegroundAttempt(
                scanId: scanId,
                generation: foregroundInferenceGeneration
            ) else {
                MerianLog.general.debug(
                    "analyze: ignored duplicate foreground generation scanId=\(scanId, privacy: .public)"
                )
                return
            }
            guard OfflineQueueManager.shared.claimForegroundInferenceStart(
                        scanId: scanId,
                        generation: foregroundInferenceGeneration
                  ) else {
                MerianLog.general.debug(
                    "analyze: rejected missing, stale, used, or retiring foreground owner scanId=\(scanId, privacy: .public)"
                )
                return
            }
        } else if foregroundInferenceGeneration != nil {
            MerianLog.general.debug(
                "analyze: rejected foreground owner without scanId"
            )
            return
        }
        invalidateActiveLiveInferenceAttempt(
            resumeBackground: true,
            reason: "live_scan_replaced_by_analyze"
        )
        self.inferenceTask?.cancel()
        self.hydrationCoordinator.cancelAllTasks()
        self.cancelLocalVisualAnalysis()
        self.resetTrackedBackgroundWrites()

        // Reset loading flags synchronously before the cancelled tasks' defer blocks can run
        // on @MainActor. Without this, a stale defer from the old task can fire after the new
        // pipeline has already set these flags to true, prematurely clearing the skeletons.
        self.isEnrichmentLoading = false
        self.isLookalikesLoading = false
        self.activeMedia = ActiveScanMedia()
        let datasToUse = displayDatas.isEmpty ? imageDatas : displayDatas
        let resolvedObservationContexts = filteredObservationContexts(observationContexts)
        let resolvedMediaTimeline = mediaTimeline ?? CaptureSubmissionMediaItem.defaultTimeline(
            imageCount: datasToUse.count,
            observationContexts: resolvedObservationContexts,
            audioFilePaths: audioFilePaths ?? [],
            videoFilePaths: videoFilePaths ?? []
        )
        let submissionProjection = resolvedMediaTimeline.submissionMediaProjection
        let ownerMediaTimeline = mediaTimeline == nil
            ? nil
            : submissionProjection.ownerMediaTimeline
        self.activeMedia.items = mediaItems(
            from: resolvedMediaTimeline,
            liveImageDatas: datasToUse,
            persistedImagePaths: nil
        )
        self.activeMedia.focusRegionsBySourceIndex = visualMediaItems?.focusRegionsBySourceIndex ?? [:]
        
        self.speciesData = nil

        // Queue-backed attempts use the same UUID persisted on the durable job;
        // queue-less online descriptions receive a process-local owner.
        let attemptGeneration =
            foregroundInferenceGeneration ?? UUID()
        self.activeScanId = scanId
        self.activeLiveInferenceAttemptGeneration = attemptGeneration
        self.activeForegroundInferenceGeneration =
            foregroundInferenceGeneration
        self.preparedPresentationOwner = nil
        self.activePresentationOwner = AnalysisPresentationOwner(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            modality: .visual
        )
        self.activeLatitude = telemetry.gpsLatitude
        self.activeLongitude = telemetry.gpsLongitude
        self.activeElevation = telemetry.gpsElevation
        self.activeLocationName = telemetry.locationName
        self.activeWeatherCondition = telemetry.weatherCondition
        self.activeTemperatureF = telemetry.weatherTemperatureF
        self.activeDistanceInMeters = telemetry.subjectDistanceInMeters

        let capturedDisplayDatas = displayDatas

        if let firstData = imageDatas.first {
            classifySubjectLocally(
                from: firstData,
                focusRegion: visualMediaItems?.first?.focusRegion
            )
        }

        // Capture before the Task so the defer can compare against the ID this Task owns.
        let ownedScanId = scanId
        let ownedForegroundInferenceGeneration =
            foregroundInferenceGeneration
        let resolvedClientScanId = scanId ?? UUID().uuidString.lowercased()
        if let userPerceivedStart {
            self.pendingFirstRenderMetric = (
                scanId: resolvedClientScanId,
                startedAt: userPerceivedStart
            )
        }

        self.inferenceTask = Task { [weak self] in
            guard let self = self else { return }

            // Single exit point for isProcessing — covers all success, error, and cancellation paths.
            // Guard on ownedScanId: if a new scan called prepareForNewScan() + analyze() before this
            // Task's defer runs, activeScanId has already been updated to the new scan's ID. Writing
            // isProcessing=false or activeScanId=nil in that window would corrupt the new scan's state
            // (leaving the insight sheet stuck in a done-but-empty state). Only reset when this Task
            // still owns the active slot.
            defer {
                if self.isLocalLiveInferenceAttemptCurrent(
                    scanId: ownedScanId,
                    attemptGeneration: attemptGeneration
                ) {
                    self.isProcessing = false
                    self.activeScanId = nil
                    self.activeLiveInferenceAttemptGeneration = nil
                    self.activeForegroundInferenceGeneration = nil
                    if self.activePresentationOwner?.attemptGeneration
                        == attemptGeneration {
                        self.activePresentationOwner = nil
                    }
                    self.cancelLocalVisualAnalysis()
                }
            }

            let pipelineStart = CFAbsoluteTimeGetCurrent()
            let compressedDatas = imageDatas  // 1024 px — only these are base64-encoded for Gemini

            do {
                // --- Step 1: Pre-flight Checks & Data Preparation ---

                try self.checkLiveInferenceAttempt(
                    scanId: ownedScanId,
                    attemptGeneration: attemptGeneration,
                    foregroundInferenceGeneration:
                        ownedForegroundInferenceGeneration
                )
                if CircuitBreakerManager.shared.isCircuitTripped {
                    throw URLError(.notConnectedToInternet)
                }

                let client = MerianNetworkClient.shared

                let base64Strings = await InferenceProcessingActor.shared.encodeBase64(compressedDatas: compressedDatas)
                try self.checkLiveInferenceAttempt(
                    scanId: ownedScanId,
                    attemptGeneration: attemptGeneration,
                    foregroundInferenceGeneration:
                        ownedForegroundInferenceGeneration
                )
                let validBase64Strings = base64Strings.filter { !$0.isEmpty }
                guard !validBase64Strings.isEmpty else {
                    MerianLog.general.error("All base64 payloads are empty — corrupted capture data. Refunding scan.")
                    UsageManager.shared.refundScan(scanId: resolvedClientScanId)
                    OfflineQueueManager.shared.releaseDeferredLiveUpload(
                        scanId: resolvedClientScanId,
                        foregroundInferenceGeneration:
                            ownedForegroundInferenceGeneration,
                        reason: "live_visual_encoding_empty"
                    )
                    self.retireForegroundInferenceIfCurrent(
                        scanId: ownedScanId,
                        attemptGeneration: attemptGeneration,
                        foregroundInferenceGeneration:
                            ownedForegroundInferenceGeneration,
                        resumeBackground: true,
                        reason: "live_visual_encoding_empty"
                    )
                    return
                }

                // Detect actual encoding from JPEG magic bytes (FF D8 FF).
                // Falls back to WebP when the image was encoded with the primary path.
                let imageMimeType: String = {
                    guard let first = compressedDatas.first, first.count >= 3 else { return "image/webp" }
                    let prefix = [UInt8](first.prefix(3))
                    return (prefix[0] == 0xFF && prefix[1] == 0xD8 && prefix[2] == 0xFF) ? "image/jpeg" : "image/webp"
                }()

                try Task.checkCancellation()

                // --- Step 2: Edge Inference Generation (Gemini 1.5 Flash) ---

                MerianLog.general.debug("[⏱ BENCH] Pre-flight (encode+auth): \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - pipelineStart), privacy: .public)s")
                let inferenceStart = CFAbsoluteTimeGetCurrent()
                // Encode ObservationContext to JSON once: used for DB persistence (observationContextJSON)
                // and already serialised to plain text for the Gemini prompt (description).
                let observationContextsJSON = observationContextJSONStrings(
                    from: submissionProjection.observationContexts
                )
                let validVisualMediaItems = visualMediaItems?.count == validBase64Strings.count
                    ? visualMediaItems
                    : nil
                let videoFrameCount = validVisualMediaItems?
                    .filter { $0.kind == .videoFrame }
                    .count ?? (submissionProjection.videoFilePaths.isEmpty ? nil : imageDatas.count)
                let videoR2ObjectKeys: [String]
                if !submissionProjection.videoFilePaths.isEmpty {
                    videoR2ObjectKeys = try await client.uploadStagedVideoFiles(
                        videoFilePaths: submissionProjection.videoFilePaths,
                        scanId: resolvedClientScanId
                    )
                    try self.checkLiveInferenceAttempt(
                        scanId: ownedScanId,
                        attemptGeneration: attemptGeneration,
                        foregroundInferenceGeneration:
                            ownedForegroundInferenceGeneration
                    )
                } else {
                    videoR2ObjectKeys = []
                }
                let uploadFailSafe = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    OfflineQueueManager.shared.releaseDeferredLiveUpload(
                        scanId: resolvedClientScanId,
                        foregroundInferenceGeneration:
                            ownedForegroundInferenceGeneration,
                        reason: "inline_upload_two_second_failsafe"
                    )
                }
                defer { uploadFailSafe.cancel() }
                let resultData = try await client.identifyMultiModal(
                    // Inline images have no staged source object. Older clients sent a
                    // synthetic key here as a destination filename hint, which the durable
                    // finalizer could misclassify as an upload that must be promoted.
                    r2ObjectKeys: [],
                    base64ImageDatas: validBase64Strings,
                    mimeType: imageMimeType,
                    audioFilePaths: submissionProjection.audioFilePaths,
                    videoR2ObjectKeys: videoR2ObjectKeys,
                    videoFrameCount: videoFrameCount,
                    visualMediaItems: validVisualMediaItems,
                    audioMediaItems: submissionProjection.audioMediaItems,
                    ownerMediaTimeline: ownerMediaTimeline,
                    observationContextsJSON: observationContextsJSON,
                    telemetry: telemetry,
                    clientScanId: resolvedClientScanId,
                    preferredGoal: preferredGoal,
                    // A durable queue already owns every later transport retry
                    // and receives a bounded foreground deadline. Direct callers
                    // retain the reviewed long request window and inline replay.
                    durableQueueOwnsRecovery:
                        ownedForegroundInferenceGeneration != nil,
                    onRequestBodySent: { [weak self] in
                        Task { @MainActor in
                            OfflineQueueManager.shared.releaseDeferredLiveUpload(
                                scanId: resolvedClientScanId,
                                foregroundInferenceGeneration:
                                    ownedForegroundInferenceGeneration,
                                reason: "inline_request_body_sent"
                            )
                            self?.markInferenceRequestBodySent(
                                session: InferenceLocalAnalysisCoordinator.Session(
                                    scanId: ownedScanId,
                                    attemptGeneration: attemptGeneration,
                                    foregroundGeneration:
                                        ownedForegroundInferenceGeneration
                                )
                            )
                        }
                    }
                )
                try self.checkLiveInferenceAttempt(
                    scanId: ownedScanId,
                    attemptGeneration: attemptGeneration,
                    foregroundInferenceGeneration:
                        ownedForegroundInferenceGeneration
                )
                let responseReceivedAt = CFAbsoluteTimeGetCurrent()
                MerianLog.general.debug("Gemini inference completed in \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - inferenceStart), privacy: .public)s.")
                self.cancelLocalVisualAnalysis(resetPhraseCoordinator: false)

                // --- Step 3: Response Parsing & Local Persistence ---
                
                let postFlightStart = CFAbsoluteTimeGetCurrent()
                let parseResult = try await InferenceProcessingActor.shared.parseAndSave(
                    resultData: resultData,
                    telemetry: telemetry,
                    modelContext: modelContext,
                    compressedDatas: compressedDatas,
                    displayDatas: capturedDisplayDatas,
                    observationContextsJSON: observationContextsJSON,
                    audioFilePaths: submissionProjection.audioFilePaths.isEmpty
                        ? nil
                        : submissionProjection.audioFilePaths,
                    videoFilePaths: submissionProjection.videoFilePaths.isEmpty
                        ? nil
                        : submissionProjection.videoFilePaths,
                    mediaTimeline: resolvedMediaTimeline,
                    persistenceFence: ownedScanId.flatMap { scanId in
                        ownedForegroundInferenceGeneration.map { generation in
                            LiveInferencePersistenceFence(
                                scanId: scanId,
                                generation: generation
                            )
                        }
                    }
                )
                try self.checkLiveInferenceAttempt(
                    scanId: ownedScanId,
                    attemptGeneration: attemptGeneration,
                    foregroundInferenceGeneration:
                        ownedForegroundInferenceGeneration
                )
                guard parseResult.didCompletePersistence else {
                    self.retireForegroundInferenceIfCurrent(
                        scanId: ownedScanId,
                        attemptGeneration: attemptGeneration,
                        foregroundInferenceGeneration:
                            ownedForegroundInferenceGeneration,
                        resumeBackground: true,
                        reason: "live_result_persistence_rejected"
                    )
                    return
                }
                let finalMappedData = parseResult.mappedData
                let isNewDisc = parseResult.isNewDiscovery
                let savedImagePaths = parseResult.savedPaths

                // --- Step 4: UI State Updates & Gamification ---
                
                if var mappedData = finalMappedData {
                    applyNewDiscoveryIfNeeded(isNewDisc, to: &mappedData)
                    transferReplacementMetadataIfNeeded(
                        from: targetEradicationScanId,
                        to: mappedData.scanId,
                        modelContext: modelContext
                    )

                    CircuitBreakerManager.shared.recordSuccess()
                    AppTelemetry.trackScan(
                        isPro: RevenueCatManager.shared.isProActive,
                        isSubscribed: RevenueCatManager.shared.isSubscribed,
                        inferenceTier: mappedData.inferenceTier,
                        planUsed: parseResult.planUsed
                    )
                    let didCommitResult = self.commitSuccessfulResult(
                        for: ownedScanId,
                        attemptGeneration: attemptGeneration,
                        foregroundInferenceGeneration:
                            ownedForegroundInferenceGeneration,
                        speciesData: mappedData,
                        persistedMediaItems: self.mediaItems(
                            from: resolvedMediaTimeline,
                            liveImageDatas: nil,
                            persistedImagePaths: savedImagePaths
                        )
                    )
                    let stateCommittedAt = CFAbsoluteTimeGetCurrent()
                    MerianLog.general.debug(
                        "[⏱ BENCH] Response to first-result state: \(String(format: "%.3f", stateCommittedAt - responseReceivedAt), privacy: .public)s"
                    )
                    var didFinalizeQueue = true
                    if didCommitResult {
                        didFinalizeQueue =
                            await completeQueuedLiveInferenceIfNeeded(
                                scanId: scanId,
                                attemptGeneration: attemptGeneration,
                                foregroundInferenceGeneration:
                                    ownedForegroundInferenceGeneration,
                                mediaPathsToKeep:
                                    (mappedData.audioFilePaths ?? []) +
                                    (mappedData.videoFilePaths ?? [])
                            )
                    }
                    let stillOwnsPresentation =
                        self.isLocalLiveInferenceAttemptCurrent(
                            scanId: ownedScanId,
                            attemptGeneration: attemptGeneration
                        )
                    if didCommitResult,
                       didFinalizeQueue,
                       stillOwnsPresentation {
                        sendInferenceCompleteNotificationIfEnabled(
                            for: mappedData
                        )
                    }

                    MerianLog.general.debug("[⏱ BENCH] Post-flight (parse+save+state): \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - postFlightStart), privacy: .public)s")
                    MerianLog.general.debug("[⏱ BENCH] Total pipeline: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - pipelineStart), privacy: .public)s")

                    // --- Step 5: Post-Inference Background Hydration ---
                    if didCommitResult,
                       didFinalizeQueue,
                       stillOwnsPresentation {
                        schedulePostInferenceHydrationIfNeeded(
                            for: mappedData,
                            modelContext: modelContext,
                            referencePolicy: .showLoadingWhenReferenceMissing
                        )
                        Task { [mappedData] in
                            guard let scanId = mappedData.scanId else { return }
                            await AppDIContainer.shared.scanMilestoneCoordinator.processCompletedScan(
                                scanId: scanId,
                                speciesData: mappedData,
                                modelContainer: modelContext?.container
                            )
                        }
                    }
                }
            } catch {
                // --- Step 6: Failure Handling & Error State ---
                let stillOwnsAttempt =
                    self.isLiveInferenceAttemptCurrent(
                        scanId: ownedScanId,
                        attemptGeneration: attemptGeneration,
                        foregroundInferenceGeneration:
                            ownedForegroundInferenceGeneration
                    )

                // Cancellation: the task was cancelled (e.g., user started a new scan via
                // prepareForNewScan). The scan is already durably in the offline queue, so
                // the background upload path will complete it — no credit refund needed.
                if Task.isCancelled {
                    if stillOwnsAttempt {
                        self.releaseQueueBackedLiveInferenceForRecovery(
                            scanId: ownedScanId,
                            attemptGeneration: attemptGeneration,
                            foregroundInferenceGeneration:
                                ownedForegroundInferenceGeneration,
                            reason: "live_request_cancelled"
                        )
                    }
                    return
                }

                // Ownership checks also throw CancellationError when the queue
                // retires this provider generation without cancelling the Swift
                // task. Preserve the exact still-current sheet in that case.
                if error is CancellationError {
                    if publishQueuedRetiredOwnershipHandoffIfNeeded(
                        scanId: ownedScanId,
                        attemptGeneration: attemptGeneration,
                        foregroundInferenceGeneration:
                            ownedForegroundInferenceGeneration
                    ) {
                        return
                    }
                    if stillOwnsAttempt {
                        self.releaseQueueBackedLiveInferenceForRecovery(
                            scanId: ownedScanId,
                            attemptGeneration: attemptGeneration,
                            foregroundInferenceGeneration:
                                ownedForegroundInferenceGeneration,
                            reason: "live_request_cancelled"
                        )
                    }
                    return
                }

                if (error as? URLError)?.code == .cancelled {
                    _ = publishQueuedRecoveryHandoffIfNeeded(
                        scanId: ownedScanId,
                        attemptGeneration: attemptGeneration,
                        foregroundInferenceGeneration:
                            ownedForegroundInferenceGeneration,
                        telemetryEvent:
                            "InferenceQueuedForTransportCancellation",
                        reason: "live_transport_cancelled"
                    )
                    return
                }

                // Connectivity monitoring may have retired the durable foreground
                // generation before URLSession reports the matching failure. The
                // still-current local presentation remains authorized to acknowledge
                // that exact queue handoff, but it cannot publish provider results or
                // generic error state.
                if publishQueuedConnectivityFailureIfNeeded(
                    error,
                    scanId: ownedScanId,
                    attemptGeneration: attemptGeneration,
                    foregroundInferenceGeneration:
                        ownedForegroundInferenceGeneration
                ) {
                    return
                }

                guard stillOwnsAttempt else { return }
                self.releaseQueueBackedLiveInferenceForRecovery(
                    scanId: ownedScanId,
                    attemptGeneration: attemptGeneration,
                    foregroundInferenceGeneration:
                        ownedForegroundInferenceGeneration,
                    reason: "live_request_failed"
                )
                if ownedScanId != nil {
                    self.recoverablePresentationScanId = resolvedClientScanId
                }

                if publishRecoverableInferenceConflictIfNeeded(
                    error,
                    scanId: resolvedClientScanId,
                    telemetry: telemetry
                ) {
                    return
                }

                if publishConsentRequiredIfNeeded(
                    error,
                    telemetry: telemetry
                ) {
                    return
                }

                if publishProviderAdmissionFailureIfNeeded(
                    error,
                    telemetry: telemetry
                ) {
                    return
                }

                if publishTerminalObservationRejectionIfNeeded(
                    error,
                    scanId: resolvedClientScanId,
                    telemetry: telemetry
                ) {
                    return
                }

                if let apiError = error as? MerianError, apiError == .decodingFailed {
                    AppTelemetry.trackError("APIDecodingFailure")
                    // No refund: the scan is already durably in the offline queue and will be
                    // retried by the background upload path. Refunding here would give the user
                    // a free extra scan against a quota that was already consumed.
                    if stillOwnsAttempt {
                        HapticManager.shared.triggerErrorThump()
                        self.speciesData = makeErrorSpeciesData(
                            title: "Analysis Failed",
                            subtitle: "Data Unreadable",
                            reasoning: "The AI failed to understand the image or produced an unreadable schema.",
                            telemetry: telemetry
                        )
                    }
                    return
                }

                // Remaining failures are not assumed to be connectivity loss. A
                // queue-backed transport failure already returned through the dedicated
                // queued presentation above; server and client-contract failures keep
                // distinct copy while the durable background owner continues recovery.
                let isConnectivityFailure = Self.isConnectivityFailure(error)
                AppTelemetry.trackError(
                    isConnectivityFailure
                        ? "InferenceNetworkFailure"
                        : "InferenceServiceFailure"
                )
                CircuitBreakerManager.shared.recordFailure()
                MerianLog.general.debug("Inference failure: \(error.localizedDescription, privacy: .private)")
                if stillOwnsAttempt {
                    HapticManager.shared.triggerErrorThump()
                    self.speciesData = makeErrorSpeciesData(
                        title: isConnectivityFailure
                            ? "Network timeout"
                            : "Analysis delayed",
                        subtitle: ownedScanId == nil
                            ? "Please try again"
                            : "Scan saved",
                        reasoning: isConnectivityFailure
                            ? Self.networkTimeoutRecoveryReason
                            : (ownedScanId == nil
                                ? Self.serviceFailureReason
                                : Self.savedServiceFailureReason),
                        telemetry: telemetry
                    )
                }
            }
        }
    }

    // MARK: - Describe Inference Pipeline

    func analyzeNonVisual(
        scanId: String?,
        foregroundInferenceGeneration: UUID? = nil,
        audioFilePaths: [String]? = nil,
        videoFilePaths: [String]? = nil,
        observationContexts: [ObservationContext] = [],
        mediaTimeline: [CaptureSubmissionMediaItem]? = nil,
        telemetry: CaptureTelemetry,
        modelContext: ModelContext?,
        targetEradicationScanId: String? = nil,
        userPerceivedStart: CFAbsoluteTime? = nil
    ) {
        guard !writeCoordinator.isAuthTransitionFenceActive else {
            if let scanId, let foregroundInferenceGeneration {
                OfflineQueueManager.shared.releaseDeferredLiveUpload(
                    scanId: scanId,
                    foregroundInferenceGeneration:
                        foregroundInferenceGeneration,
                    reason: "auth_transition_active"
                )
                OfflineQueueManager.shared.retireForegroundInference(
                    scanId: scanId,
                    generation: foregroundInferenceGeneration,
                    resumeBackground: true,
                    reason: "auth_transition_active"
                )
            }
            return
        }
        let filteredAudioFilePaths = (audioFilePaths ?? []).filter { !$0.isEmpty }
        let filteredVideoFilePaths = (videoFilePaths ?? []).filter { !$0.isEmpty }
        let filteredObservationContexts = observationContexts.filter { !$0.isEmpty }
        let resolvedMediaTimeline = mediaTimeline ?? CaptureSubmissionMediaItem.defaultTimeline(
            imageCount: 0,
            observationContexts: filteredObservationContexts,
            audioFilePaths: filteredAudioFilePaths,
            videoFilePaths: filteredVideoFilePaths
        )
        let submissionProjection = resolvedMediaTimeline.submissionMediaProjection
        let ownerMediaTimeline = mediaTimeline == nil
            ? nil
            : submissionProjection.ownerMediaTimeline

        guard !resolvedMediaTimeline.isEmpty else {
            if let scanId, let foregroundInferenceGeneration {
                OfflineQueueManager.shared.retireForegroundInference(
                    scanId: scanId,
                    generation: foregroundInferenceGeneration,
                    resumeBackground: true,
                    reason: "live_nonvisual_payload_empty"
                )
            }
            return
        }
        if let scanId {
            guard let foregroundInferenceGeneration else {
                MerianLog.general.debug(
                    "analyzeNonVisual: rejected missing foreground owner scanId=\(scanId, privacy: .public)"
                )
                return
            }
            guard !isDuplicateActiveForegroundAttempt(
                scanId: scanId,
                generation: foregroundInferenceGeneration
            ) else {
                MerianLog.general.debug(
                    "analyzeNonVisual: ignored duplicate foreground generation scanId=\(scanId, privacy: .public)"
                )
                return
            }
            guard OfflineQueueManager.shared.claimForegroundInferenceStart(
                        scanId: scanId,
                        generation: foregroundInferenceGeneration
                  ) else {
                MerianLog.general.debug(
                    "analyzeNonVisual: rejected stale, used, or retiring foreground owner scanId=\(scanId, privacy: .public)"
                )
                return
            }
        } else if foregroundInferenceGeneration != nil {
            MerianLog.general.debug(
                "analyzeNonVisual: rejected foreground owner without scanId"
            )
            return
        }

        self.inferenceTask?.cancel()
        self.hydrationCoordinator.cancelAllTasks()
        self.cancelLocalVisualAnalysis()

        let attemptGeneration =
            foregroundInferenceGeneration ?? UUID()
        self.prepareForNewScan(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            modality: .nonVisual
        )
        self.scanningPhaseText = submissionProjection.audioFilePaths.isEmpty
            ? "Identifying describe"
            : "Listening"

        self.activeScanId = scanId
        self.activeLiveInferenceAttemptGeneration = attemptGeneration
        self.activeForegroundInferenceGeneration =
            foregroundInferenceGeneration
        self.activePresentationOwner = AnalysisPresentationOwner(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            modality: .nonVisual
        )
        self.preparedPresentationOwner = nil
        self.activeLatitude = telemetry.gpsLatitude
        self.activeLongitude = telemetry.gpsLongitude
        self.activeElevation = telemetry.gpsElevation
        self.activeLocationName = telemetry.locationName
        self.activeWeatherCondition = telemetry.weatherCondition
        self.activeTemperatureF = telemetry.weatherTemperatureF
        self.activeMedia = ActiveScanMedia(items: mediaItems(from: resolvedMediaTimeline, liveImageDatas: nil, persistedImagePaths: nil))

        let ownedScanId = scanId
        let ownedForegroundInferenceGeneration =
            foregroundInferenceGeneration
        let resolvedClientScanId = scanId ?? UUID().uuidString.lowercased()
        let shouldFlushQueuedScan =
            ownedForegroundInferenceGeneration != nil
        if let userPerceivedStart {
            self.pendingFirstRenderMetric = (
                scanId: resolvedClientScanId,
                startedAt: userPerceivedStart
            )
        }

        self.inferenceTask = Task { [weak self] in
            guard let self else { return }
            let pipelineStart = CFAbsoluteTimeGetCurrent()

            defer {
                if self.isLocalLiveInferenceAttemptCurrent(
                    scanId: ownedScanId,
                    attemptGeneration: attemptGeneration
                ) {
                    self.isProcessing = false
                    self.activeScanId = nil
                    self.activeLiveInferenceAttemptGeneration = nil
                    self.activeForegroundInferenceGeneration = nil
                    if self.activePresentationOwner?.attemptGeneration
                        == attemptGeneration {
                        self.activePresentationOwner = nil
                    }
                    self.cancelLocalVisualAnalysis()
                }
            }

            do {
                try self.checkLiveInferenceAttempt(
                    scanId: ownedScanId,
                    attemptGeneration: attemptGeneration,
                    foregroundInferenceGeneration:
                        ownedForegroundInferenceGeneration
                )
                if CircuitBreakerManager.shared.isCircuitTripped {
                    throw URLError(.notConnectedToInternet)
                }

                let observationContextsJSON = observationContextJSONStrings(
                    from: submissionProjection.observationContexts
                )
                try self.checkLiveInferenceAttempt(
                    scanId: ownedScanId,
                    attemptGeneration: attemptGeneration,
                    foregroundInferenceGeneration:
                        ownedForegroundInferenceGeneration
                )
                let resultData = try await MerianNetworkClient.shared.identifyMultiModal(
                    audioFilePaths: submissionProjection.audioFilePaths,
                    audioMediaItems: submissionProjection.audioMediaItems,
                    ownerMediaTimeline: ownerMediaTimeline,
                    observationContextsJSON: observationContextsJSON,
                    telemetry: telemetry,
                    clientScanId: scanId,
                    durableQueueOwnsRecovery:
                        ownedForegroundInferenceGeneration != nil
                )
                try self.checkLiveInferenceAttempt(
                    scanId: ownedScanId,
                    attemptGeneration: attemptGeneration,
                    foregroundInferenceGeneration:
                        ownedForegroundInferenceGeneration
                )
                let responseReceivedAt = CFAbsoluteTimeGetCurrent()
                let postFlightStart = CFAbsoluteTimeGetCurrent()

                let parseResult = try await InferenceProcessingActor.shared.parseAndSave(
                    resultData: resultData,
                    telemetry: telemetry,
                    modelContext: modelContext,
                    compressedDatas: [],
                    displayDatas: [],
                    skipImageRequirement: true,
                    observationContextsJSON: observationContextsJSON,
                    audioFilePaths: submissionProjection.audioFilePaths.isEmpty
                        ? nil
                        : submissionProjection.audioFilePaths,
                    videoFilePaths: submissionProjection.videoFilePaths.isEmpty
                        ? nil
                        : submissionProjection.videoFilePaths,
                    mediaTimeline: resolvedMediaTimeline,
                    persistenceFence: ownedScanId.flatMap { scanId in
                        ownedForegroundInferenceGeneration.map { generation in
                            LiveInferencePersistenceFence(
                                scanId: scanId,
                                generation: generation
                            )
                        }
                    }
                )
                try self.checkLiveInferenceAttempt(
                    scanId: ownedScanId,
                    attemptGeneration: attemptGeneration,
                    foregroundInferenceGeneration:
                        ownedForegroundInferenceGeneration
                )
                guard parseResult.didCompletePersistence else {
                    self.retireForegroundInferenceIfCurrent(
                        scanId: ownedScanId,
                        attemptGeneration: attemptGeneration,
                        foregroundInferenceGeneration:
                            ownedForegroundInferenceGeneration,
                        resumeBackground: true,
                        reason: "live_nonvisual_persistence_rejected"
                    )
                    return
                }
                let finalMappedData = parseResult.mappedData
                let isNewDisc = parseResult.isNewDiscovery

                if var mappedData = finalMappedData {
                    applyNewDiscoveryIfNeeded(isNewDisc, to: &mappedData)
                    transferReplacementMetadataIfNeeded(
                        from: targetEradicationScanId,
                        to: mappedData.scanId,
                        modelContext: modelContext
                    )

                    CircuitBreakerManager.shared.recordSuccess()
                    AppTelemetry.trackScan(
                        isPro: RevenueCatManager.shared.isProActive,
                        isSubscribed: RevenueCatManager.shared.isSubscribed,
                        inferenceTier: mappedData.inferenceTier,
                        planUsed: parseResult.planUsed
                    )

                    let didCommitResult = self.commitSuccessfulResult(
                        for: ownedScanId,
                        attemptGeneration: attemptGeneration,
                        foregroundInferenceGeneration:
                            ownedForegroundInferenceGeneration,
                        speciesData: mappedData
                    )
                    let stateCommittedAt = CFAbsoluteTimeGetCurrent()
                    MerianLog.general.debug(
                        "[⏱ BENCH] Response to first-result state: \(String(format: "%.3f", stateCommittedAt - responseReceivedAt), privacy: .public)s"
                    )
                    MerianLog.general.debug(
                        "[⏱ BENCH] Post-flight (parse+save+state): \(String(format: "%.3f", stateCommittedAt - postFlightStart), privacy: .public)s"
                    )
                    MerianLog.general.debug(
                        "[⏱ BENCH] Total pipeline: \(String(format: "%.3f", stateCommittedAt - pipelineStart), privacy: .public)s"
                    )
                    var didFinalizeQueue = true
                    if didCommitResult, shouldFlushQueuedScan {
                        didFinalizeQueue =
                            await self.completeQueuedLiveInferenceIfNeeded(
                                scanId: ownedScanId,
                                attemptGeneration: attemptGeneration,
                                foregroundInferenceGeneration:
                                    ownedForegroundInferenceGeneration,
                                mediaPathsToKeep:
                                    (mappedData.audioFilePaths ?? []) +
                                    (mappedData.videoFilePaths ?? [])
                            )
                    }
                    let stillOwnsPresentation =
                        self.isLocalLiveInferenceAttemptCurrent(
                            scanId: ownedScanId,
                            attemptGeneration: attemptGeneration
                        )
                    if didCommitResult,
                       didFinalizeQueue,
                       stillOwnsPresentation {
                        Task { [mappedData] in
                            guard let scanId = mappedData.scanId else { return }
                            await AppDIContainer.shared.scanMilestoneCoordinator.processCompletedScan(
                                scanId: scanId,
                                speciesData: mappedData,
                                modelContainer: modelContext?.container
                            )
                        }
                        self.sendInferenceCompleteNotificationIfEnabled(
                            for: mappedData
                        )
                        schedulePostInferenceHydrationIfNeeded(
                            for: mappedData,
                            modelContext: modelContext,
                            referencePolicy: .none
                        )
                    }
                }
            } catch {
                let stillOwnsAttempt =
                    self.isLiveInferenceAttemptCurrent(
                        scanId: ownedScanId,
                        attemptGeneration: attemptGeneration,
                        foregroundInferenceGeneration:
                            ownedForegroundInferenceGeneration
                    )
                if Task.isCancelled {
                    if stillOwnsAttempt {
                        self.releaseQueueBackedLiveInferenceForRecovery(
                            scanId: ownedScanId,
                            attemptGeneration: attemptGeneration,
                            foregroundInferenceGeneration:
                                ownedForegroundInferenceGeneration,
                            reason: "live_nonvisual_cancelled"
                        )
                    }
                    return
                }

                // Apply the same task-cancellation versus ownership-retirement
                // distinction used by the visual pipeline.
                if error is CancellationError {
                    if publishQueuedRetiredOwnershipHandoffIfNeeded(
                        scanId: ownedScanId,
                        attemptGeneration: attemptGeneration,
                        foregroundInferenceGeneration:
                            ownedForegroundInferenceGeneration
                    ) {
                        return
                    }
                    if stillOwnsAttempt {
                        self.releaseQueueBackedLiveInferenceForRecovery(
                            scanId: ownedScanId,
                            attemptGeneration: attemptGeneration,
                            foregroundInferenceGeneration:
                                ownedForegroundInferenceGeneration,
                            reason: "live_nonvisual_cancelled"
                        )
                    }
                    return
                }

                if (error as? URLError)?.code == .cancelled {
                    _ = publishQueuedRecoveryHandoffIfNeeded(
                        scanId: ownedScanId,
                        attemptGeneration: attemptGeneration,
                        foregroundInferenceGeneration:
                            ownedForegroundInferenceGeneration,
                        telemetryEvent:
                            "InferenceQueuedForTransportCancellation",
                        reason: "live_nonvisual_transport_cancelled"
                    )
                    return
                }

                if publishQueuedConnectivityFailureIfNeeded(
                    error,
                    scanId: ownedScanId,
                    attemptGeneration: attemptGeneration,
                    foregroundInferenceGeneration:
                        ownedForegroundInferenceGeneration
                ) {
                    return
                }

                guard stillOwnsAttempt else { return }
                self.releaseQueueBackedLiveInferenceForRecovery(
                    scanId: ownedScanId,
                    attemptGeneration: attemptGeneration,
                    foregroundInferenceGeneration:
                        ownedForegroundInferenceGeneration,
                    reason: "live_nonvisual_failed"
                )
                if ownedScanId != nil {
                    self.recoverablePresentationScanId = resolvedClientScanId
                }

                if publishRecoverableInferenceConflictIfNeeded(
                    error,
                    scanId: resolvedClientScanId,
                    telemetry: telemetry
                ) {
                    return
                }
                if publishConsentRequiredIfNeeded(
                    error,
                    telemetry: telemetry
                ) {
                    return
                }
                if publishProviderAdmissionFailureIfNeeded(
                    error,
                    telemetry: telemetry
                ) {
                    return
                }
                if publishTerminalObservationRejectionIfNeeded(
                    error,
                    scanId: resolvedClientScanId,
                    telemetry: telemetry
                ) {
                    return
                }

                let isConnectivityFailure = Self.isConnectivityFailure(error)
                AppTelemetry.trackError(
                    isConnectivityFailure
                        ? "InferenceNetworkFailure"
                        : (filteredAudioFilePaths.isEmpty
                            ? "DescribeInferenceFailure"
                            : "InferenceServiceFailure")
                )
                CircuitBreakerManager.shared.recordFailure()
                MerianLog.general.debug("Non-visual inference failure: \(error.localizedDescription, privacy: .private)")
                if stillOwnsAttempt {
                    HapticManager.shared.triggerErrorThump()
                    self.speciesData = makeErrorSpeciesData(
                        title: isConnectivityFailure
                            ? "Network timeout"
                            : "Analysis delayed",
                        subtitle: ownedScanId == nil
                            ? "Please try again"
                            : "Scan saved",
                        reasoning: isConnectivityFailure
                            ? Self.networkTimeoutRecoveryReason
                            : (ownedScanId == nil
                                ? Self.serviceFailureReason
                                : Self.savedServiceFailureReason),
                        telemetry: telemetry
                    )
                }
            }
        }
    }

    // MARK: - Error State Factory

    private static let networkTimeoutRecoveryReason =
        "Naturebook couldn’t reach the analysis service. Check your connection and try again."

    private static let serviceFailureReason =
        "Naturebook couldn’t complete this analysis because the service returned an " +
        "unexpected response. Please try again."

    private static let savedServiceFailureReason =
        "Naturebook saved this scan and will retry it automatically. You can leave this " +
        "screen and check Scans later."

    private static let consentRequiredRecoveryReason =
        "Naturebook saved this scan. Complete the required age, Terms, and Google Gemini " +
        "consent step, and Naturebook will resume it automatically when eligible. " +
        "If it stays paused, you can retry it from Scans."

    private static let savedScanRecoveryReason =
        "Your scan reached Naturebook safely. We’re restoring its saved result now, " +
        "and it will appear here or in Scans automatically."

    private static let proRequiredRecoveryReason =
        "Naturebook saved this scan. This capture requires Pro access. " +
        "Upgrade, then retry it from Scans."

    private static let rateLimitRecoveryReason =
        "Naturebook saved this scan and will retry automatically after the server’s " +
        "short safety pause. You can leave this screen and check Scans later."

    private static let observationRejectedReason =
        "Naturebook couldn’t process this observation. Try a different photo or " +
        "recording with the subject clearly visible."

    private func clearQueuedVisualPresentationContext() {
        queuedVisualPresentationScanId = nil
        queuedPresentationCarriesLiveMedia = false
        queuedPresentationScanningPhrases = []
    }

    /// Moves an already-durable, exactly owned scan out of the live-result state
    /// and into the Insight queue presentation. The queue owns all retry work
    /// from this point; no synthetic `SpeciesData` or error haptic is
    /// appropriate.
    @discardableResult
    func transitionToQueuedPresentation(
        scanId: String,
        source: QueuedPresentationSource
    ) -> Bool {
        let normalizedScanId = scanId
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedScanId.isEmpty else {
            clearQueuedVisualPresentationContext()
            return false
        }

        let owner: AnalysisPresentationOwner
        let isPreparedHandoff: Bool
        switch source {
        case .prepared(let attemptGeneration):
            guard let preparedPresentationOwner,
                  preparedPresentationOwner.matches(
                      scanId: normalizedScanId,
                      attemptGeneration: attemptGeneration
                  ) else {
                clearQueuedVisualPresentationContext()
                return false
            }
            owner = preparedPresentationOwner
            isPreparedHandoff = true
        case .active(let attemptGeneration):
            guard let activePresentationOwner,
                  activePresentationOwner.matches(
                      scanId: normalizedScanId,
                      attemptGeneration: attemptGeneration
                  ),
                  isLocalLiveInferenceAttemptCurrent(
                      scanId: normalizedScanId,
                      attemptGeneration: attemptGeneration
                  ) else {
                clearQueuedVisualPresentationContext()
                return false
            }
            owner = activePresentationOwner
            isPreparedHandoff = false
        }

        clearQueuedVisualPresentationContext()
        if owner.modality == .visual {
            queuedVisualPresentationScanId = normalizedScanId
            queuedPresentationCarriesLiveMedia =
                !isPreparedHandoff && activeMedia.totalItems > 0
            let phraseDeck = isPreparedHandoff
                ? ScanningPhraseCoordinator.genericPhrases
                : localAnalysisCoordinator.handoffPhraseDeck
            queuedPresentationScanningPhrases = phraseDeck
            if let firstPhrase = phraseDeck.first {
                scanningPhaseText = firstPhrase
            }
        }

        preparedPresentationOwner = nil
        activePresentationOwner = nil
        recoverablePresentationScanId = normalizedScanId
        queuedPresentationScanId = normalizedScanId
        pendingFirstRenderMetric = nil
        cancelLocalVisualAnalysis(resetPhraseCoordinator: false)
        speciesData = nil
        isProcessing = false
        return true
    }

    /// Returns visual copy only for the exact queued presentation that inherited
    /// a prepared or active visual scan. Values remain process-local and
    /// ephemeral.
    func liveQueueHandoffScanningPhrases(for scanId: String) -> [String] {
        guard queuedVisualPresentationScanId?
            .caseInsensitiveCompare(scanId) == .orderedSame else {
            return []
        }
        return queuedPresentationScanningPhrases
    }

    func hasLiveVisualQueueHandoff(for scanId: String) -> Bool {
        queuedVisualPresentationScanId?
            .caseInsensitiveCompare(scanId) == .orderedSame
    }

    func hasLiveQueueHandoffMedia(for scanId: String) -> Bool {
        queuedPresentationCarriesLiveMedia &&
            hasLiveVisualQueueHandoff(for: scanId)
    }

    private static func isConnectivityFailure(_ error: Error) -> Bool {
        if (error as? MerianError) == .networkTimeout {
            return true
        }
        return ScanConnectivityFailurePolicy.isDurableRecoveryFailure(error)
    }

    @discardableResult
    private func publishQueuedConnectivityFailureIfNeeded(
        _ error: Error,
        scanId: String?,
        attemptGeneration: UUID,
        foregroundInferenceGeneration: UUID?
    ) -> Bool {
        guard Self.isConnectivityFailure(error) else {
            return false
        }

        // Physical captures are already durable before this request starts.
        // Connectivity loss therefore changes presentation and ownership, not
        // scan success: background recovery continues from the same scan ID.
        return publishQueuedRecoveryHandoffIfNeeded(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundInferenceGeneration: foregroundInferenceGeneration,
            telemetryEvent: "InferenceQueuedForConnectivity",
            reason: "live_connectivity_handoff"
        )
    }

    private func publishQueuedRetiredOwnershipHandoffIfNeeded(
        scanId: String?,
        attemptGeneration: UUID,
        foregroundInferenceGeneration: UUID?
    ) -> Bool {
        guard let scanId, let foregroundInferenceGeneration,
              !OfflineQueueManager.shared.isForegroundInferenceAttemptCurrent(
                  scanId: scanId,
                  generation: foregroundInferenceGeneration
              ) else {
            return false
        }
        return publishQueuedRecoveryHandoffIfNeeded(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundInferenceGeneration: foregroundInferenceGeneration,
            telemetryEvent: "InferenceQueuedAfterOwnershipRetirement",
            reason: "live_ownership_retired"
        )
    }

    private func publishQueuedRecoveryHandoffIfNeeded(
        scanId: String?,
        attemptGeneration: UUID,
        foregroundInferenceGeneration: UUID?,
        telemetryEvent: String,
        reason: String
    ) -> Bool {
        guard let scanId,
              foregroundInferenceGeneration != nil,
              isLocalLiveInferenceAttemptCurrent(
                  scanId: scanId,
                  attemptGeneration: attemptGeneration
              ) else {
            return false
        }

        releaseQueueBackedLiveInferenceForRecovery(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundInferenceGeneration: foregroundInferenceGeneration,
            reason: reason
        )
        AppTelemetry.trackError(telemetryEvent)
        MerianLog.general.debug(
            "Live inference handed presentation to durable queue state."
        )
        transitionToQueuedPresentation(
            scanId: scanId,
            source: .active(attemptGeneration: attemptGeneration)
        )
        return true
    }

    private func releaseQueueBackedLiveInferenceForRecovery(
        scanId: String?,
        attemptGeneration: UUID,
        foregroundInferenceGeneration: UUID?,
        reason: String
    ) {
        guard let scanId, let foregroundInferenceGeneration else { return }
        OfflineQueueManager.shared.releaseDeferredLiveUpload(
            scanId: scanId,
            foregroundInferenceGeneration: foregroundInferenceGeneration,
            reason: reason
        )
        retireForegroundInferenceIfCurrent(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundInferenceGeneration: foregroundInferenceGeneration,
            resumeBackground: true,
            reason: reason
        )
    }

    private static func isTerminalObservationRejection(_ error: Error) -> Bool {
        guard case let MerianError.httpError(statusCode, _) = error,
              statusCode == 400 else {
            return false
        }
        return MerianNetworkClient.stableEdgeErrorCode(from: error)
            == "observation_rejected"
    }

    @discardableResult
    private func publishConsentRequiredIfNeeded(
        _ error: Error,
        telemetry: CaptureTelemetry
    ) -> Bool {
        guard (error as? MerianError) == .aiConsentRequired else {
            return false
        }

        // Missing or rejected consent is a policy transition, not evidence of
        // network instability. In particular, it must not advance the shared
        // circuit breaker and strand the user after fresh approval succeeds.
        AppTelemetry.trackError("InferenceConsentRequired")
        MerianLog.general.debug(
            "Inference paused until required consent is authoritative; the queued scan remains saved."
        )
        HapticManager.shared.triggerErrorThump()
        speciesData = makeErrorSpeciesData(
            title: "Approval needed",
            subtitle: "Scan saved",
            reasoning: Self.consentRequiredRecoveryReason,
            telemetry: telemetry
        )
        return true
    }

    @discardableResult
    private func publishProviderAdmissionFailureIfNeeded(
        _ error: Error,
        telemetry: CaptureTelemetry
    ) -> Bool {
        guard let merianError = error as? MerianError,
              case let .httpError(statusCode, _) = merianError,
              let code = MerianNetworkClient.stableEdgeErrorCode(from: error) else {
            return false
        }

        let title: String
        let reasoning: String
        let telemetryEvent: String
        switch (statusCode, code) {
        case (402, "pro_required"):
            title = "Upgrade needed"
            reasoning = Self.proRequiredRecoveryReason
            telemetryEvent = "InferenceProRequired"
        case (429, "ai_quota_daily_exceeded"):
            // The durable queue still owns retry timing, but quota exhaustion
            // is an upgrade boundary rather than an Insight result. Request the
            // root paywall without publishing a synthetic SpeciesData view.
            AppTelemetry.trackError("InferenceDailyQuotaExceeded")
            MerianLog.general.debug(
                "Inference daily quota exhausted; requesting the paywall while the queued scan remains saved."
            )
            requestPaywall()
            return true
        case (429, "ai_user_rate_limit_exceeded"),
             (429, "ai_ip_rate_limit_exceeded"):
            title = "Retrying shortly"
            reasoning = Self.rateLimitRecoveryReason
            telemetryEvent = "InferenceRateLimited"
        default:
            return false
        }

        // These are authenticated provider-admission decisions, not evidence
        // that the device network is unhealthy. The durable queue owns the
        // saved scan: 402 becomes explicit attention after entitlement refresh,
        // while temporary 429s honor the server retry delay in the background.
        AppTelemetry.trackError(telemetryEvent)
        MerianLog.general.debug(
            "Inference paused by provider admission policy code=\(code, privacy: .public); the queued scan remains saved."
        )
        HapticManager.shared.triggerErrorThump()
        speciesData = makeErrorSpeciesData(
            title: title,
            subtitle: "Scan saved",
            reasoning: reasoning,
            telemetry: telemetry
        )
        return true
    }

    @discardableResult
    private func publishTerminalObservationRejectionIfNeeded(
        _ error: Error,
        scanId: String,
        telemetry: CaptureTelemetry
    ) -> Bool {
        guard Self.isTerminalObservationRejection(error) else {
            return false
        }

        // This is a handler-owned moderation/policy outcome. Retrying the same
        // retained media cannot succeed, and it says nothing about the device's
        // network health. Mirror the background disposition immediately; if
        // the durable transition fails, the normal background owner remains
        // eligible to retry and apply the same terminal response safely.
        AppTelemetry.trackError("InferenceObservationRejected")
        MerianLog.general.debug(
            "Inference observation was rejected by policy; a different capture is required."
        )
        _ = OfflineQueueManager.shared.softDeleteQueuedScan(
            scanId: scanId,
            reason: Self.observationRejectedReason,
            errorCode: "observation_rejected",
            httpStatus: 400,
            needsAttention: false
        )
        HapticManager.shared.triggerErrorThump()
        speciesData = makeErrorSpeciesData(
            title: "Try another capture",
            subtitle: "Scan not processed",
            reasoning: Self.observationRejectedReason,
            telemetry: telemetry
        )
        return true
    }

    @discardableResult
    private func publishRecoverableInferenceConflictIfNeeded(
        _ error: Error,
        scanId: String,
        telemetry: CaptureTelemetry
    ) -> Bool {
        guard MerianNetworkClient.isRecoverableInferenceConflict(error) else {
            return false
        }
        AppTelemetry.trackError("InferenceCompletionRecovery")
        MerianLog.general.debug(
            "Inference response was ambiguous after server acceptance; restoring scanId=\(scanId, privacy: .public)"
        )
        speciesData = makeErrorSpeciesData(
            title: "Restoring scan",
            subtitle: "Safely saved",
            reasoning: Self.savedScanRecoveryReason,
            telemetry: telemetry
        )
        return true
    }

    /// Builds an error-placeholder `SpeciesData` for failures that cannot use the
    /// durable queued presentation. Every branch shares the same field layout.
    private func makeErrorSpeciesData(
        title: String,
        subtitle: String,
        reasoning: String,
        telemetry: CaptureTelemetry
    ) -> SpeciesData {
        SpeciesData(
            scanId: nil,
            presentationRole: .inferenceError,
            commonName: title,
            scientificName: subtitle,
            insightData: InsightData(aiReasoning: reasoning, hazardType: "none"),
            confidenceScore: 0,
            blurScore: nil,
            similarSpecies: nil,
            wikipediaUrl: nil,
            wikipediaOverview: nil,
            referenceImageUrl: nil,
            isBiological: false,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "unknown",
            taxonomy: nil,
            locationName: telemetry.locationName,
            weatherCondition: telemetry.weatherCondition,
            weatherTemperatureF: telemetry.weatherTemperatureF,
            gpsElevation: telemetry.gpsElevation,
            gpsLatitude: telemetry.gpsLatitude,
            gpsLongitude: telemetry.gpsLongitude,
            colors: nil,
            groupTags: nil,
            iucnRedListStatus: nil,
            zoomFactor: telemetry.zoomFactor.map { Double($0) }
        )
    }

    // MARK: - Wikipedia Background Hydration

    /// Fetches and patches the Wikipedia extract and reference image for a species after inference completes.
    /// Runs independently to avoid adding latency to the inference round-trip.
    /// Only marks the species as attempted after a *successful* fetch, so transient failures are retryable.
    private func fetchWikipediaAndHydrate(
        for species: String,
        scanId: String,
        presentationGeneration: UInt64,
        reviewActionGeneration: UInt64?,
        modelContext: ModelContext?
    ) async {
        guard !species.isEmpty,
              species.lowercased() != "taxonomy unavailable",
              species.lowercased() != "unknown subject" else { return }
        guard hydrationCoordinator.canHydrateWikipedia(for: species) else {
            return
        }

        do {
            guard let reference = try await speciesReferenceService
                .fetchWikipediaReference(for: species),
                let descriptionText = reference.overview else {
                return
            }
            let webUrl = reference.pageURL
            let imageUrl = ExternalReferenceImagePolicy.sanitizedURL(
                reference.imageURL
            )

            guard isLiveSpeciesPresentation(
                scanId: scanId,
                scientificName: species,
                presentationGeneration: presentationGeneration,
                reviewActionGeneration: reviewActionGeneration
            ), var updated = speciesData else {
                return
            }

            // Mark as attempted only after the fetched species still owns this exact
            // presentation. A stale successful request must not suppress hydration when the
            // user later returns to the same species under a new generation.
            hydrationCoordinator.recordWikipediaHydrationSuccess(for: species)

            MerianLog.general.debug("Wikipedia hydration returned imageUrl: \(imageUrl ?? "nil", privacy: .private)")
            updated.wikipediaOverview = descriptionText
            updated.wikipediaUrl = webUrl
            if let img = imageUrl, !img.isEmpty {
                var currentUrls = Self.normalizedReferenceURLs(from: updated.referenceImageUrl)
                if !currentUrls.contains(img) {
                    currentUrls.insert(img, at: 0)
                }
                let capped = Array(currentUrls.prefix(5))
                updated.referenceImageUrl = capped.joined(separator: ",")
                activeMedia.referenceState = .loaded(capped)
                MerianLog.general.debug("Wiki hydration applied. New state: \(capped, privacy: .public)")
            }
            speciesData = updated
            let safeImageUrlToPersist = updated.referenceImageUrl

            if let context = modelContext {
                let container = context.container
                executeSpeciesMetadataWrite(
                    scanId: scanId,
                    scientificName: species,
                    presentationGeneration: presentationGeneration,
                    reviewActionGeneration: reviewActionGeneration
                ) { [safeImageUrlToPersist] in
                    let dbActor = BackgroundDatabaseActor(modelContainer: container)
                    await dbActor.updateScanWithWikipedia(
                        scanId: scanId,
                        extract: descriptionText,
                        url: webUrl,
                        imageUrl: safeImageUrlToPersist,
                        expectedScientificName: species
                    )
                }
            }
        } catch {
            MerianLog.general.debug("Wikipedia hydration skipped: \(error, privacy: .private)")
        }
    }

    // MARK: - GBIF Background Hydration

    /// Fetches high-quality field observations from GBIF (e.g. iNaturalist) once the Taxon Key is known.
    /// This acts as a robust supplement/fallback to Wikipedia imagery.
    private func fetchGBIFImagesAndHydrate(
        for taxonKey: Int,
        scanId: String,
        scientificName: String,
        presentationGeneration: UInt64,
        reviewActionGeneration: UInt64?,
        modelContext: ModelContext?
    ) async {
        do {
            let fetchedURLs = try await speciesReferenceService
                .fetchGBIFImageURLs(taxonKey: taxonKey)
            let newUrls = fetchedURLs.compactMap {
                ExternalReferenceImagePolicy.sanitizedURL($0)
            }

            MerianLog.general.debug(
                "GBIF hydration returned \(newUrls.count, privacy: .public) usable URLs: \(newUrls, privacy: .private)"
            )
            guard !newUrls.isEmpty else { return }

            // Back on @MainActor (InferenceEngine is @MainActor) — direct access, no hop needed.
            var persistUrls: String?
            if var updated = self.speciesData,
               isLiveSpeciesPresentation(
                   scanId: scanId,
                   scientificName: scientificName,
                   presentationGeneration: presentationGeneration,
                   reviewActionGeneration: reviewActionGeneration
               ) {
                var currentUrls = Self.normalizedReferenceURLs(from: updated.referenceImageUrl)

                for urlStr in newUrls where !currentUrls.contains(urlStr) {
                    currentUrls.append(urlStr)
                }

                // Cap at 5 URLs to prevent unbounded referenceImageUrl string growth across sessions.
                let capped = Array(currentUrls.prefix(5))
                updated.referenceImageUrl = capped.joined(separator: ",")
                persistUrls = updated.referenceImageUrl
                self.activeMedia.referenceState = .loaded(capped)
                // Single full-value replacement — see fetchAndApplyEnrichment comment.
                self.speciesData = updated
            }

            if let context = modelContext, let finalUrls = persistUrls {
                let container = context.container
                executeSpeciesMetadataWrite(
                    scanId: scanId,
                    scientificName: scientificName,
                    presentationGeneration: presentationGeneration,
                    reviewActionGeneration: reviewActionGeneration
                ) {
                    let dbActor = BackgroundDatabaseActor(modelContainer: container)
                    await dbActor.updateScanWithWikipedia(
                        scanId: scanId,
                        extract: nil,
                        url: nil,
                        imageUrl: finalUrls,
                        expectedScientificName: scientificName
                    )
                }
            }
        } catch {
            // Silently fail on network/timeout
            MerianLog.general.debug("GBIF image hydration skipped: \(error, privacy: .private)")
        }
    }

    // MARK: - Species Enrichment

    /// Fires the "enrichment" and "lookalikes" scopes of `enrich-scan` concurrently via a
    /// task group. Each scope applies its fields to `speciesData` as soon as its network call
    /// resolves — habitat description and taxonomy appear independently of similar species cards.
    ///
    /// `isEnrichmentLoading` gates the habitat/distribution skeleton (enrichment scope).
    /// `isLookalikesLoading` gates the similar species gallery skeleton (lookalikes scope).
    ///
    /// Called automatically after every successful biological scan and when reloading a historical
    /// record that is missing enrichment data. `needsMetadata` / `needsLookalikes` allow callers
    /// to skip whichever scope is already fully populated locally.
    func fetchAndApplyEnrichment(
        modelContext: ModelContext?,
        needsMetadata: Bool = true,
        needsLookalikes: Bool = true,
        allowLookalikesRetry: Bool = true,
        reviewActionGeneration: UInt64? = nil
    ) async {
        guard let data = speciesData,
              let scanId = data.scanId,
              data.isBiological,
              !data.scientificName.isEmpty,
              data.scientificName.lowercased() != "taxonomy unavailable" else { return }

        guard needsMetadata || needsLookalikes else { return }
        guard hydrationCoordinator.canAttemptEnrichment() else { return }

        if needsMetadata { isEnrichmentLoading = true }
        if needsLookalikes { isLookalikesLoading = true }

        let capturedScanId = scanId
        let capturedScientificName = data.scientificName
        let capturedConfidence = data.confidenceScore
        let capturedTier = data.inferenceTier ?? "flash"
        let capturedPresentationGeneration = writeCoordinator.generation

        await withTaskGroup(of: Void.self) { group in
            if needsMetadata {
                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    defer {
                        if self.isLiveSpeciesPresentation(
                            scanId: capturedScanId,
                            scientificName: capturedScientificName,
                            presentationGeneration: capturedPresentationGeneration,
                            reviewActionGeneration: reviewActionGeneration
                        ) {
                            self.isEnrichmentLoading = false
                        }
                    }
                    do {
                        let response = try await MerianNetworkClient.shared.fetchEnrichment(
                            scanId: capturedScanId,
                            scientificName: capturedScientificName,
                            confidenceScore: capturedConfidence,
                            inferenceTier: capturedTier,
                            scope: "enrichment"
                        )
                        guard let enrichData = response.data else { return }

                        // Collect all enrichment mutations into a local copy, then assign once.
                        // Individual optional-chain mutations (self.speciesData?.field = x) do not
                        // reliably fire @Observable notifications for struct value types; a single
                        // full-value replacement is the only guaranteed trigger.
                        // Guard on scanId: a stale enrichment task completing after a new scan
                        // has already set speciesData must not overwrite the new scan's fields.
                        if var updated = self.speciesData,
                           self.isLiveSpeciesPresentation(
                               scanId: capturedScanId,
                               scientificName: capturedScientificName,
                               presentationGeneration: capturedPresentationGeneration,
                               reviewActionGeneration: reviewActionGeneration
                           ) {
                            updated.habitatDescription = enrichData.habitat_description
                            if let tax = enrichData.taxonomy {
                                updated.taxonomy = TaxonomyData(
                                    kingdom: tax.kingdom,
                                    phylum: tax.phylum,
                                    className: tax.`class`,
                                    order: tax.order,
                                    family: tax.family,
                                    genus: tax.genus
                                )
                            }
                            if let key = enrichData.gbif_taxon_key {
                                updated.gbifTaxonKey = key
                            }
                            if let names = enrichData.alternative_common_names {
                                updated.alternativeCommonNames = SpeciesData.sanitizeAlternativeNames(names)
                            }
                            self.speciesData = updated  // Single @Observable-triggering assignment
                        }
                        if let context = modelContext {
                            let container = context.container
                            let habitatSnapshot = enrichData.habitat_description
                            let gbifSnapshot = enrichData.gbif_taxon_key
                            let taxonomySnapshot = enrichData.taxonomy
                            let altNamesSnapshot = enrichData.alternative_common_names
                            self.executeSpeciesMetadataWrite(
                                scanId: capturedScanId,
                                scientificName: capturedScientificName,
                                presentationGeneration: capturedPresentationGeneration,
                                reviewActionGeneration: reviewActionGeneration
                            ) {
                                let dbActor = BackgroundDatabaseActor(modelContainer: container)
                                await dbActor.updateScanWithEnrichment(
                                    scanId: capturedScanId,
                                    habitatDescription: habitatSnapshot,
                                    gbifTaxonKey: gbifSnapshot,
                                    similarSpeciesJsonData: nil,
                                    taxonomy: taxonomySnapshot,
                                    alternativeCommonNames: altNamesSnapshot,
                                    expectedScientificName:
                                        capturedScientificName
                                )
                            }
                        }
                    } catch let error as MerianError {
                        if case .httpError(let code, _) = error, code == 403 { return }
                        if case .httpError(let code, _) = error, code == 429 {
                            self.hydrationCoordinator
                                .recordEnrichmentRateLimit()
                            return
                        }
                        MerianLog.general.debug("Enrichment scope failed: \(error, privacy: .private)")
                    } catch {
                        MerianLog.general.debug("Enrichment scope failed: \(error, privacy: .private)")
                    }
                }
            }

            if needsLookalikes {
                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    defer {
                        if self.isLiveSpeciesPresentation(
                            scanId: capturedScanId,
                            scientificName: capturedScientificName,
                            presentationGeneration: capturedPresentationGeneration,
                            reviewActionGeneration: reviewActionGeneration
                        ) {
                            self.isLookalikesLoading = false
                        }
                    }
                    do {
                        let response = try await MerianNetworkClient.shared.fetchEnrichment(
                            scanId: capturedScanId,
                            scientificName: capturedScientificName,
                            confidenceScore: capturedConfidence,
                            inferenceTier: capturedTier,
                            scope: "lookalikes"
                        )
                        guard let enrichData = response.data else { return }

                        if let entries = enrichData.similar_species, !entries.isEmpty {
                            let mappedEntries = entries.map {
                                let splitCommonName = $0.common_name?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines)
                                return SimilarSpeciesEntry(
                                    scientificName: $0.scientific_name,
                                    commonName: splitCommonName,
                                    referenceImageUrl: $0.reference_image_url,
                                    iucnRedListStatus: $0.iucn_red_list_status,
                                    speciesId: $0.species_id,
                                    similarityReason: $0.reason,
                                    visualTraits: $0.visual_traits ?? [],
                                    similarityConfidence: $0.confidence,
                                    relationshipSource: $0.source,
                                    reviewStatus: $0.review_status,
                                    isBidirectional: $0.is_bidirectional,
                                    sortOrder: $0.sort_order
                                )
                            }
                            // Single full-value replacement — see enrichment scope comment above.
                            // Guard on scanId: a stale lookalikes task completing after a new scan
                            // has set speciesData must not overwrite the new scan's similar species.
                            if var updated = self.speciesData,
                               self.isLiveSpeciesPresentation(
                                   scanId: capturedScanId,
                                   scientificName: capturedScientificName,
                                   presentationGeneration: capturedPresentationGeneration,
                                   reviewActionGeneration: reviewActionGeneration
                               ) {
                                updated.similarSpecies = SimilarSpecies(entries: mappedEntries)
                                self.speciesData = updated
                            }
                            if let context = modelContext {
                                let container = context.container
                                let entriesToEncode: [SimilarSpeciesEntry]? = mappedEntries
                                self.executeSpeciesMetadataWrite(
                                    scanId: capturedScanId,
                                    scientificName: capturedScientificName,
                                    presentationGeneration: capturedPresentationGeneration,
                                    reviewActionGeneration: reviewActionGeneration
                                ) {
                                    // Encode off @MainActor — JSONEncoder is CPU-bound.
                                    let encodedLookalikes: Data? = await Task.detached(priority: .utility) {
                                        entriesToEncode.flatMap { try? JSONEncoder().encode($0) }
                                    }.value
                                    let dbActor = BackgroundDatabaseActor(modelContainer: container)
                                    await dbActor.updateScanWithEnrichment(
                                        scanId: capturedScanId,
                                        habitatDescription: nil,
                                        gbifTaxonKey: nil,
                                        similarSpeciesJsonData: encodedLookalikes,
                                        taxonomy: nil,
                                        expectedScientificName:
                                            capturedScientificName
                                    )
                                }
                            }
                        }
                    } catch let error as MerianError {
                        if case .httpError(let code, _) = error, code == 403 { return }
                        if case .httpError(let code, _) = error, code == 429 {
                            self.hydrationCoordinator
                                .recordEnrichmentRateLimit()
                            return
                        }
                        MerianLog.general.debug("Lookalikes scope failed: \(error, privacy: .private)")
                    } catch {
                        MerianLog.general.debug("Lookalikes scope failed: \(error, privacy: .private)")
                    }
                }
            }
        }

        // If lookalikes were requested before taxonomy was available, the backend now returns
        // null rather than provisional cards. Once metadata lands, retry the lookalikes scope
        // exactly once so first-open UX still recovers within the same session.
        if allowLookalikesRetry,
           needsMetadata,
           needsLookalikes,
           isLiveSpeciesPresentation(
               scanId: capturedScanId,
               scientificName: capturedScientificName,
               presentationGeneration: capturedPresentationGeneration,
               reviewActionGeneration: reviewActionGeneration
           ),
           speciesData?.similarSpecies == nil,
           hasUsableLookalikeTaxonomy(speciesData?.taxonomy) {
            await fetchAndApplyEnrichment(
                modelContext: modelContext,
                needsMetadata: false,
                needsLookalikes: true,
                allowLookalikesRetry: false,
                reviewActionGeneration: reviewActionGeneration
            )
        }
    }

    // MARK: - Identification Override

    /// Called when the user selects a candidate as their preferred identification.
    /// Immediately updates display state, persists locally, syncs to cloud, and hydrates
    /// species data for the override species from `species_dictionary`.
    func applyIdentificationOverride(
        scientificName: String,
        expectedScanId: String? = nil,
        modelContext: ModelContext?
    ) async {
        guard !writeCoordinator.isAuthTransitionFenceActive,
              let scanId = speciesData?.scanId,
              expectedScanId == nil ||
                expectedScanId?.caseInsensitiveCompare(scanId) == .orderedSame else {
            return
        }
        let reviewActionGeneration = beginIdentificationReviewAction(scanId: scanId)
        _ = beginIdentificationFlagAction(scanId: scanId)
        let presentationGeneration = writeCoordinator.generation
        let container = modelContext?.container
        cancelSpeciesHydrationForIdentificationChange()

        // 1. Immediately update display — scientificName drives InsightHeader subtitle.
        // Wipe stale contextual data to prevent old UI cards from lingering during the fetch.
        // Full-value replacement guarantees a single @Observable notification for the entire wipe.
        if var updated = speciesData {
            updated.userIdentificationOverride = scientificName
            updated.scientificName = scientificName
            updated.commonName = scientificName
            updated.insightData = InsightData(aiReasoning: "", hazardType: "none")
            updated.wikipediaOverview = nil
            updated.wikipediaUrl = nil
            updated.referenceImageUrl = nil
            updated.iucnRedListStatus = nil
            updated.habitatDescription = nil
            updated.gbifTaxonKey = nil
            updated.taxonomy = nil
            updated.alternativeCommonNames = nil
            updated.similarSpecies = nil
            updated.userConfirmedIdentification = false
            updated.isFlagged = false
            updated.alternativesExhausted = false
            speciesData = updated
            activeMedia.referenceState = .empty
        }
        let localOverrideAdmission: Task<Void, Never>? = if let container {
            enqueueIdentificationWrite(
                scanId: scanId,
                actionGeneration: reviewActionGeneration
            ) {
                let dbActor = BackgroundDatabaseActor(modelContainer: container)
                await dbActor.beginScanIdentificationOverride(
                    scanId: scanId,
                    scientificName: scientificName
                )
            }
        } else {
            nil
        }
        await localOverrideAdmission?.value
        guard !writeCoordinator.isAuthTransitionFenceActive,
              isLiveSpeciesPresentation(
                  scanId: scanId,
                  scientificName: scientificName,
                  presentationGeneration: presentationGeneration,
                  reviewActionGeneration: reviewActionGeneration
              ) else {
            return
        }

        // 2. Register the complete review hydration before its first network
        // suspension. Replacement, dismissal, and Auth transitions can now
        // cancel and drain the Species Dictionary and reference-image work.
        await hydrationCoordinator.replaceAndAwaitTask(
            in: .review
        ) { [weak self] in
            guard let self else { return }
            let confirmedId = await self.fetchAndPatchOverrideData(
                scientificName: scientificName,
                scanId: scanId,
                modelContext: modelContext,
                replacingSpeciesIdentity: true,
                reviewActionGeneration: reviewActionGeneration
            )
            guard !Task.isCancelled,
                  self.isIdentificationReviewActionCurrent(
                      scanId: scanId,
                      generation: reviewActionGeneration
                  ) else {
                return
            }

            // 3–4. Serialize local and cloud writes so this choice remains the
            // final writer even when a newer review action begins while an
            // older request is already in flight.
            self.enqueueIdentificationWrite(
                scanId: scanId,
                actionGeneration: reviewActionGeneration
            ) { [weak self] in
                if let container {
                    let dbActor = BackgroundDatabaseActor(
                        modelContainer: container
                    )
                    await dbActor.updateScanWithOverride(
                        scanId: scanId,
                        override: scientificName,
                        confirmed: false,
                        newConfirmedSpeciesId: confirmedId,
                        userReviewState: .userOverridden
                    )
                }
                await self?.syncIdentificationReviewToCloud(
                    scanId: scanId,
                    override: scientificName,
                    confirmed: false,
                    confirmedSpeciesId: confirmedId,
                    userReviewState:
                        UserReviewState.userOverridden.rawValue
                )
            }

            await self.hydrateMissingReviewReferenceImages(
                scanId: scanId,
                scientificName: scientificName,
                presentationGeneration: presentationGeneration,
                reviewActionGeneration: reviewActionGeneration,
                modelContext: modelContext
            )
        }
    }

    /// Called when the user confirms the AI's primary identification ("Yes, correct").
    /// Persists locally and syncs confirmation to the cloud scan record.
    func confirmAIIdentification(
        expectedScanId: String? = nil,
        modelContext: ModelContext?
    ) async {
        guard !writeCoordinator.isAuthTransitionFenceActive,
              let scanId = speciesData?.scanId,
              speciesData?.userIdentificationOverride == nil,
              expectedScanId == nil ||
              expectedScanId?.caseInsensitiveCompare(scanId) == .orderedSame else {
            return
        }
        let confirmationActionGeneration =
            beginIdentificationConfirmationAction(scanId: scanId)
        hydrationCoordinator.cancelCurrentTask(in: .review)

        if var updated = speciesData {
            updated.userConfirmedIdentification = true
            speciesData = updated
        }

        let container = modelContext?.container
        let confirmedSpeciesId: String?
        if let context = modelContext {
            let descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == scanId })
            confirmedSpeciesId = (try? context.fetch(descriptor))?.first?.speciesId
        } else {
            confirmedSpeciesId = nil
        }

        enqueueIdentificationWrite(
            scanId: scanId,
            actionGeneration: confirmationActionGeneration,
            channel: .confirmation
        ) { [weak self] in
            if let container {
                let dbActor = BackgroundDatabaseActor(modelContainer: container)
                await dbActor.updateScanWithOverride(
                    scanId: scanId,
                    override: nil,
                    confirmed: true,
                    newConfirmedSpeciesId: confirmedSpeciesId,
                    userReviewState: .aiConfirmed
                )
            }
            await self?.syncIdentificationReviewToCloud(
                scanId: scanId,
                override: nil,
                confirmed: true,
                confirmedSpeciesId: confirmedSpeciesId,
                userReviewState: UserReviewState.aiConfirmed.rawValue
            )
        }
    }

    /// Resets all identification review state, reverting the scan back to the AI's original
    /// identification. Called by Undo (from `.overridden`) and Change (from `.confirmed`).
    /// Clears both `userIdentificationOverride` and `userConfirmedIdentification` locally,
    /// syncs both columns to null/false in the cloud, and re-hydrates the AI species data.
    func resetIdentificationReview(
        expectedScanId: String? = nil,
        modelContext: ModelContext?
    ) async {
        guard !writeCoordinator.isAuthTransitionFenceActive,
              let scanId = speciesData?.scanId,
              expectedScanId == nil ||
                expectedScanId?.caseInsensitiveCompare(scanId) == .orderedSame,
              let aiName = speciesData?.aiScientificName,
              !aiName.isEmpty else { return }
        let reviewActionGeneration = beginIdentificationReviewAction(scanId: scanId)
        let flagActionGeneration = beginIdentificationFlagAction(scanId: scanId)
        let presentationGeneration = writeCoordinator.generation
        cancelSpeciesHydrationForIdentificationChange()

        let container = modelContext?.container
        var originalAiReasoning: String?
        if let context = modelContext {
            let descriptor = FetchDescriptor<LocalScanRecord>(
                predicate: #Predicate { $0.id == scanId }
            )
            originalAiReasoning = (try? context.fetch(descriptor))?
                .first?.aiReasoning
        }
        let restoredReasoning = originalAiReasoning
            ?? speciesData?.aiReasoning
            ?? ""

        // 1. Revert identity immediately and clear every override-owned
        // presentation field. A cache miss must not leave the rejected
        // species' taxonomy, media, or overview visible under the AI name.
        if var updated = speciesData {
            updated.userIdentificationOverride = nil
            updated.userConfirmedIdentification = false
            updated.isFlagged = false
            updated.alternativesExhausted = false
            updated.scientificName = aiName
            updated.commonName = aiName
            updated.insightData = InsightData(
                aiReasoning: restoredReasoning,
                hazardType: "none"
            )
            updated.wikipediaOverview = nil
            updated.wikipediaUrl = nil
            updated.referenceImageUrl = nil
            updated.iucnRedListStatus = nil
            updated.habitatDescription = nil
            updated.gbifTaxonKey = nil
            updated.taxonomy = nil
            updated.alternativeCommonNames = nil
            updated.similarSpecies = nil
            speciesData = updated
        }
        activeMedia.referenceState = .empty

        if let container {
            enqueueIdentificationWrite(
                scanId: scanId,
                actionGeneration: flagActionGeneration,
                channel: .legacyFlag
            ) {
                let dbActor = BackgroundDatabaseActor(modelContainer: container)
                await dbActor.updateScanAsUnflagged(scanId: scanId)
            }
        }

        // 2–3. Serialize the local reset and cloud reset behind any already-started older
        // write. This makes the user's newest action the durable final state.
        enqueueIdentificationWrite(
            scanId: scanId,
            actionGeneration: reviewActionGeneration
        ) { [weak self] in
            if let container {
                let dbActor = BackgroundDatabaseActor(modelContainer: container)
                await dbActor.updateScanWithOverride(
                    scanId: scanId,
                    override: nil,
                    confirmed: false,
                    newConfirmedSpeciesId: nil,
                    userReviewState: .unreviewed
                )
            }
            await self?.syncIdentificationReviewToCloud(
                scanId: scanId,
                override: nil,
                confirmed: false,
                confirmedSpeciesId: nil,
                userReviewState: UserReviewState.unreviewed.rawValue
            )
        }

        // 4. Re-hydrate the original species inside the tracked review slot.
        await hydrationCoordinator.replaceAndAwaitTask(
            in: .review
        ) { [weak self] in
            guard let self else { return }
            await self.fetchAndPatchOverrideData(
                scientificName: aiName,
                scanId: scanId,
                modelContext: modelContext,
                restoringAiReasoning: restoredReasoning,
                replacingSpeciesIdentity: true,
                reviewActionGeneration: reviewActionGeneration
            )
            await self.hydrateMissingReviewReferenceImages(
                scanId: scanId,
                scientificName: aiName,
                presentationGeneration: presentationGeneration,
                reviewActionGeneration: reviewActionGeneration,
                modelContext: modelContext
            )
        }
    }

    /// Queries `species_dictionary` for the given scientific name and patches the live
    /// `speciesData` in-place. On cache miss, it can await
    /// `fetchAndApplyEnrichment`; the owning live, historical, or review task
    /// remains responsible for subsequent reference-image hydration.
    ///
    /// - Parameter restoringAiReasoning: When non-nil, the AI reasoning text is restored to
    ///   this value instead of being wiped. Pass the original `record.aiReasoning` when
    ///   called from `resetIdentificationReview` so the reasoning reappears after an undo.
    ///   Pass nil (default) when called from `applyIdentificationOverride` to suppress the
    ///   original AI reasoning under the override species name.
    /// - Parameter enrichOnCacheMiss: Keep true for interactive review work.
    ///   Historical loading passes false because its enclosing task owns the
    ///   single enrichment/GBIF sequence.
    /// - Parameter replacingSpeciesIdentity: Clears prior-species taxonomy and
    ///   related collections only for an interactive override or reset. A
    ///   historical refresh preserves already-valid data for the same species.
    @MainActor
    @discardableResult
    private func fetchAndPatchOverrideData(
        scientificName: String,
        scanId: String,
        modelContext: ModelContext?,
        restoringAiReasoning: String? = nil,
        enrichOnCacheMiss: Bool = true,
        replacingSpeciesIdentity: Bool,
        reviewActionGeneration: UInt64
    ) async -> String? {
        struct SpeciesDictRow: Decodable {
            let id: String
            let common_names: [String: String?]?
            let kingdom: String?
            let phylum: String?
            let `class`: String?
            let order: String?
            let family: String?
            let genus: String?
            let wikipedia_overview: String?
            let hazard_type: String?
            let reference_image_url: String?
            let wikipedia_url: String?
            let iucn_red_list_status: String?
            let habitat_description: String?
            let gbif_taxon_key: Int?
        }
        
        struct IdOnlyRow: Decodable { let id: String }

        do {
            let rows: [SpeciesDictRow] = try await SupabaseManager.shared.client
                .from("species_dictionary")
                .select("id, common_names, kingdom, phylum, class, order, family, genus, wikipedia_overview, hazard_type, reference_image_url, wikipedia_url, iucn_red_list_status, habitat_description, gbif_taxon_key")
                .eq("scientific_name", value: scientificName)
                .limit(1)
                .execute()
                .value
            guard !Task.isCancelled else { return nil }

            if let row = rows.first {
                // Cache hit — patch all available fields reactively.
                // Prefer the authoritative "en" locale; fall back to any available translation;
                // final fallback is the scientific name. Mirrors ScanRepository's resolution logic.
                let commonName: String = {
                    guard let names = row.common_names else { return scientificName }
                    return names["en"].flatMap { $0 } ?? names.compactMap { $0.value }.first ?? scientificName
                }()
                // On override: wipe aiReasoning — the AI's explanation was for the rejected species.
                // On reset (restoringAiReasoning != nil): restore the original reasoning so the
                // paragraph reappears under the reverted AI identification.
                //
                // Individual optional-chain mutations (speciesData?.field = x) do not reliably
                // fire @Observable notifications for struct value types; a single full-value
                // replacement is the only guaranteed trigger.
                if var updated = speciesData,
                   isLiveSpeciesPresentation(
                       scanId: scanId,
                       scientificName: scientificName,
                       reviewActionGeneration: reviewActionGeneration
                   ) {
                    updated.commonName = commonName.capitalized
                    updated.insightData = InsightData(
                        aiReasoning: restoringAiReasoning ?? "",
                        hazardType: row.hazard_type ?? "none"
                    )
                    updated.taxonomy = TaxonomyData(
                        kingdom: row.kingdom,
                        phylum: row.phylum,
                        className: row.class,
                        order: row.order,
                        family: row.family,
                        genus: row.genus
                    )
                    updated.iucnRedListStatus = row.iucn_red_list_status
                    updated.habitatDescription = row.habitat_description
                    updated.gbifTaxonKey = row.gbif_taxon_key
                    updated.referenceImageUrl = ExternalReferenceImagePolicy.sanitizedURLList(
                        row.reference_image_url
                    )
                    updated.wikipediaOverview = row.wikipedia_overview
                    updated.wikipediaUrl = row.wikipedia_url
                    speciesData = updated
                    let referenceURLs = Self.normalizedReferenceURLs(
                        from: updated.referenceImageUrl
                    )
                    activeMedia.referenceState = referenceURLs.isEmpty
                        ? .empty
                        : .loaded(referenceURLs)
                }

                // Persist updated species fields so they survive sheet dismissal and reopen.
                // scientificName is intentionally excluded — it is preserved as aiScientificName.
                if let context = modelContext {
                    let container = context.container
                    let capturedCommonName = commonName.capitalized
                    let capturedHazardType = row.hazard_type ?? "none"
                    let capturedTaxonomy = TaxonomyData(
                        kingdom: row.kingdom, phylum: row.phylum, className: row.class,
                        order: row.order, family: row.family, genus: row.genus
                    )
                    let capturedWikiOverview = row.wikipedia_overview
                    let capturedWikiUrl = row.wikipedia_url
                    let capturedRefImageUrl =
                        ExternalReferenceImagePolicy.sanitizedURLList(
                            row.reference_image_url
                        )
                    let capturedIucn = row.iucn_red_list_status
                    let capturedHabitat = row.habitat_description
                    let capturedGbif = row.gbif_taxon_key
                    enqueueIdentificationWrite(
                        scanId: scanId,
                        actionGeneration: reviewActionGeneration
                    ) {
                        let dbActor = BackgroundDatabaseActor(modelContainer: container)
                        await dbActor.updateScanWithOverrideSpeciesData(
                            scanId: scanId,
                            commonName: capturedCommonName,
                            hazardType: capturedHazardType,
                            wikipediaOverview: capturedWikiOverview,
                            wikipediaUrl: capturedWikiUrl,
                            referenceImageUrl: capturedRefImageUrl,
                            iucnRedListStatus: capturedIucn,
                            habitatDescription: capturedHabitat,
                            gbifTaxonKey: capturedGbif,
                            taxonomy: capturedTaxonomy,
                            replacingSpeciesIdentity:
                                replacingSpeciesIdentity
                        )
                    }
                }
                return row.id
            } else {
                // Cache miss — enrich the override species. fetchAndApplyEnrichment uses
                // speciesData.scientificName which is already set to the override name.
                // Interactive replacement already admitted an atomic local
                // override placeholder before this lookup began.
                if enrichOnCacheMiss,
                   isLiveSpeciesPresentation(
                    scanId: scanId,
                    scientificName: scientificName,
                    reviewActionGeneration: reviewActionGeneration
                ) {
                    await fetchAndApplyEnrichment(
                        modelContext: modelContext,
                        reviewActionGeneration: reviewActionGeneration
                    )
                }

                guard !Task.isCancelled else { return nil }
                let fallbackRows: [IdOnlyRow]? = try? await SupabaseManager.shared.client
                    .from("species_dictionary")
                    .select("id")
                    .eq("scientific_name", value: scientificName)
                    .limit(1)
                    .execute()
                    .value
                return fallbackRows?.first?.id
            }
        } catch {
            MerianLog.general.debug("fetchAndPatchOverrideData failed: \(error, privacy: .private)")

            guard !Task.isCancelled else { return nil }
            let fallbackRows: [IdOnlyRow]? = try? await SupabaseManager.shared.client
                .from("species_dictionary")
                .select("id")
                .eq("scientific_name", value: scientificName)
                .limit(1)
                .execute()
                .value
            return fallbackRows?.first?.id
        }
    }

    /// Completes reference-image hydration inside the review task that owns the
    /// Species Dictionary lookup. Existing authoritative imagery is preserved;
    /// GBIF is only consulted when the reviewed species still owns this exact
    /// presentation and has no usable reference URL.
    private func hydrateMissingReviewReferenceImages(
        scanId: String,
        scientificName: String,
        presentationGeneration: UInt64,
        reviewActionGeneration: UInt64,
        modelContext: ModelContext?
    ) async {
        guard !Task.isCancelled,
              isLiveSpeciesPresentation(
                  scanId: scanId,
                  scientificName: scientificName,
                  presentationGeneration: presentationGeneration,
                  reviewActionGeneration: reviewActionGeneration
              ),
              Self.normalizedReferenceURLs(
                  from: speciesData?.referenceImageUrl
              ).isEmpty,
              let taxonKey = speciesData?.gbifTaxonKey else {
            return
        }

        await fetchGBIFImagesAndHydrate(
            for: taxonKey,
            scanId: scanId,
            scientificName: scientificName,
            presentationGeneration: presentationGeneration,
            reviewActionGeneration: reviewActionGeneration,
            modelContext: modelContext
        )
    }

    /// Owner-derived RPC persisting the complete identification review atomically.
    /// Accepts nil for `override` to set the column to NULL (reset / confirmed-only path).
    private func syncIdentificationReviewToCloud(scanId: String, override: String?, confirmed: Bool, confirmedSpeciesId: String?, userReviewState: String) async {
        guard let accountWorkLease = try? SupabaseManager.shared
            .beginUnownedAccountBoundWork() else { return }
        defer {
            SupabaseManager.shared.finishAccountBoundWork(accountWorkLease)
        }

        do {
            try await SupabaseManager.shared.client
                .rpc(
                    "update_owned_scan_identification_review",
                    params: ReviewSyncRPCParameters(
                        scanId: scanId,
                        override: override,
                        confirmed: confirmed,
                        confirmedSpeciesId: confirmedSpeciesId,
                        userReviewState: userReviewState
                    )
                )
                .execute()

            guard SupabaseManager.shared
                .isAccountBoundWorkLeaseCurrent(accountWorkLease) else {
                return
            }

            if let postId = ExploreShareStateStore.sharedPostId(for: scanId) {
                AppDIContainer.shared.appEventPublisher.send(.explorePostNeedsRefresh(postId: postId))
            }
            await AppDIContainer.shared.scanMilestoneCoordinator.processIdentificationUpdate(scanId: scanId)
        } catch {
            MerianLog.general.debug(
                "syncIdentificationReviewToCloud failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
        }
    }

    // MARK: - Pipeline Modifiers

    /// Ends only presentation-owned local analysis. Durable inference, queue
    /// recovery, persistence, and result publication continue independently.
    /// Clearing the owners before cancellation fences even non-cooperative local
    /// providers from publishing after the sheet has gone away.
    func dismissAnalyzingPresentation() {
        preparedPresentationOwner = nil
        activePresentationOwner = nil
        recoverablePresentationScanId = nil
        queuedPresentationScanId = nil
        queuedVisualPresentationScanId = nil
        queuedPresentationCarriesLiveMedia = false
        queuedPresentationScanningPhrases = []
        pendingFirstRenderMetric = nil
        cancelLocalVisualAnalysis()
        scanningPhaseText = ScanningPhraseCoordinator.genericPhrases[0]
        activeMedia = ActiveScanMedia()
    }

    /// Cancels all in-flight work and resets the engine to idle.
    ///
    /// Contrast with `prepareForNewScan()`, which also cancels in-flight work but leaves
    /// `isProcessing = true` in anticipation of an *upcoming* scan. `cancelActiveRequest`
    /// resets to `isProcessing = false, speciesData = nil` — appropriate when the user
    /// dismisses the insight sheet with no new scan queued.
    func cancelActiveRequest(isUserInitiated: Bool = false) {
        invalidateActiveLiveInferenceAttempt(
            resumeBackground: true,
            reason: isUserInitiated
                ? "live_scan_cancelled_by_user"
                : "live_scan_cancelled"
        )
        // The helper invalidates the UUID and paired scan identity atomically,
        // so the cancelled task's defer no longer owns this slot.
        // Background-wins hydration still works for a suspended live task;
        // an explicitly cancelled presentation is intentionally no longer a
        // hydration target.
        self.isProcessing = false
        self.inferenceTask?.cancel()
        self.hydrationCoordinator.cancelAllTasks()
        self.cancelLocalVisualAnalysis()
        self.resetTrackedBackgroundWrites()
        // Reset loading flags synchronously so stale defer blocks from cancelled task group
        self.scanningPhaseText = ScanningPhraseCoordinator.genericPhrases[0]
        self.isEnrichmentLoading = false
        self.isLookalikesLoading = false
        self.speciesData = nil
        self.recoverablePresentationScanId = nil
        self.queuedPresentationScanId = nil
        self.queuedVisualPresentationScanId = nil
        self.queuedPresentationCarriesLiveMedia = false
        self.queuedPresentationScanningPhrases = []
        self.preparedPresentationOwner = nil
        self.activePresentationOwner = nil
        self.pendingFirstRenderMetric = nil
        self.activeMedia = ActiveScanMedia()
        activeLatitude = nil
        activeLongitude = nil
        activeElevation = nil
        activeLocationName = nil
        activeWeatherCondition = nil
        activeTemperatureF = nil
    }

    /// Called by the Insight sheet's one-shot UIKit draw probe. Unlike a task
    /// yield, `draw(_:)` only fires when the result view participates in a real
    /// display pass, so this closes the user-perceived latency interval at the
    /// first rendered frame rather than at state assignment.
    func recordFirstRenderedFrame(scanId: String) {
        guard let metric = pendingFirstRenderMetric,
              metric.scanId.caseInsensitiveCompare(scanId) == .orderedSame else {
            return
        }
        pendingFirstRenderMetric = nil
        MerianLog.general.debug(
            "[⏱ BENCH] Analyze tap to first rendered frame: \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - metric.startedAt), privacy: .public)s"
        )
    }

#if DEBUG
    struct DebugBackgroundWriteState: Sendable {
        let active: Int
        let pending: Int
        let generation: UInt64
    }

    var debugBackgroundWriteTaskCap: Int { writeCoordinator.activeTaskCapacity }
    var debugPendingBackgroundWriteTaskCap: Int {
        writeCoordinator.pendingTaskCapacity
    }

    func debugBackgroundWriteState() -> DebugBackgroundWriteState {
        let snapshot = writeCoordinator.snapshot
        return DebugBackgroundWriteState(
            active: snapshot.active,
            pending: snapshot.pending,
            generation: snapshot.generation
        )
    }

    func debugEnqueueTrackedBackgroundTask(_ operation: @escaping @Sendable () async -> Void) {
        writeCoordinator.enqueueBackgroundWrite(operation)
    }
#endif

    // MARK: - Local Record Loading

    var hasHistoricHydrationWork: Bool {
        hydrationCoordinator.hasCurrentTask(in: .historic)
    }

    func awaitHistoricHydration() async {
        await hydrationCoordinator.awaitCurrentTask(in: .historic)
    }

    func cancelHistoricHydration() {
        hydrationCoordinator.cancelCurrentTask(in: .historic)
    }

    /// Rehydrates engine state from a persisted `LocalScanRecord` for the insight sheet.
    ///
    /// All async work (path validation, JSON decoding, network hydration) runs
    /// inside the hydration coordinator's single current historic slot so that
    /// navigating to a different scan immediately cancels the previous scan's
    /// outstanding work.
    func load(from record: LocalScanRecord) {
        guard !writeCoordinator.isAuthTransitionFenceActive else { return }
        // Loading a persisted record replaces the live presentation just as
        // starting another capture does. Relinquish the exact foreground owner
        // before changing activeScanId, otherwise the old task can no longer
        // identify itself to release durable recovery suppression.
        invalidateActiveLiveInferenceAttempt(
            resumeBackground: true,
            reason: "persisted_scan_loaded"
        )
        inferenceTask?.cancel()
        recoverablePresentationScanId = nil
        queuedPresentationScanId = nil
        queuedVisualPresentationScanId = nil
        queuedPresentationCarriesLiveMedia = false
        queuedPresentationScanningPhrases = []
        preparedPresentationOwner = nil
        activePresentationOwner = nil
        self.isProcessing = true
        hydrationCoordinator.cancelAllTasks()
        cancelLocalVisualAnalysis()
        resetTrackedBackgroundWrites()
        pendingFirstRenderMetric = nil

        self.activeScanId = record.id
        self.activeMedia = ActiveScanMedia()
        self.activeMedia = record.capturedMediaSnapshot.activeScanMedia

        let recordHasResolvedBiologicalIdentification = record.hasResolvedBiologicalIdentification
        let recordAllowsSpeciesHydration = recordHasResolvedBiologicalIdentification && !record.isHumanSubject
        let recordAllowsReferenceImages = recordAllowsSpeciesHydration && !record.shouldSuppressReferenceImages
        let candidatesRawData: Data? = recordAllowsSpeciesHydration ? record.candidatesData : nil
        let petIdentification = recordAllowsSpeciesHydration ? record.petIdentification : nil
        let overrideName: String? = record.userIdentificationOverride
        // When a manual override is active, display the override scientific name as the title.
        // record.scientificName is preserved as the original-AI identifier and reused below
        // as aiScientificName so that resetIdentificationReview can recover it without a new
        // schema field.
        let displayScientificName: String = overrideName ?? record.scientificName
        // Suppress AI reasoning when an override is active — it was written for the originally
        // predicted species and is misleading when displayed under the override species name.
        let displayAiReasoning: String = overrideName == nil ? (record.aiReasoning ?? "") : ""
        let recordScientificName = record.scientificName
        let hydrationScientificName = displayScientificName
        let recordId = record.id
        let safeContext = record.modelContext
        let shouldResetLocalLookalikes = recordAllowsSpeciesHydration && shouldResetLocalLookalikesCache()
        if shouldResetLocalLookalikes {
            scheduleLocalLookalikesCacheResetIfNeeded(modelContext: safeContext)
        }
        let lookalikesJsonData: Data? = recordAllowsSpeciesHydration && !shouldResetLocalLookalikes
            ? record.lookalikesData
            : nil
        let lookalikesLegacyArray: [String]? = recordAllowsSpeciesHydration && !shouldResetLocalLookalikes
            ? record.similarSpecies
            : nil
        let gbifKey = record.gbifTaxonKey
        let needsWiki = recordAllowsSpeciesHydration && (
            record.wikipediaOverview == nil ||
                (recordAllowsReferenceImages &&
                    (record.referenceImageUrl == nil || record.referenceImageUrl!.isEmpty))
        )
        let recordTaxonomy = recordAllowsSpeciesHydration
            ? TaxonomyData(
                kingdom: record.taxonomyKingdom,
                phylum: record.taxonomyPhylum,
                className: record.taxonomyClass,
                order: record.taxonomyOrder,
                family: record.taxonomyFamily,
                genus: record.taxonomyGenus
            )
            : nil
        // Decode lookalikesData once here on @MainActor — the blob is small (3 entries × 4 fields).
        // The result is reused for both the needsEnrichment gate check and the UI decode step
        // inside the historic hydration task, avoiding a second JSONDecoder
        // allocation on the same data.
        let preDecodedSimilar: SimilarSpecies? = lookalikesJsonData.flatMap {
            (try? JSONDecoder().decode([SimilarSpeciesEntry].self, from: $0))
                .map { SimilarSpecies(entries: $0) }
        }
        // A scan needs enrichment when any of the three key fields are absent, OR when
        // lookalikesData exists but every decoded entry has a nil commonName — indicating
        // the join table was populated before the common-name back-fill pipeline was added.
        let lookalikesHaveNoCommonNames: Bool = preDecodedSimilar.map {
            !$0.entries.isEmpty && $0.entries.allSatisfy { $0.commonName == nil }
        } ?? false
        // Split enrichment needs by scope so each concurrent call is fired only when required.
        let needsMetadata = recordAllowsSpeciesHydration &&
            (record.habitatDescription == nil || record.gbifTaxonKey == nil || !hasUsableLookalikeTaxonomy(recordTaxonomy))
        let needsLookalikes = recordAllowsSpeciesHydration &&
            (shouldResetLocalLookalikes || record.lookalikesData == nil || lookalikesHaveNoCommonNames)
        let needsEnrichment = needsMetadata || needsLookalikes
        let recordReferenceImageUrl = recordAllowsReferenceImages ? record.referenceImageUrl : nil

        // Set speciesData immediately with nil for blob-decoded fields.
        // similarSpecies and candidates are populated by the task below to avoid
        // blocking @MainActor with synchronous JSONDecoder calls on large datasets.
        self.speciesData = SpeciesData(
            scanId: record.id,
            commonName: record.commonName,
            scientificName: displayScientificName,
            insightData: InsightData(aiReasoning: displayAiReasoning, hazardType: record.hazardType),
            confidenceScore: record.confidenceScore ?? 0.0,
            blurScore: nil,
            similarSpecies: nil,
            wikipediaUrl: record.wikipediaUrl,
            wikipediaOverview: record.wikipediaOverview,
            referenceImageUrl: recordReferenceImageUrl,
            isBiological: record.isBiological,
            isLiveCapture: record.isLiveCapture,
            isInvasive: record.isInvasive,
            invasiveStatusRegion: record.invasiveStatusRegion,
            invasiveRationale: record.invasiveRationale,
            invasiveConfidence: record.invasiveConfidence,
            ecologyType: record.ecologyType,
            taxonomy: recordTaxonomy,
            locationName: record.locationName,
            weatherCondition: record.weatherCondition,
            weatherTemperatureF: record.weatherTemperatureF,
            gpsElevation: record.gpsElevation,
            gpsLatitude: record.gpsLatitude,
            gpsLongitude: record.gpsLongitude,
            colors: nil,
            groupTags: nil,
            iucnRedListStatus: record.iucnRedListStatus,
            zoomFactor: record.zoomFactor,
            estimatedSizeCm: record.estimatedSizeCm,
            lifeStage: record.lifeStage,
            reproductiveCondition: record.reproductiveCondition,
            sex: record.sex,
            sexConfidence: record.sexConfidence,
            sexEvidence: record.sexEvidence,
            individualCount: record.individualCount,
            ecologicalInteractions: record.ecologicalInteractions,
            aiReasoning: record.aiReasoning,
            habitatDescription: record.habitatDescription,
            gbifTaxonKey: recordAllowsSpeciesHydration ? record.gbifTaxonKey : nil,
            inferenceTier: record.inferenceTier,
            alternativeCommonNames: recordAllowsSpeciesHydration ? record.alternativeCommonNames : nil,
            petIdentification: petIdentification,
            candidates: nil,
            imageQualityScore: record.imageQualityScore,
            aiScientificName: recordScientificName,
            userIdentificationOverride: record.userIdentificationOverride,
            userConfirmedIdentification: record.userConfirmedIdentification,
            isFlagged: record.isFlagged
        )
        self.isProcessing = false
        let historicPresentationGeneration = writeCoordinator.generation
        let reviewActionGeneration =
            beginIdentificationReviewAction(scanId: recordId)

        hydrationCoordinator.replaceTask(in: .historic) { [weak self] in
            guard let self else { return }

            // Step 1: Determine initial reference image loading state.
            guard !Task.isCancelled else { return }
            let refUrls = Self.normalizedReferenceURLs(from: recordReferenceImageUrl)
            let shouldLoadImages = recordAllowsReferenceImages && refUrls.isEmpty && (gbifKey != nil || needsEnrichment)
            self.activeMedia.referenceState = shouldLoadImages ? .loading : (refUrls.isEmpty ? .empty : .loaded(refUrls))

            // Step 2: Resolve similar species and decode candidates off @MainActor (CPU-bound).
            // similarSpecies reuses the pre-decoded result from the gate check above —
            // no second JSONDecoder pass on lookalikesData. Candidates are decoded here
            // since they were not needed for any @MainActor gate.
            let (parsedSimilar, parsedCandidates) = await Task.detached(priority: .userInitiated) {
                let similar: SimilarSpecies? = preDecodedSimilar
                    ?? lookalikesLegacyArray.flatMap { arr in
                        arr.isEmpty ? nil : SimilarSpecies(entries: arr.map {
                            SimilarSpeciesEntry(scientificName: $0, commonName: nil, referenceImageUrl: nil, iucnRedListStatus: nil)
                        })
                    }
                let candidates: [IdentificationCandidate]? = candidatesRawData.flatMap {
                    try? JSONDecoder().decode([IdentificationCandidate].self, from: $0)
                }
                return (similar, candidates)
            }.value

            guard !Task.isCancelled else { return }
            if var updated = self.speciesData {
                updated.similarSpecies = parsedSimilar
                updated.candidates = parsedCandidates
                self.speciesData = updated
            }

            // Step 3: If an identification override is active, patch in the override species data.
            if let override = overrideName, recordAllowsSpeciesHydration {
                guard !Task.isCancelled else { return }
                await self.fetchAndPatchOverrideData(
                    scientificName: override,
                    scanId: recordId,
                    modelContext: safeContext,
                    enrichOnCacheMiss: false,
                    replacingSpeciesIdentity: false,
                    reviewActionGeneration: reviewActionGeneration
                )
            }

            // Steps 4 & 5: Retroactive Wikipedia hydration, Enrichment, and GBIF-image hydration.
            // Run Wikipedia and Enrichment concurrently. GBIF images run sequentially after Enrichment.
            await withTaskGroup(of: Void.self) { group in
                if needsWiki {
                    group.addTask { @MainActor [weak self] in
                        guard let self else { return }
                        guard !Task.isCancelled else { return }
                        await self.fetchWikipediaAndHydrate(
                            for: hydrationScientificName,
                            scanId: recordId,
                            presentationGeneration: historicPresentationGeneration,
                            reviewActionGeneration: reviewActionGeneration,
                            modelContext: safeContext
                        )
                    }
                }

                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    var taxonKeyToUse = gbifKey
                    let speciesIsEnriched = self.hydrationCoordinator
                        .isSpeciesEnriched(hydrationScientificName)
                    let plannedScopes = Self.plannedEnrichmentScopes(
                        needsMetadata: needsMetadata,
                        needsLookalikes: needsLookalikes,
                        speciesIsEnriched: speciesIsEnriched
                    )

                    // Metadata is species-level cached, but lookalikes are still hydrated per-scan
                    // unless the record already has rich local lookalike data persisted.
                    if (plannedScopes.metadata || plannedScopes.lookalikes)
                        && self.hydrationCoordinator
                        .beginHistoricEnrichmentAttempt(scanId: recordId) {
                        guard !Task.isCancelled else { return }
                        await self.fetchAndApplyEnrichment(
                            modelContext: safeContext,
                            needsMetadata: plannedScopes.metadata,
                            needsLookalikes: plannedScopes.lookalikes,
                            reviewActionGeneration: reviewActionGeneration
                        )
                        if !Task.isCancelled,
                           self.speciesData?.habitatDescription != nil,
                           self.hasUsableLookalikeTaxonomy(self.speciesData?.taxonomy) {
                            self.hydrationCoordinator.markSpeciesEnriched(
                                hydrationScientificName
                            )
                        }
                        taxonKeyToUse = self.speciesData?.gbifTaxonKey ?? taxonKeyToUse
                    }

                    if let key = taxonKeyToUse, recordAllowsReferenceImages {
                        guard !Task.isCancelled else { return }
                        guard let currentScientificName = self.speciesData?.scientificName,
                              currentScientificName.caseInsensitiveCompare(
                                  hydrationScientificName
                              ) == .orderedSame,
                              self.speciesData?.scanId?.caseInsensitiveCompare(recordId) == .orderedSame else {
                            return
                        }
                        await self.fetchGBIFImagesAndHydrate(
                            for: key,
                            scanId: recordId,
                            scientificName: currentScientificName,
                            presentationGeneration: historicPresentationGeneration,
                            reviewActionGeneration: reviewActionGeneration,
                            modelContext: safeContext
                        )
                    }
                }
            }
        }
    }

    // MARK: - On-Device Subject Study

    /// Builds one bounded image from the primary visual item, then reuses it for
    /// Vision, deterministic visible-trait extraction, and the future Foundation
    /// Models provider. This work never joins the network task and cannot delay
    /// request dispatch or result publication.
    @discardableResult
    private func classifySubjectLocally(
        from data: Data,
        focusRegion: NormalizedImageFocusRegion?
    ) -> Task<Void, Never>? {
        guard let attemptGeneration = activeLiveInferenceAttemptGeneration else {
            return nil
        }
        let session = InferenceLocalAnalysisCoordinator.Session(
            scanId: activeScanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: activeForegroundInferenceGeneration
        )
        return localAnalysisCoordinator.start(
            imageData: data,
            focusRegion: focusRegion,
            session: session,
            isCurrent: { [weak self] session in
                self?.isLocalAnalysisCurrent(session) == true
            },
            publishPhrase: { [weak self] phrase in
                self?.scanningPhaseText = phrase
            }
        )
    }

    private func markInferenceRequestBodySent(
        session: InferenceLocalAnalysisCoordinator.Session
    ) {
        localAnalysisCoordinator.markInferenceRequestBodySent(for: session)
    }

    private func isLocalAnalysisCurrent(
        _ session: InferenceLocalAnalysisCoordinator.Session
    ) -> Bool {
        guard activePresentationOwner?.modality == .visual,
              activePresentationOwner?.attemptGeneration
                == session.attemptGeneration else {
            return false
        }
        return isLiveInferenceAttemptCurrent(
            scanId: session.scanId,
            attemptGeneration: session.attemptGeneration,
            foregroundInferenceGeneration: session.foregroundGeneration
        )
    }

    private func cancelLocalVisualAnalysis(
        resetPhraseCoordinator: Bool = true
    ) {
        localAnalysisCoordinator.cancel(
            resetPhraseCoordinator: resetPhraseCoordinator
        )
    }

    func handleApplicationActiveStateChange(isActive: Bool) {
        let canResume = isProcessing
            && activePresentationOwner?.modality == .visual
            && activePresentationOwner?.attemptGeneration
                == activeLiveInferenceAttemptGeneration
        if isActive {
            localAnalysisCoordinator.resumeAfterInactivity(
                canResume: canResume
            )
            return
        }
        localAnalysisCoordinator.pauseForInactivity(canResume: canResume)
    }

    #if DEBUG
    /// Deterministic generic → category → trait progression for UI development
    /// and the analyzing-pill UI contract test.
    func simulateProgressiveAnalyzing(
        automaticallyAdvances: Bool = true,
        scanId: String = "debug-progressive-analysis"
    ) {
        cancelLocalVisualAnalysis()
        let attemptGeneration = UUID()
        activeScanId = scanId
        activeLiveInferenceAttemptGeneration = attemptGeneration
        activeForegroundInferenceGeneration = nil
        activePresentationOwner = AnalysisPresentationOwner(
            scanId: activeScanId,
            attemptGeneration: attemptGeneration,
            modality: .visual
        )
        isProcessing = true
        let session = InferenceLocalAnalysisCoordinator.Session(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: nil
        )
        localAnalysisCoordinator.startDebugProgression(
            session: session,
            automaticallyAdvances: automaticallyAdvances,
            isCurrent: { [weak self] session in
                self?.isLocalAnalysisCurrent(session) == true
            },
            publishPhrase: { [weak self] phrase in
                self?.scanningPhaseText = phrase
            }
        )
    }

    func debugAdvanceProgressiveAnalyzing() {
        localAnalysisCoordinator.advanceDebugProgression()
    }

    func simulateAnalyzing() {
        simulateProgressiveAnalyzing()
    }

    func debugStartFoundationCueStream(
        image: ImageDownsampler.SendableImage,
        classification: VisionSubjectClassification,
        scanId: String = "debug-local-analysis",
        attemptGeneration: UUID = UUID()
    ) {
        cancelLocalVisualAnalysis()
        activeScanId = scanId
        activeLiveInferenceAttemptGeneration = attemptGeneration
        activeForegroundInferenceGeneration = nil
        activePresentationOwner = AnalysisPresentationOwner(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            modality: .visual
        )
        isProcessing = true
        let session = InferenceLocalAnalysisCoordinator.Session(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: nil
        )
        localAnalysisCoordinator.startDebugFoundationCueStream(
            image: image,
            classification: classification,
            session: session,
            isCurrent: { [weak self] session in
                self?.isLocalAnalysisCurrent(session) == true
            },
            publishPhrase: { [weak self] phrase in
                self?.scanningPhaseText = phrase
            }
        )
    }

    @discardableResult
    func debugStartLocalClassification(
        imageData: Data,
        focusRegion: NormalizedImageFocusRegion? = nil,
        scanId: String = "debug-local-classification",
        attemptGeneration: UUID = UUID()
    ) -> Task<Void, Never>? {
        cancelLocalVisualAnalysis()
        activeScanId = scanId
        activeLiveInferenceAttemptGeneration = attemptGeneration
        activeForegroundInferenceGeneration = nil
        activePresentationOwner = AnalysisPresentationOwner(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            modality: .visual
        )
        isProcessing = true
        return classifySubjectLocally(
            from: imageData,
            focusRegion: focusRegion
        )
    }

    @discardableResult
    func debugTransitionProgressiveAnalyzingToQueue(scanId: String) -> Bool {
        let attemptGeneration = activeLiveInferenceAttemptGeneration ?? UUID()
        activeScanId = scanId
        activeLiveInferenceAttemptGeneration = attemptGeneration
        activeForegroundInferenceGeneration = nil
        activePresentationOwner = AnalysisPresentationOwner(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            modality: .visual
        )
        return transitionToQueuedPresentation(
            scanId: scanId,
            source: .active(attemptGeneration: attemptGeneration)
        )
    }

    func debugStartNonVisualPresentation(
        scanId: String,
        phrase: String = "Listening"
    ) -> UUID {
        cancelLocalVisualAnalysis()
        let attemptGeneration = UUID()
        activeScanId = scanId
        activeLiveInferenceAttemptGeneration = attemptGeneration
        activeForegroundInferenceGeneration = nil
        activePresentationOwner = AnalysisPresentationOwner(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            modality: .nonVisual
        )
        isProcessing = true
        scanningPhaseText = phrase
        return attemptGeneration
    }

    func debugSimulateGeminiResponseArrival() {
        cancelLocalVisualAnalysis()
    }

    var debugAcceptedFoundationPhraseCount: Int {
        localAnalysisCoordinator.acceptedFoundationPhraseCount
    }

    func debugWaitForFoundationVisualCueStream() async {
        await localAnalysisCoordinator.waitForFoundationCueStream()
    }

    func debugWaitForLocalVisualTraits() async {
        await localAnalysisCoordinator.waitForTraits()
    }

    var debugLocalVisionCategory: LocalSubjectCategory? {
        localAnalysisCoordinator.localVisionCategory
    }

    var debugLocalVisualAnalysisIsRunning: Bool {
        localAnalysisCoordinator.isRunning
    }

    var debugLocalVisualTraitIsRunning: Bool {
        localAnalysisCoordinator.isTraitExtractionRunning
    }
    #endif

    /// Existing cloud-analysis phrases retained by queued, audio-only, and
    /// Describe flows. Foreground visual local analysis uses the morphology-only
    /// deck owned by `ScanningPhraseCoordinator`.
    nonisolated static var genericScanningPhasePhrases: [String] {
        [
            "Scanning subject...",
            "Analyzing subject morphology",
            "Analyzing biological traits",
            "Analyzing structural patterns",
            "Checking taxonomic data",
            "Checking species records",
            "Checking habitat context",
            "Identifying species..."
        ]
    }

    func markAlternativesExhausted(expectedScanId: String? = nil) {
        guard let scanId = speciesData?.scanId,
              expectedScanId == nil ||
                expectedScanId?.caseInsensitiveCompare(scanId) == .orderedSame else {
            return
        }
        _ = beginIdentificationReviewAction(scanId: scanId)
        speciesData?.alternativesExhausted = true
    }
}

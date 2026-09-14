import Foundation
import Observation
import SwiftData

// MARK: - Inference Engine

/// Stable observable facade for live, recovered, and historical inference.
/// Focused coordinators own execution, lifecycle, and mutable state.
@MainActor
@Observable final class InferenceEngine {
    // MARK: - Pipeline State
    var inferenceTask: Task<Void, Error>? {
        get { liveAttemptCoordinator.task }
        set { liveAttemptCoordinator.replaceTask(newValue) }
    }
    /// The client scan ID passed to `analyze()` — matches the `OfflineQueuedScan.id` for the
    /// same capture. Used by the background offline path to detect when it completes the same
    /// scan and should hydrate the engine instead of leaving `isProcessing = true` forever.
    var activeScanId: String? {
        get { liveAttemptCoordinator.activeScanId }
        set { liveAttemptCoordinator.setActiveScanId(newValue) }
    }
    /// Unique owner of the current foreground pipeline. This is distinct from
    /// `activeScanId` because the same queued scan can be retried or replaced.
    var activeLiveInferenceAttemptGeneration: UUID? {
        get { liveAttemptCoordinator.activeAttemptGeneration }
        set { liveAttemptCoordinator.setActiveAttemptGeneration(newValue) }
    }
    /// Durable generation written on the queued scan-ingestion job. `nil` only
    /// for direct queue-less API uses.
    var activeForegroundInferenceGeneration: UUID? {
        get { liveAttemptCoordinator.activeForegroundGeneration }
        set { liveAttemptCoordinator.setActiveForegroundGeneration(newValue) }
    }
    /// Exact queued scan whose live presentation ended with an ambiguous
    /// response. Retained after the active task's defer clears `activeScanId`
    /// so a later URLSession or status-recovery winner can replace the local
    /// error placeholder without overwriting a newer scan presentation.
    var recoverablePresentationScanId: String? {
        get { liveAttemptCoordinator.recoverablePresentationScanId }
        set { liveAttemptCoordinator.setRecoverablePresentationScanId(newValue) }
    }
    /// Exact durable scan whose live request relinquished foreground ownership
    /// and should now use the queue-aware Insight presentation. Unlike
    /// `recoverablePresentationScanId`, this value is observable because the
    /// visible sheet uses it to bind the matching `OfflineQueuedScan` snapshot.
    var queuedPresentationScanId: String? {
        presentationState.queuedPresentationScanId
    }
    var isProcessing: Bool {
        get { presentationState.isProcessing }
        set { presentationState.setProcessing(newValue) }
    }
    var scanningPhaseText: String {
        get { presentationState.scanningPhaseText }
        set { presentationState.setScanningPhaseText(newValue) }
    }
    var activeMedia: ActiveScanMedia {
        get { presentationState.activeMedia }
        set { presentationState.replaceActiveMedia(newValue) }
    }
    var speciesData: SpeciesData? {
        get { presentationState.speciesData }
        set { presentationState.replaceSpeciesData(newValue) }
    }
    // MARK: - Environmental Telemetry State
    var activeLatitude: Double? {
        presentationState.activeLatitude
    }
    var activeLongitude: Double? {
        presentationState.activeLongitude
    }
    var activeElevation: Double? {
        presentationState.activeElevation
    }
    var activeLocationName: String? {
        presentationState.activeLocationName
    }
    var activeWeatherCondition: String? {
        presentationState.activeWeatherCondition
    }
    var activeTemperatureF: Double? {
        presentationState.activeTemperatureF
    }
    var activeFlashFired: Bool? {
        presentationState.activeFlashFired
    }
    var activeDistanceInMeters: Float? {
        presentationState.activeDistanceInMeters
    }

    /// True while the "enrichment" scope call (habitat, taxonomy, GBIF key) is in flight.
    var isEnrichmentLoading: Bool {
        get { presentationState.isEnrichmentLoading }
        set { presentationState.setEnrichmentLoading(newValue) }
    }
    /// True while the "lookalikes" scope call (similar species cards) is in flight.
    var isLookalikesLoading: Bool {
        get { presentationState.isLookalikesLoading }
        set { presentationState.setLookalikesLoading(newValue) }
    }
    // isReferenceImageLoading has been removed. Use activeMedia.referenceState.
    // MARK: - Focused Owners
    @ObservationIgnored private let presentationLifecycleCoordinator:
        InferencePresentationCoordinator
    @ObservationIgnored private let presentationState:
        InferencePresentationState
    @ObservationIgnored private let sessionLifecycleCoordinator:
        InferenceSessionLifecycleCoordinator
    @ObservationIgnored private let localAnalysisCoordinator:
        InferenceLocalAnalysisCoordinator
    @ObservationIgnored private let liveAttemptCoordinator:
        InferenceLiveAttemptCoordinator
    @ObservationIgnored private let liveSubmissionCoordinator:
        InferenceLiveSubmissionCoordinator
    @ObservationIgnored private let livePipelinePresentationCoordinator:
        InferenceLivePresentationCoordinator
    @ObservationIgnored private let speciesPresentationCoordinator:
        InferenceSpeciesPresentationCoordinator
    @ObservationIgnored private let historicalLoadCoordinator:
        InferenceHistoricalLoadCoordinator
    @ObservationIgnored private let identificationReviewWorkflowCoordinator:
        InferenceReviewWorkflowCoordinator
    @ObservationIgnored private let hydrationCoordinator:
        InferenceHydrationCoordinator
    @ObservationIgnored private let writeCoordinator:
        InferenceWriteCoordinator
    var scanPresentationGeneration: UInt64 { writeCoordinator.generation }

    init(
        visionSubjectClassifier: any VisionSubjectClassifying = AppleVisionSubjectClassifier(),
        localVisualTraitExtractor: any LocalVisualTraitExtracting = AppleImageVisualTraitExtractor(),
        foundationVisualCueProvider: any FoundationVisualCueProviding = UnavailableFoundationVisualCueProvider(),
        foundationVisualCueEligibilityChecker: any FoundationVisualCueEligibilityChecking = SystemFoundationCueEligibility(),
        scanningPhraseSleeper: any ScanningPhraseSleeping = ContinuousScanningPhraseSleeper(),
        localAnalysisStartFeedback: @escaping @MainActor () -> Void = {},
        liveRequestService: InferenceLiveRequestService = .live,
        liveResultService: InferenceLiveResultService = .live,
        liveQueueService: InferenceLiveQueueService? = nil,
        liveCompletionDependencies:
            InferenceLiveCompletionCoordinator.Dependencies? = nil,
        speciesReferenceService: SpeciesReferenceHydrationService = .live,
        speciesEnrichmentService:
            InferenceSpeciesEnrichmentService = .live,
        hydrationPersistenceService:
            InferenceHydrationPersistenceService = .live,
        identificationReviewService:
            InferenceIdentificationReviewService = .live,
        identificationReviewSnapshotService:
            InferenceReviewSnapshotService = .live,
        identificationReviewDependencies:
            InferenceIdentificationReviewCoordinator.Dependencies? = nil,
        hydrationCoordinator: InferenceHydrationCoordinator? = nil,
        requestPaywall: (@MainActor () -> Void)? = nil,
        liveFailureDependencies:
            InferenceLiveFailureCoordinator.Dependencies? = nil,
        livePipelineDependencies:
            InferenceLivePipelineCoordinator.Dependencies = .live,
        speciesHydrationDependencies:
            InferenceSpeciesHydrationCoordinator.Dependencies = .live,
        lookalikeCacheResetService:
            InferenceLookalikeCacheResetService = .live,
        liveMediaProjector: InferenceLiveMediaProjector = .live
    ) {
        let assembly = InferenceEngineAssembly(
            dependencies: .init(
                visionSubjectClassifier: visionSubjectClassifier,
                localVisualTraitExtractor: localVisualTraitExtractor,
                foundationVisualCueProvider:
                    foundationVisualCueProvider,
                foundationVisualCueEligibilityChecker:
                    foundationVisualCueEligibilityChecker,
                scanningPhraseSleeper: scanningPhraseSleeper,
                localAnalysisStartFeedback: localAnalysisStartFeedback,
                liveRequestService: liveRequestService,
                liveResultService: liveResultService,
                liveQueueService: liveQueueService,
                liveCompletionDependencies: liveCompletionDependencies,
                speciesReferenceService: speciesReferenceService,
                speciesEnrichmentService: speciesEnrichmentService,
                hydrationPersistenceService: hydrationPersistenceService,
                identificationReviewService: identificationReviewService,
                identificationReviewSnapshotService:
                    identificationReviewSnapshotService,
                identificationReviewDependencies:
                    identificationReviewDependencies,
                hydrationCoordinator: hydrationCoordinator,
                requestPaywall: requestPaywall,
                liveFailureDependencies: liveFailureDependencies,
                livePipelineDependencies: livePipelineDependencies,
                speciesHydrationDependencies:
                    speciesHydrationDependencies,
                lookalikeCacheResetService: lookalikeCacheResetService,
                liveMediaProjector: liveMediaProjector
            )
        )
        self.presentationLifecycleCoordinator =
            assembly.presentationLifecycleCoordinator
        self.presentationState = assembly.presentationState
        self.sessionLifecycleCoordinator =
            assembly.sessionLifecycleCoordinator
        self.localAnalysisCoordinator = assembly.localAnalysisCoordinator
        self.liveAttemptCoordinator = assembly.liveAttemptCoordinator
        self.liveSubmissionCoordinator = assembly.liveSubmissionCoordinator
        self.livePipelinePresentationCoordinator =
            assembly.livePipelinePresentationCoordinator
        self.speciesPresentationCoordinator =
            assembly.speciesPresentationCoordinator
        self.historicalLoadCoordinator = assembly.historicalLoadCoordinator
        self.identificationReviewWorkflowCoordinator =
            assembly.identificationReviewWorkflowCoordinator
        self.hydrationCoordinator = assembly.hydrationCoordinator
        self.writeCoordinator = assembly.writeCoordinator
    }

    #if DEBUG
    /// The only DEBUG cross-file seam. The returned value is ephemeral and
    /// exposes operations rather than the facade's private owner references.
    func makeDebugSupport() -> InferenceEngineDebugSupport {
        InferenceEngineDebugSupport(
            presentationLifecycleCoordinator:
                presentationLifecycleCoordinator,
            presentationState: presentationState,
            sessionLifecycleCoordinator: sessionLifecycleCoordinator,
            localAnalysisCoordinator: localAnalysisCoordinator,
            liveAttemptCoordinator: liveAttemptCoordinator,
            liveSubmissionCoordinator: liveSubmissionCoordinator,
            writeCoordinator: writeCoordinator
        )
    }
    #endif

    /// Synchronously closes new presentation writes at Auth-transition
    /// admission and cancels every existing producer. Ephemeral local visual
    /// work is fenced and released here; only durable write owners participate
    /// in the async quiescence drain.
    func beginAuthTransitionWriteFence() {
        sessionLifecycleCoordinator.beginAuthTransition()
    }

    func awaitAuthTransitionWriteQuiescence() async {
        await sessionLifecycleCoordinator.awaitAuthTransitionQuiescence()
    }

    func finishAuthTransitionWriteFence() {
        sessionLifecycleCoordinator.finishAuthTransition()
    }

    // MARK: - Live Inference Pipeline

    /// Resets display state before the Insight sheet opens so its first frame
    /// presents the upcoming scan rather than a previous result.
    func prepareForNewScan(
        scanId: String? = nil,
        attemptGeneration: UUID? = nil,
        modality: ScanPresentationModality = .visual
    ) {
        sessionLifecycleCoordinator.prepareForNewScan(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            modality: modality.presentationValue
        )
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
        livePipelinePresentationCoordinator.commitSuccessfulResult(
            for: ownedScanId,
            attemptGeneration: attemptGeneration,
            foregroundInferenceGeneration: foregroundInferenceGeneration,
            speciesData: speciesData,
            persistedMediaItems: persistedMediaItems
        )
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
        sessionLifecycleCoordinator.commitRecoveredBackgroundResult(
            for: scanId,
            replacingAttemptGeneration: replacingAttemptGeneration,
            expectedForegroundGeneration: expectedForegroundGeneration,
            speciesData: speciesData
        )
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
        sessionLifecycleCoordinator.commitRecoveredQueuedResult(
            for: scanId,
            speciesData: speciesData
        )
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
        sessionLifecycleCoordinator.commitRecoveredQueuedRecord(
            for: scanId,
            recordScanId: record.id
        ) { [self] in
            load(from: record)
        }
    }

    /// Starts a live visual submission. The focused submission coordinator owns
    /// admission, media projection, execution, persistence, and hydration.
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
        liveSubmissionCoordinator.startVisual(
            InferenceLiveSubmissionCoordinator.VisualSubmission(
                scanId: scanId,
                foregroundInferenceGeneration:
                    foregroundInferenceGeneration,
                imageDatas: imageDatas,
                displayDatas: displayDatas,
                audioFilePaths: audioFilePaths,
                videoFilePaths: videoFilePaths,
                telemetry: telemetry,
                observationContexts: observationContexts,
                mediaTimeline: mediaTimeline,
                visualMediaItems: visualMediaItems,
                preferredGoal: preferredGoal,
                modelContext: modelContext,
                targetEradicationScanId: targetEradicationScanId,
                userPerceivedStart: userPerceivedStart
            )
        )
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
        liveSubmissionCoordinator.startNonVisual(
            InferenceLiveSubmissionCoordinator.NonVisualSubmission(
                scanId: scanId,
                foregroundInferenceGeneration:
                    foregroundInferenceGeneration,
                audioFilePaths: audioFilePaths,
                videoFilePaths: videoFilePaths,
                observationContexts: observationContexts,
                mediaTimeline: mediaTimeline,
                telemetry: telemetry,
                modelContext: modelContext,
                targetEradicationScanId: targetEradicationScanId,
                userPerceivedStart: userPerceivedStart
            )
        )
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
        return sessionLifecycleCoordinator.transitionToQueue(
            scanId: scanId,
            source: source.presentationValue,
            activeVisualPhrases: localAnalysisCoordinator.handoffPhraseDeck
        )
    }

    /// Returns visual copy only for the exact queued presentation that inherited
    /// a prepared or active visual scan. Values remain process-local and
    /// ephemeral.
    func liveQueueHandoffScanningPhrases(for scanId: String) -> [String] {
        presentationLifecycleCoordinator.scanningPhrases(for: scanId)
    }

    func hasLiveVisualQueueHandoff(for scanId: String) -> Bool {
        presentationLifecycleCoordinator.hasVisualQueueHandoff(for: scanId)
    }

    func hasLiveQueueHandoffMedia(for scanId: String) -> Bool {
        presentationLifecycleCoordinator.hasLiveMedia(for: scanId)
    }

    // MARK: - Species Enrichment

    /// Fetches independently requested metadata and lookalike scopes for the
    /// exact current species presentation.
    func fetchAndApplyEnrichment(
        modelContext: ModelContext?,
        needsMetadata: Bool = true,
        needsLookalikes: Bool = true,
        allowLookalikesRetry: Bool = true,
        reviewActionGeneration: UInt64? = nil
    ) async {
        await speciesPresentationCoordinator.fetchAndApplyEnrichment(
            .init(
                modelContainer: modelContext?.container,
                needsMetadata: needsMetadata,
                needsLookalikes: needsLookalikes,
                allowLookalikesRetry: allowLookalikesRetry,
                reviewActionGeneration: reviewActionGeneration
            )
        )
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
        await identificationReviewWorkflowCoordinator.applyOverride(
            .init(
                scientificName: scientificName,
                expectedScanID: expectedScanId,
                modelContainer: modelContext?.container
            ),
            callbacks: speciesPresentationCoordinator
                .makeReviewWorkflowCallbacks()
        )
    }

    /// Called when the user confirms the AI's primary identification ("Yes, correct").
    /// Persists locally and syncs confirmation to the cloud scan record.
    func confirmAIIdentification(
        expectedScanId: String? = nil,
        modelContext: ModelContext?
    ) async {
        await identificationReviewWorkflowCoordinator.confirm(
            .init(
                expectedScanID: expectedScanId,
                modelContext: modelContext
            ),
            callbacks: speciesPresentationCoordinator
                .makeReviewWorkflowCallbacks()
        )
    }

    /// Resets all identification review state, reverting the scan back to the AI's original
    /// identification. Called by Undo (from `.overridden`) and Change (from `.confirmed`).
    /// Clears both `userIdentificationOverride` and `userConfirmedIdentification` locally,
    /// syncs both columns to null/false in the cloud, and re-hydrates the AI species data.
    func resetIdentificationReview(
        expectedScanId: String? = nil,
        modelContext: ModelContext?
    ) async {
        await identificationReviewWorkflowCoordinator.reset(
            .init(
                expectedScanID: expectedScanId,
                modelContext: modelContext
            ),
            callbacks: speciesPresentationCoordinator
                .makeReviewWorkflowCallbacks()
        )
    }

    // MARK: - Pipeline Modifiers

    /// Ends only presentation-owned local analysis. Durable inference, queue
    /// recovery, persistence, and result publication continue independently.
    /// Clearing the owners before cancellation fences even non-cooperative local
    /// providers from publishing after the sheet has gone away.
    func dismissAnalyzingPresentation() {
        sessionLifecycleCoordinator.dismissAnalyzingPresentation()
    }

    /// Cancels all in-flight work and resets the engine to idle.
    ///
    /// Contrast with `prepareForNewScan()`, which also cancels in-flight work but leaves
    /// `isProcessing = true` in anticipation of an *upcoming* scan. `cancelActiveRequest`
    /// resets to `isProcessing = false, speciesData = nil` — appropriate when the user
    /// dismisses the insight sheet with no new scan queued.
    func cancelActiveRequest(isUserInitiated: Bool = false) {
        sessionLifecycleCoordinator.cancelActiveRequest(
            isUserInitiated: isUserInitiated
        )
    }

    /// Called by the Insight sheet's one-shot UIKit draw probe. Unlike a task
    /// yield, `draw(_:)` only fires when the result view participates in a real
    /// display pass, so this closes the user-perceived latency interval at the
    /// first rendered frame rather than at state assignment.
    func recordFirstRenderedFrame(scanId: String) {
        liveSubmissionCoordinator.recordFirstRenderedFrame(scanId: scanId)
    }

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
    /// The historical-load coordinator first projects the record into value-
    /// only state on `@MainActor`. Deferred decoding and network hydration then
    /// run inside the hydration coordinator's single current historic slot.
    /// Replacing that slot fences stale state and effects immediately; a
    /// synchronous decoder already in progress can finish before it observes
    /// cancellation.
    func load(from record: LocalScanRecord) {
        historicalLoadCoordinator.load(from: record)
    }

    func handleApplicationActiveStateChange(isActive: Bool) {
        sessionLifecycleCoordinator.handleApplicationActiveStateChange(
            isActive: isActive
        )
    }

    func markAlternativesExhausted(expectedScanId: String? = nil) {
        speciesPresentationCoordinator.markAlternativesExhausted(
            expectedScanId: expectedScanId
        )
    }
}

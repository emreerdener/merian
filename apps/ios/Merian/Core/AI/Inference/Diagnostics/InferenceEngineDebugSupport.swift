import Foundation

#if DEBUG
/// Coordinates deterministic simulator and test-only inference scenarios.
///
/// This ephemeral value receives exact focused-owner references from
/// `InferenceEngine` and stores no state of its own. It is absent from Release
/// builds and does not create an alternate production inference path.
@MainActor
struct InferenceEngineDebugSupport {
    struct BackgroundWriteState: Sendable {
        let active: Int
        let pending: Int
        let generation: UInt64
    }

    private let presentationLifecycleCoordinator:
        InferencePresentationCoordinator
    private let presentationState: InferencePresentationState
    private let sessionLifecycleCoordinator:
        InferenceSessionLifecycleCoordinator
    private let localAnalysisCoordinator: InferenceLocalAnalysisCoordinator
    private let liveAttemptCoordinator: InferenceLiveAttemptCoordinator
    private let liveSubmissionCoordinator: InferenceLiveSubmissionCoordinator
    private let writeCoordinator: InferenceWriteCoordinator

    init(
        presentationLifecycleCoordinator:
            InferencePresentationCoordinator,
        presentationState: InferencePresentationState,
        sessionLifecycleCoordinator:
            InferenceSessionLifecycleCoordinator,
        localAnalysisCoordinator: InferenceLocalAnalysisCoordinator,
        liveAttemptCoordinator: InferenceLiveAttemptCoordinator,
        liveSubmissionCoordinator: InferenceLiveSubmissionCoordinator,
        writeCoordinator: InferenceWriteCoordinator
    ) {
        self.presentationLifecycleCoordinator =
            presentationLifecycleCoordinator
        self.presentationState = presentationState
        self.sessionLifecycleCoordinator = sessionLifecycleCoordinator
        self.localAnalysisCoordinator = localAnalysisCoordinator
        self.liveAttemptCoordinator = liveAttemptCoordinator
        self.liveSubmissionCoordinator = liveSubmissionCoordinator
        self.writeCoordinator = writeCoordinator
    }

    var backgroundWriteTaskCap: Int {
        writeCoordinator.activeTaskCapacity
    }

    var pendingBackgroundWriteTaskCap: Int {
        writeCoordinator.pendingTaskCapacity
    }

    var backgroundWriteState: BackgroundWriteState {
        let snapshot = writeCoordinator.snapshot
        return BackgroundWriteState(
            active: snapshot.active,
            pending: snapshot.pending,
            generation: snapshot.generation
        )
    }

    func enqueueTrackedBackgroundTask(
        _ operation: @escaping @Sendable () async -> Void
    ) {
        writeCoordinator.enqueueBackgroundWrite(operation)
    }

    func simulateProgressiveAnalyzing(
        automaticallyAdvances: Bool,
        scanId: String
    ) {
        localAnalysisCoordinator.cancel()
        let attemptGeneration = UUID()
        liveAttemptCoordinator.activate(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: nil
        )
        presentationLifecycleCoordinator.activate(
            scanId: liveAttemptCoordinator.activeScanId,
            attemptGeneration: attemptGeneration,
            modality: .visual
        )
        presentationState.setProcessing(true)
        let session = InferenceLocalAnalysisCoordinator.Session(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: nil
        )
        localAnalysisCoordinator.startDebugProgression(
            session: session,
            automaticallyAdvances: automaticallyAdvances,
            isCurrent: { [weak liveSubmissionCoordinator] session in
                liveSubmissionCoordinator?
                    .debugIsLocalAnalysisCurrent(session) == true
            },
            publishPhrase: { [weak presentationState] phrase in
                presentationState?.setScanningPhaseText(phrase)
            }
        )
    }

    func advanceProgressiveAnalyzing() {
        localAnalysisCoordinator.advanceDebugProgression()
    }

    func startFoundationCueStream(
        image: ImageDownsampler.SendableImage,
        classification: VisionSubjectClassification,
        scanId: String,
        attemptGeneration: UUID
    ) {
        localAnalysisCoordinator.cancel()
        liveAttemptCoordinator.activate(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: nil
        )
        presentationLifecycleCoordinator.activate(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            modality: .visual
        )
        presentationState.setProcessing(true)
        let session = InferenceLocalAnalysisCoordinator.Session(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: nil
        )
        localAnalysisCoordinator.startDebugFoundationCueStream(
            image: image,
            classification: classification,
            session: session,
            isCurrent: { [weak liveSubmissionCoordinator] session in
                liveSubmissionCoordinator?
                    .debugIsLocalAnalysisCurrent(session) == true
            },
            publishPhrase: { [weak presentationState] phrase in
                presentationState?.setScanningPhaseText(phrase)
            }
        )
    }

    @discardableResult
    func startLocalClassification(
        imageData: Data,
        focusRegion: NormalizedImageFocusRegion?,
        scanId: String,
        attemptGeneration: UUID
    ) -> Task<Void, Never>? {
        localAnalysisCoordinator.cancel()
        liveAttemptCoordinator.activate(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: nil
        )
        presentationLifecycleCoordinator.activate(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            modality: .visual
        )
        presentationState.setProcessing(true)
        return liveSubmissionCoordinator.debugStartLocalClassification(
            from: imageData,
            focusRegion: focusRegion
        )
    }

    func transitionProgressiveAnalyzingToQueue(scanId: String) -> Bool {
        let attemptGeneration =
            liveAttemptCoordinator.activeAttemptGeneration ?? UUID()
        liveAttemptCoordinator.activate(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: nil
        )
        presentationLifecycleCoordinator.activate(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            modality: .visual
        )
        return sessionLifecycleCoordinator.transitionToQueue(
            scanId: scanId,
            source: .active(attemptGeneration: attemptGeneration),
            activeVisualPhrases: localAnalysisCoordinator.handoffPhraseDeck
        )
    }

    func startNonVisualPresentation(
        scanId: String,
        phrase: String
    ) -> UUID {
        localAnalysisCoordinator.cancel()
        let attemptGeneration = UUID()
        liveAttemptCoordinator.activate(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: nil
        )
        presentationLifecycleCoordinator.activate(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            modality: .nonVisual
        )
        presentationState.setProcessing(true)
        presentationState.setScanningPhaseText(phrase)
        return attemptGeneration
    }

    func simulateGeminiResponseArrival() {
        localAnalysisCoordinator.cancel()
    }

    var acceptedFoundationPhraseCount: Int {
        localAnalysisCoordinator.acceptedFoundationPhraseCount
    }

    func waitForFoundationVisualCueStream() async {
        await localAnalysisCoordinator.waitForFoundationCueStream()
    }

    func waitForLocalVisualTraits() async {
        await localAnalysisCoordinator.waitForTraits()
    }

    var localVisionCategory: LocalSubjectCategory? {
        localAnalysisCoordinator.localVisionCategory
    }

    var localVisualAnalysisIsRunning: Bool {
        localAnalysisCoordinator.isRunning
    }

    var localVisualTraitIsRunning: Bool {
        localAnalysisCoordinator.isTraitExtractionRunning
    }
}
#endif

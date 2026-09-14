import Foundation

#if DEBUG
extension InferenceEngine {
    struct DebugBackgroundWriteState: Sendable {
        let active: Int
        let pending: Int
        let generation: UInt64
    }

    var debugBackgroundWriteTaskCap: Int {
        makeDebugSupport().backgroundWriteTaskCap
    }

    var debugPendingBackgroundWriteTaskCap: Int {
        makeDebugSupport().pendingBackgroundWriteTaskCap
    }

    func debugBackgroundWriteState() -> DebugBackgroundWriteState {
        let snapshot = makeDebugSupport().backgroundWriteState
        return DebugBackgroundWriteState(
            active: snapshot.active,
            pending: snapshot.pending,
            generation: snapshot.generation
        )
    }

    func debugEnqueueTrackedBackgroundTask(
        _ operation: @escaping @Sendable () async -> Void
    ) {
        makeDebugSupport().enqueueTrackedBackgroundTask(operation)
    }

    /// Deterministic generic → category → trait progression for UI
    /// development and the analyzing-pill UI contract test.
    func simulateProgressiveAnalyzing(
        automaticallyAdvances: Bool = true,
        scanId: String = "debug-progressive-analysis"
    ) {
        makeDebugSupport().simulateProgressiveAnalyzing(
            automaticallyAdvances: automaticallyAdvances,
            scanId: scanId
        )
    }

    func debugAdvanceProgressiveAnalyzing() {
        makeDebugSupport().advanceProgressiveAnalyzing()
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
        makeDebugSupport().startFoundationCueStream(
            image: image,
            classification: classification,
            scanId: scanId,
            attemptGeneration: attemptGeneration
        )
    }

    @discardableResult
    func debugStartLocalClassification(
        imageData: Data,
        focusRegion: NormalizedImageFocusRegion? = nil,
        scanId: String = "debug-local-classification",
        attemptGeneration: UUID = UUID()
    ) -> Task<Void, Never>? {
        makeDebugSupport().startLocalClassification(
            imageData: imageData,
            focusRegion: focusRegion,
            scanId: scanId,
            attemptGeneration: attemptGeneration
        )
    }

    @discardableResult
    func debugTransitionProgressiveAnalyzingToQueue(scanId: String) -> Bool {
        makeDebugSupport().transitionProgressiveAnalyzingToQueue(scanId: scanId)
    }

    func debugStartNonVisualPresentation(
        scanId: String,
        phrase: String = "Listening"
    ) -> UUID {
        makeDebugSupport().startNonVisualPresentation(
            scanId: scanId,
            phrase: phrase
        )
    }

    func debugSimulateGeminiResponseArrival() {
        makeDebugSupport().simulateGeminiResponseArrival()
    }

    var debugAcceptedFoundationPhraseCount: Int {
        makeDebugSupport().acceptedFoundationPhraseCount
    }

    func debugWaitForFoundationVisualCueStream() async {
        await makeDebugSupport().waitForFoundationVisualCueStream()
    }

    func debugWaitForLocalVisualTraits() async {
        await makeDebugSupport().waitForLocalVisualTraits()
    }

    var debugLocalVisionCategory: LocalSubjectCategory? {
        makeDebugSupport().localVisionCategory
    }

    var debugLocalVisualAnalysisIsRunning: Bool {
        makeDebugSupport().localVisualAnalysisIsRunning
    }

    var debugLocalVisualTraitIsRunning: Bool {
        makeDebugSupport().localVisualTraitIsRunning
    }
}
#endif

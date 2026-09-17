import Foundation

@testable import Merian

@MainActor
final class InferenceSessionLifecycleQueueHarness {
    enum Event: Equatable {
        case release(String, UUID?, String)
        case retire(String, UUID, Bool, String)
    }

    private(set) var events: [Event] = []
    var onRelease: (@MainActor () -> Void)?

    var service: InferenceLiveQueueService {
        InferenceLiveQueueService(dependencies: .init(
            releaseDeferredUpload: { [self] scanId, generation, reason in
                onRelease?()
                events.append(.release(scanId, generation, reason))
            },
            retireForegroundInference: { [self] scanId, generation, resume, reason in
                events.append(.retire(scanId, generation, resume, reason))
            },
            claimForegroundInferenceStart: { _, _ in true },
            isForegroundInferenceAttemptCurrent: { _, _ in true },
            foregroundInferenceGeneration: { _ in nil },
            deleteQueuedScan: { _, _, _ in true },
            rejectQueuedScan: { _, _, _ in true }
        ))
    }
}

private struct InferenceSessionLifecycleClassifier: VisionSubjectClassifying {
    func classify(
        image _: ImageDownsampler.SendableImage
    ) async throws -> VisionSubjectClassification {
        VisionSubjectClassification(category: nil, candidates: [])
    }
}

private struct InferenceSessionLifecycleTraitExtractor: LocalVisualTraitExtracting {
    func extractCues(
        from _: ImageDownsampler.SendableImage
    ) async -> [FoundationVisualCue] {
        []
    }
}

private struct InferenceSessionLifecycleCueProvider: FoundationVisualCueProviding {
    func cueSnapshots(
        for _: FoundationVisualCueRequest
    ) async throws -> FoundationVisualCueStream? {
        nil
    }
}

private struct InferenceSessionLifecycleEligibility:
    FoundationVisualCueEligibilityChecking {
    @MainActor
    func isEligibleForVisualCues() -> Bool { false }
}

private struct InferenceSessionLifecycleSleeper: ScanningPhraseSleeping {
    func sleepUntilNextPhrase() async throws {
        throw CancellationError()
    }
}

@MainActor
final class InferenceSessionLifecycleHarness {
    let queue: InferenceSessionLifecycleQueueHarness
    let attempt: InferenceLiveAttemptCoordinator
    let hydration: InferenceHydrationCoordinator
    let writes: InferenceWriteCoordinator
    let localAnalysis: InferenceLocalAnalysisCoordinator
    let presentation: InferencePresentationCoordinator
    let state: InferencePresentationState
    let coordinator: InferenceSessionLifecycleCoordinator

    init() {
        let queue = InferenceSessionLifecycleQueueHarness()
        self.queue = queue
        let attempt = InferenceLiveAttemptCoordinator(
            queueService: queue.service
        )
        self.attempt = attempt
        let hydration = InferenceHydrationCoordinator(
            dependencies: .init(
                now: { Date(timeIntervalSinceReferenceDate: 1_000) },
                loadEnrichedSpeciesTimestamps: { [:] },
                persistEnrichedSpeciesTimestamps: { _ in }
            )
        )
        self.hydration = hydration
        let writes = InferenceWriteCoordinator()
        self.writes = writes
        let localAnalysis = InferenceLocalAnalysisCoordinator(
            dependencies: .init(
                classifier: InferenceSessionLifecycleClassifier(),
                traitExtractor: InferenceSessionLifecycleTraitExtractor(),
                foundationCueProvider: InferenceSessionLifecycleCueProvider(),
                foundationCueEligibilityChecker:
                    InferenceSessionLifecycleEligibility(),
                phraseSleeper: InferenceSessionLifecycleSleeper(),
                startFeedback: {}
            )
        )
        self.localAnalysis = localAnalysis
        let presentation = InferencePresentationCoordinator()
        self.presentation = presentation
        let state = InferencePresentationState()
        self.state = state
        self.coordinator = InferenceSessionLifecycleCoordinator(
            attemptCoordinator: attempt,
            hydrationCoordinator: hydration,
            writeCoordinator: writes,
            localAnalysisCoordinator: localAnalysis,
            presentationCoordinator: presentation,
            presentationState: state
        )
    }
}

func inferenceSessionLifecycleSpeciesData(
    scanId: String,
    commonName: String = "Monarch"
) -> SpeciesData {
    SpeciesData(
        scanId: scanId,
        commonName: commonName,
        scientificName: "Danaus plexippus",
        insightData: InsightData(
            aiReasoning: "Orange wings",
            hazardType: "none"
        ),
        confidenceScore: 0.94,
        isBiological: true,
        isLiveCapture: true,
        isInvasive: false,
        ecologyType: "terrestrial",
        aiScientificName: "Danaus plexippus"
    )
}

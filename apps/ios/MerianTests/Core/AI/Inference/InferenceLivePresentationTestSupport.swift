import Foundation
import SwiftData

@testable import Merian

struct LivePipelinePresentationClassifier: VisionSubjectClassifying {
    func classify(
        image _: ImageDownsampler.SendableImage
    ) async throws -> VisionSubjectClassification {
        VisionSubjectClassification(category: nil, candidates: [])
    }
}

struct LivePipelinePresentationTraitExtractor: LocalVisualTraitExtracting {
    func extractCues(
        from _: ImageDownsampler.SendableImage
    ) async -> [FoundationVisualCue] {
        []
    }
}

struct LivePipelinePresentationCueProvider: FoundationVisualCueProviding {
    func cueSnapshots(
        for _: FoundationVisualCueRequest
    ) async throws -> FoundationVisualCueStream? {
        nil
    }
}

struct LivePipelinePresentationEligibility:
    FoundationVisualCueEligibilityChecking {
    @MainActor
    func isEligibleForVisualCues() -> Bool { false }
}

struct LivePipelinePresentationEligible:
    FoundationVisualCueEligibilityChecking {
    @MainActor
    func isEligibleForVisualCues() -> Bool { true }
}

struct LivePipelinePresentationSleeper: ScanningPhraseSleeping {
    func sleepUntilNextPhrase() async throws {
        throw CancellationError()
    }
}

actor LivePipelinePresentationCueRecorder: FoundationVisualCueProviding {
    private var requestCount = 0

    func cueSnapshots(
        for _: FoundationVisualCueRequest
    ) async throws -> FoundationVisualCueStream? {
        requestCount += 1
        return nil
    }

    func count() -> Int {
        requestCount
    }

    func waitUntilRequested() async {
        while requestCount == 0 {
            await Task.yield()
        }
    }
}

actor LivePipelinePresentationHydrationGate {
    private var started = false
    private var released = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuations:
        [CheckedContinuation<Void, Never>] = []

    func wait() async {
        started = true
        startContinuation?.resume()
        startContinuation = nil
        guard !released else { return }
        await withCheckedContinuation { continuation in
            releaseContinuations.append(continuation)
        }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startContinuation = $0 }
    }

    func release() {
        released = true
        let continuations = releaseContinuations
        releaseContinuations = []
        continuations.forEach { $0.resume() }
    }
}

@MainActor
final class LivePresentationPersistenceRecorder {
    private(set) var metadataContainers: [ObjectIdentifier] = []

    func recordMetadataContainer(_ container: ModelContainer) {
        metadataContainers.append(ObjectIdentifier(container))
    }
}

@MainActor
final class LivePipelinePresentationEventRecorder {
    enum Event: Equatable {
        case foregroundCompletion(String, observedPublishedResult: Bool)
    }

    private(set) var events: [Event] = []
    private let state: InferencePresentationState

    init(state: InferencePresentationState) {
        self.state = state
    }

    func record(_ event: AppEvent) {
        guard case let .foregroundBiologicalScanCompleted(scanId) =
            event else { return }
        events.append(.foregroundCompletion(
            scanId,
            observedPublishedResult:
                state.speciesData?.scanId == scanId
                    && state.isProcessing == false
        ))
    }
}

@MainActor
final class LivePipelinePresentationQueueRecorder {
    enum Event: Equatable {
        case release(String, UUID?, String)
        case retire(String, UUID, Bool, String)
    }

    private(set) var events: [Event] = []

    func recordRelease(
        scanId: String,
        generation: UUID?,
        reason: String
    ) {
        events.append(.release(scanId, generation, reason))
    }

    func recordRetirement(
        scanId: String,
        generation: UUID,
        resumeBackground: Bool,
        reason: String
    ) {
        events.append(
            .retire(scanId, generation, resumeBackground, reason)
        )
    }
}

@MainActor
final class LivePipelinePresentationHarness {
    typealias Event = LivePipelinePresentationEventRecorder.Event
    typealias QueueEvent = LivePipelinePresentationQueueRecorder.Event

    var events: [Event] { eventRecorder.events }
    var queueEvents: [QueueEvent] { queueRecorder.events }
    let attempt: InferenceLiveAttemptCoordinator
    let state: InferencePresentationState
    let presentation: InferencePresentationCoordinator
    let localAnalysis: InferenceLocalAnalysisCoordinator
    let hydrationTasks: InferenceHydrationCoordinator
    let writes: InferenceWriteCoordinator
    let lifecycle: InferenceSessionLifecycleCoordinator
    let subject: InferenceLivePresentationCoordinator
    private let eventRecorder: LivePipelinePresentationEventRecorder
    private let queueRecorder: LivePipelinePresentationQueueRecorder

    init(
        foundationCueProvider: any FoundationVisualCueProviding =
            LivePipelinePresentationCueProvider(),
        foundationCueEligibilityChecker:
            any FoundationVisualCueEligibilityChecking =
                LivePipelinePresentationEligibility(),
        enrichmentService: InferenceSpeciesEnrichmentService? = nil,
        persistenceService: InferenceHydrationPersistenceService? = nil
    ) {
        let queueRecorder = LivePipelinePresentationQueueRecorder()
        self.queueRecorder = queueRecorder
        let queueService = InferenceLiveQueueService(dependencies: .init(
            releaseDeferredUpload: { [queueRecorder] scanId, generation, reason in
                queueRecorder.recordRelease(
                    scanId: scanId,
                    generation: generation,
                    reason: reason
                )
            },
            retireForegroundInference: { [queueRecorder] scanId, generation, resume, reason in
                queueRecorder.recordRetirement(
                    scanId: scanId,
                    generation: generation,
                    resumeBackground: resume,
                    reason: reason
                )
            },
            claimForegroundInferenceStart: { _, _ in true },
            isForegroundInferenceAttemptCurrent: { _, _ in true },
            foregroundInferenceGeneration: { _ in nil },
            deleteQueuedScan: { _, _, _ in true },
            rejectQueuedScan: { _, _, _ in true }
        ))
        let attempt = InferenceLiveAttemptCoordinator(
            queueService: queueService
        )
        self.attempt = attempt

        let hydrationTasks = InferenceHydrationCoordinator(
            dependencies: .init(
                now: { Date(timeIntervalSinceReferenceDate: 1_000) },
                loadEnrichedSpeciesTimestamps: { [:] },
                persistEnrichedSpeciesTimestamps: { _ in }
            )
        )
        self.hydrationTasks = hydrationTasks
        let writes = InferenceWriteCoordinator()
        self.writes = writes
        let localAnalysis = InferenceLocalAnalysisCoordinator(
            dependencies: .init(
                classifier: LivePipelinePresentationClassifier(),
                traitExtractor: LivePipelinePresentationTraitExtractor(),
                foundationCueProvider: foundationCueProvider,
                foundationCueEligibilityChecker:
                    foundationCueEligibilityChecker,
                phraseSleeper: LivePipelinePresentationSleeper(),
                startFeedback: {}
            )
        )
        self.localAnalysis = localAnalysis
        let presentation = InferencePresentationCoordinator()
        self.presentation = presentation
        let state = InferencePresentationState()
        self.state = state
        let eventRecorder = LivePipelinePresentationEventRecorder(state: state)
        self.eventRecorder = eventRecorder
        let lifecycle = InferenceSessionLifecycleCoordinator(
            attemptCoordinator: attempt,
            hydrationCoordinator: hydrationTasks,
            writeCoordinator: writes,
            localAnalysisCoordinator: localAnalysis,
            presentationCoordinator: presentation,
            presentationState: state
        )
        self.lifecycle = lifecycle

        let review = InferenceIdentificationReviewCoordinator(
            writeCoordinator: writes,
            reviewService: InferenceIdentificationReviewService(
                loadSpecies: { _ in nil },
                loadSpeciesID: { _ in nil },
                syncReview: { _ in }
            ),
            snapshotService: InferenceReviewSnapshotService { _, _ in nil },
            dependencies: .init(
                beginOverride: { _, _, _ in },
                persistReview: { _, _ in },
                clearFlag: { _, _ in },
                persistSpeciesPatch: { _, _, _ in },
                sharedPostID: { _ in nil },
                sendPostRefresh: { _ in },
                processIdentificationUpdate: { _ in },
                logSnapshotFailure: { _, _, _ in },
                logSpeciesLookupFailure: { _ in },
                logSyncFailure: { _ in }
            )
        )
        let speciesHydration = InferenceSpeciesHydrationCoordinator(
            taskCoordinator: hydrationTasks,
            referenceService: SpeciesReferenceHydrationService { request in
                guard let url = request.url,
                      let response = HTTPURLResponse(
                          url: url,
                          statusCode: 404,
                          httpVersion: nil,
                          headerFields: nil
                      ) else {
                    throw URLError(.badURL)
                }
                return (Data(), response)
            },
            enrichmentService: enrichmentService
                ?? InferenceSpeciesEnrichmentService(
                dependencies: .init { _, _ in
                    EnrichScanResponse(success: true, data: nil)
                }
            ),
            persistenceService: persistenceService
                ?? InferenceHydrationPersistenceService(
                dependencies: .init(
                    persistReference: { _, _ in },
                    persistMetadata: { _, _ in },
                    persistLookalikes: { _, _ in }
                )
            ),
            dependencies: .init(
                logWikipediaResponse: { _ in },
                logWikipediaApplied: { _ in },
                logGBIFResponse: { _ in },
                logFailure: { _, _ in }
            )
        )
        let speciesPresentation =
            InferenceSpeciesPresentationCoordinator(
                presentationState: state,
                writeCoordinator: writes,
                reviewCoordinator: review,
                speciesHydrationCoordinator: speciesHydration
            )
        let completion = InferenceLiveCompletionCoordinator(
            attemptCoordinator: attempt,
            dependencies: .init(
                recordNewSpeciesDiscovered: {},
                transferReplacementMetadataAndDeleteOriginal: { _, _, _ in },
                recordCircuitSuccess: {},
                trackCompletedScan: { _, _ in },
                sendEvent: { [eventRecorder] event in
                    eventRecorder.record(event)
                },
                notificationsEnabled: { false },
                sendInferenceCompleteNotification: { _, _ in },
                scheduleMilestoneProcessing: { _, _, _ in },
                commitFundingSettlement: { _ in true }
            )
        )
        subject = InferenceLivePresentationCoordinator(
            attemptCoordinator: attempt,
            sessionLifecycleCoordinator: lifecycle,
            presentationState: state,
            speciesPresentationCoordinator: speciesPresentation,
            completionCoordinator: completion,
            localAnalysisCoordinator: localAnalysis
        )
    }

    func callbacks(
        for session: InferenceLivePipelineCoordinator.Session,
        persistedMediaItems:
            @escaping @MainActor ([String]) -> [MediaItem]? = { paths in
                paths.map { .image("persisted-\($0)") }
            },
        modelContainer: ModelContainer? = nil,
        referencePolicy:
            InferenceSpeciesHydrationCoordinator.ReferencePolicy = .none
    ) -> InferenceLivePipelineCoordinator.Callbacks {
        subject.makeCallbacks(
            for: session,
            persistedMediaItems: persistedMediaItems,
            modelContainer: modelContainer,
            referencePolicy: referencePolicy
        )
    }
}

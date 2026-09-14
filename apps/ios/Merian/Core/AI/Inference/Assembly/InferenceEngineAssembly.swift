import Foundation

/// Builds the focused owner graph retained privately by `InferenceEngine`.
///
/// The assembly is a one-shot composition boundary. It preserves construction
/// order and default dependency resolution without becoming another runtime
/// state owner. `InferenceEngine` consumes the assembled values immediately and
/// retains its runtime collaborators behind private properties.
@MainActor
struct InferenceEngineAssembly {
    struct Dependencies {
        let visionSubjectClassifier: any VisionSubjectClassifying
        let localVisualTraitExtractor: any LocalVisualTraitExtracting
        let foundationVisualCueProvider: any FoundationVisualCueProviding
        let foundationVisualCueEligibilityChecker:
            any FoundationVisualCueEligibilityChecking
        let scanningPhraseSleeper: any ScanningPhraseSleeping
        let localAnalysisStartFeedback: @MainActor () -> Void
        let liveRequestService: InferenceLiveRequestService
        let liveResultService: InferenceLiveResultService
        let liveQueueService: InferenceLiveQueueService?
        let liveCompletionDependencies:
            InferenceLiveCompletionCoordinator.Dependencies?
        let speciesReferenceService: SpeciesReferenceHydrationService
        let speciesEnrichmentService: InferenceSpeciesEnrichmentService
        let hydrationPersistenceService:
            InferenceHydrationPersistenceService
        let identificationReviewService:
            InferenceIdentificationReviewService
        let identificationReviewSnapshotService:
            InferenceReviewSnapshotService
        let identificationReviewDependencies:
            InferenceIdentificationReviewCoordinator.Dependencies?
        let hydrationCoordinator: InferenceHydrationCoordinator?
        let requestPaywall: (@MainActor () -> Void)?
        let liveFailureDependencies:
            InferenceLiveFailureCoordinator.Dependencies?
        let livePipelineDependencies:
            InferenceLivePipelineCoordinator.Dependencies
        let speciesHydrationDependencies:
            InferenceSpeciesHydrationCoordinator.Dependencies
        let lookalikeCacheResetService:
            InferenceLookalikeCacheResetService
        let liveMediaProjector: InferenceLiveMediaProjector
    }

    let presentationLifecycleCoordinator: InferencePresentationCoordinator
    let presentationState: InferencePresentationState
    let sessionLifecycleCoordinator: InferenceSessionLifecycleCoordinator
    let localAnalysisCoordinator: InferenceLocalAnalysisCoordinator
    let liveAttemptCoordinator: InferenceLiveAttemptCoordinator
    let liveSubmissionCoordinator: InferenceLiveSubmissionCoordinator
    let livePipelinePresentationCoordinator:
        InferenceLivePresentationCoordinator
    let speciesPresentationCoordinator:
        InferenceSpeciesPresentationCoordinator
    let historicalLoadCoordinator: InferenceHistoricalLoadCoordinator
    let identificationReviewWorkflowCoordinator:
        InferenceReviewWorkflowCoordinator
    let hydrationCoordinator: InferenceHydrationCoordinator
    let writeCoordinator: InferenceWriteCoordinator

    init(dependencies: Dependencies) {
        let presentationLifecycleCoordinator =
            InferencePresentationCoordinator()
        let presentationState = InferencePresentationState()
        let writeCoordinator = InferenceWriteCoordinator()
        let localAnalysisCoordinator = InferenceLocalAnalysisCoordinator(
            dependencies: .init(
                classifier: dependencies.visionSubjectClassifier,
                traitExtractor: dependencies.localVisualTraitExtractor,
                foundationCueProvider:
                    dependencies.foundationVisualCueProvider,
                foundationCueEligibilityChecker:
                    dependencies.foundationVisualCueEligibilityChecker,
                phraseSleeper: dependencies.scanningPhraseSleeper,
                startFeedback: dependencies.localAnalysisStartFeedback
            )
        )
        let liveAttemptCoordinator = InferenceLiveAttemptCoordinator(
            queueService: dependencies.liveQueueService ?? .live
        )
        let liveCompletionCoordinator =
            InferenceLiveCompletionCoordinator(
                attemptCoordinator: liveAttemptCoordinator,
                dependencies: dependencies.liveCompletionDependencies ?? .live
            )
        let liveFailureCoordinator =
            InferenceLiveFailureCoordinator(
                attemptCoordinator: liveAttemptCoordinator,
                dependencies: dependencies.liveFailureDependencies
                    ?? .live(requestPaywall: dependencies.requestPaywall)
            )
        let livePipelineCoordinator = InferenceLivePipelineCoordinator(
            attemptCoordinator: liveAttemptCoordinator,
            requestService: dependencies.liveRequestService,
            resultService: dependencies.liveResultService,
            completionCoordinator: liveCompletionCoordinator,
            failureCoordinator: liveFailureCoordinator,
            dependencies: dependencies.livePipelineDependencies
        )
        let hydrationCoordinator = dependencies.hydrationCoordinator
            ?? InferenceHydrationCoordinator()
        let sessionLifecycleCoordinator =
            InferenceSessionLifecycleCoordinator(
                attemptCoordinator: liveAttemptCoordinator,
                hydrationCoordinator: hydrationCoordinator,
                writeCoordinator: writeCoordinator,
                localAnalysisCoordinator: localAnalysisCoordinator,
                presentationCoordinator: presentationLifecycleCoordinator,
                presentationState: presentationState
            )
        let speciesHydrationCoordinator =
            InferenceSpeciesHydrationCoordinator(
                taskCoordinator: hydrationCoordinator,
                referenceService: dependencies.speciesReferenceService,
                enrichmentService: dependencies.speciesEnrichmentService,
                persistenceService: dependencies.hydrationPersistenceService,
                dependencies: dependencies.speciesHydrationDependencies
            )
        let identificationReviewCoordinator =
            InferenceIdentificationReviewCoordinator(
                writeCoordinator: writeCoordinator,
                reviewService: dependencies.identificationReviewService,
                snapshotService:
                    dependencies.identificationReviewSnapshotService,
                dependencies:
                    dependencies.identificationReviewDependencies ?? .live
            )
        let speciesPresentationCoordinator =
            InferenceSpeciesPresentationCoordinator(
                presentationState: presentationState,
                writeCoordinator: writeCoordinator,
                reviewCoordinator: identificationReviewCoordinator,
                speciesHydrationCoordinator: speciesHydrationCoordinator
            )
        let livePipelinePresentationCoordinator =
            InferenceLivePresentationCoordinator(
                attemptCoordinator: liveAttemptCoordinator,
                sessionLifecycleCoordinator: sessionLifecycleCoordinator,
                presentationState: presentationState,
                speciesPresentationCoordinator:
                    speciesPresentationCoordinator,
                completionCoordinator: liveCompletionCoordinator,
                localAnalysisCoordinator: localAnalysisCoordinator
            )
        let liveSubmissionCoordinator =
            InferenceLiveSubmissionCoordinator(
                attemptCoordinator: liveAttemptCoordinator,
                writeCoordinator: writeCoordinator,
                sessionLifecycleCoordinator: sessionLifecycleCoordinator,
                presentationCoordinator:
                    presentationLifecycleCoordinator,
                presentationState: presentationState,
                localAnalysisCoordinator: localAnalysisCoordinator,
                mediaProjector: dependencies.liveMediaProjector,
                pipelineCoordinator: livePipelineCoordinator,
                pipelinePresentationCoordinator:
                    livePipelinePresentationCoordinator
            )
        let historicalHydrationCoordinator =
            InferenceHistoricalHydrationCoordinator(
                taskCoordinator: hydrationCoordinator,
                speciesHydrationCoordinator: speciesHydrationCoordinator
            )
        let identificationReviewWorkflowCoordinator =
            InferenceReviewWorkflowCoordinator(
                reviewCoordinator: identificationReviewCoordinator,
                taskCoordinator: hydrationCoordinator,
                speciesHydrationCoordinator: speciesHydrationCoordinator
            )
        let historicalLoadCoordinator =
            InferenceHistoricalLoadCoordinator(
                attemptCoordinator: liveAttemptCoordinator,
                sessionLifecycleCoordinator: sessionLifecycleCoordinator,
                presentationState: presentationState,
                writeCoordinator: writeCoordinator,
                speciesPresentationCoordinator:
                    speciesPresentationCoordinator,
                historicalHydrationCoordinator:
                    historicalHydrationCoordinator,
                lookalikeCacheResetService:
                    dependencies.lookalikeCacheResetService,
                reviewWorkflowCoordinator:
                    identificationReviewWorkflowCoordinator
            )

        self.presentationLifecycleCoordinator =
            presentationLifecycleCoordinator
        self.presentationState = presentationState
        self.sessionLifecycleCoordinator = sessionLifecycleCoordinator
        self.localAnalysisCoordinator = localAnalysisCoordinator
        self.liveAttemptCoordinator = liveAttemptCoordinator
        self.liveSubmissionCoordinator = liveSubmissionCoordinator
        self.livePipelinePresentationCoordinator =
            livePipelinePresentationCoordinator
        self.speciesPresentationCoordinator = speciesPresentationCoordinator
        self.historicalLoadCoordinator = historicalLoadCoordinator
        self.identificationReviewWorkflowCoordinator =
            identificationReviewWorkflowCoordinator
        self.hydrationCoordinator = hydrationCoordinator
        self.writeCoordinator = writeCoordinator
    }
}

import Foundation
import Testing

@testable import Merian

@Suite("Inference Architecture")
struct InferenceArchitectureTests {
    @Test func extractedOwnersRemainSmallAndExplicit() throws {
        for relativePath in [
            "Assembly/InferenceEngineAssembly.swift",
            "Facade/InferenceEngineCompatibility.swift",
            "Diagnostics/InferenceEngineDebugSupport.swift",
            "Diagnostics/InferenceEngine+Debug.swift",
            "State/InferenceWriteCoordinator.swift",
            "Completion/InferenceLiveCompletionCoordinator.swift",
            "Completion/InferenceLiveCompletionCoordinator+Live.swift",
            "Hydration/InferenceHydrationCoordinator.swift",
            "Hydration/InferenceSpeciesEnrichmentService.swift",
            "Hydration/InferenceSpeciesEnrichmentService+Live.swift",
            "Hydration/InferenceSpeciesHydrationModels.swift",
            "Hydration/InferenceSpeciesHydrationCoordinator.swift",
            "Hydration/InferenceSpeciesHydrationCoordinator+Live.swift",
            "Hydration/InferenceSpeciesPresentationCoordinator.swift",
            "Hydration/InferenceSpeciesEnrichmentCoordinator.swift",
            "Hydration/InferenceLookalikeCacheResetService.swift",
            "Hydration/InferenceLookalikeCacheResetService+Live.swift",
            "Hydration/InferenceHydrationPersistenceService.swift",
            "Hydration/InferenceHydrationPersistenceService+Live.swift",
            "Hydration/InferenceHistoricalRecordProjection.swift",
            "Hydration/InferenceHistoricalHydrationCoordinator.swift",
            "Hydration/InferenceHistoricalLoadCoordinator.swift",
            "Lifecycle/InferenceSessionLifecycleCoordinator.swift",
            "LocalAnalysis/InferenceLocalAnalysisCoordinator.swift",
            "LocalAnalysis/VisionSubjectClassification.swift",
            "LocalAnalysis/LocalVisualAnalysisImageBuilder.swift",
            "LocalAnalysis/LocalVisualTraitExtraction.swift",
            "LocalAnalysis/FoundationVisualCues.swift",
            "LocalAnalysis/ScanningPhrasePolicy.swift",
            "LocalAnalysis/ScanningPhraseCoordinator.swift",
            "Pipeline/InferenceLivePipelineModels.swift",
            "Pipeline/InferenceLivePipelineCoordinator.swift",
            "Pipeline/InferenceLivePipelineCoordinator+Live.swift",
            "Pipeline/InferenceLivePresentationCoordinator.swift",
            "Media/InferenceLiveMediaProjector.swift",
            "Presentation/InferencePresentationState.swift",
            "Presentation/InferencePresentationCoordinator.swift",
            "Request/InferenceLiveRequestService.swift",
            "Services/InferenceLiveQueueService.swift",
            "Services/InferenceLiveQueueService+Live.swift",
            "IdentificationReview/InferenceReviewSnapshotService.swift",
            "State/InferenceLiveAttemptCoordinator.swift",
            "Result/InferenceLiveResultService.swift",
            "Result/InferenceConfidencePolicy.swift",
            "Result/InferenceScanReplacement.swift",
            "Recovery/InferenceLookalikeCachePolicy.swift",
            "Recovery/InferenceLiveFailurePolicy.swift",
            "Recovery/InferenceFailurePresentation.swift",
            "Recovery/InferenceLiveFailureCoordinator.swift",
            "Recovery/InferenceLiveFailureCoordinator+Live.swift",
            "IdentificationReview/InferenceIdentificationReviewCoordinator.swift",
            "IdentificationReview/InferenceIdentificationReviewCoordinator+Live.swift",
            "IdentificationReview/InferenceReviewWorkflowCoordinator.swift",
            "IdentificationReview/IdentificationReviewPresentation.swift"
        ] {
            let file = try sourceRoot().appendingPathComponent(relativePath)
            #expect(
                FileManager.default.fileExists(atPath: file.path),
                "Inference is missing its \(relativePath) owner"
            )
            let lineCount = try contents(of: file)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(
                lineCount <= 600,
                "\(file.lastPathComponent) has \(lineCount) lines"
            )
        }
    }

    @Test func observablePresentationStateOwnsValueTransitions() throws {
        let state = try contents(
            of: sourceRoot().appendingPathComponent(
                "Presentation/InferencePresentationState.swift"
            )
        )
        let engine = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/AI/InferenceEngine.swift"
            )
        )
        let lifecycle = try contents(
            of: sourceRoot().appendingPathComponent(
                "Lifecycle/InferenceSessionLifecycleCoordinator.swift"
            )
        )
        let livePresentation = try contents(
            of: sourceRoot().appendingPathComponent(
                "Pipeline/InferenceLivePresentationCoordinator.swift"
            )
        )
        let historicalLoad = try contents(
            of: sourceRoot().appendingPathComponent(
                "Hydration/InferenceHistoricalLoadCoordinator.swift"
            )
        )
        let focusedTests = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/MerianTests/Core/AI/Inference/InferencePresentationStateTests.swift"
            )
        )

        for token in [
            "@Observable\nfinal class InferencePresentationState",
            "private(set) var queuedPresentationScanId:",
            "private(set) var activeMedia = ActiveScanMedia()",
            "private(set) var speciesData: SpeciesData?",
            "func prepareForNewScan(",
            "func publishSuccessfulResult(",
            "func finishCancellation(",
            "func beginHistoricalLoad(",
            "func publishHistoricalProjection(",
            "activeDistanceInMeters = nil"
        ] {
            #expect(state.contains(token))
        }
        for token in [
            "URLSession", "ModelContext", "LocalScanRecord", "Task {",
            "Task.detached", "MerianLog", "FileManager", ".shared",
            "InferenceLiveAttemptCoordinator", "InferenceHydrationCoordinator"
        ] {
            #expect(!state.contains(token))
        }

        for token in [
            "@ObservationIgnored private let presentationState:",
            "@ObservationIgnored private let sessionLifecycleCoordinator:",
            "get { presentationState.isProcessing }",
            "get { presentationState.activeMedia }",
            "get { presentationState.speciesData }",
            "sessionLifecycleCoordinator.prepareForNewScan(",
            "historicalLoadCoordinator.load(from: record)"
        ] {
            #expect(engine.contains(token))
        }
        for token in [
            "sessionLifecycleCoordinator.beginHistoricalLoad()",
            "presentationState.publishHistoricalProjection("
        ] {
            #expect(historicalLoad.contains(token))
            #expect(!engine.contains(token))
        }
        for token in [
            "presentationState.prepareForNewScan(",
            "presentationState.publishSuccessfulResult(",
            "presentationState.beginHistoricalLoad()",
            "presentationState.finishCancellation("
        ] {
            #expect(lifecycle.contains(token))
        }
        #expect(
            livePresentation.contains(
                "sessionLifecycleCoordinator.publishSuccessfulResult("
            )
        )
        for token in [
            "var isProcessing: Bool = false",
            "var scanningPhaseText: String =",
            "var activeMedia = ActiveScanMedia()",
            "private var activeDeviceLocale:",
            "private var activeCurrentMonth:",
            "private var activeTimeOfDay:",
            "private func applyReferenceStateIfAvailable("
        ] {
            #expect(!engine.contains(token))
        }

        let successStart = try #require(
            state.range(of: "func publishSuccessfulResult(")
        )
        let successEnd = try #require(
            state.range(
                of: "func beginQueueHandoff(",
                range: successStart.upperBound..<state.endIndex
            )
        )
        let successBody = state[successStart.lowerBound..<successEnd.lowerBound]
        let queuedClear = try #require(
            successBody.range(of: "queuedPresentationScanId = nil")
        )
        let mediaPublish = try #require(
            successBody.range(of: "activeMedia.items = persistedMediaItems")
        )
        let speciesPublish = try #require(
            successBody.range(of: "speciesData = data")
        )
        let referencePublish = try #require(
            successBody.range(of: "applyReferenceStateIfAvailable(from: data)")
        )
        let processingFinish = try #require(
            successBody.range(of: "isProcessing = false")
        )
        #expect(queuedClear.lowerBound < mediaPublish.lowerBound)
        #expect(mediaPublish.lowerBound < speciesPublish.lowerBound)
        #expect(speciesPublish.lowerBound < referencePublish.lowerBound)
        #expect(referencePublish.lowerBound < processingFinish.lowerBound)

        for token in [
            "prepareForNewScanClearsPresentationAndEveryTelemetryValue",
            "nonVisualTelemetryCannotInheritVisualDistance",
            "successfulResultPublishesPersistedMediaAndReferenceState",
            "queueHandoffPreservesMediaWhileEndingResultPresentation",
            "cancellationReturnsPresentationToCleanIdleState",
            "historicalProjectionReplacesReleasedLiveMedia",
            "engineReadThroughRetainsSwiftObservationInvalidation"
        ] {
            #expect(focusedTests.contains(token))
        }
    }

    @Test func liveMediaProjectorOwnsInputAndCarouselMapping() throws {
        let projector = try contents(
            of: sourceRoot().appendingPathComponent(
                "Media/InferenceLiveMediaProjector.swift"
            )
        )
        let engine = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/AI/InferenceEngine.swift"
            )
        )
        let submission = try contents(
            of: sourceRoot().appendingPathComponent(
                "Pipeline/InferenceLiveSubmissionCoordinator.swift"
            )
        )
        let focusedTests = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/MerianTests/Core/AI/Inference/InferenceLiveMediaProjectorTests.swift"
            )
        )

        for token in [
            "struct InferenceLiveMediaProjector",
            "private let dependencies: Dependencies",
            "func projectVisual(",
            "func projectNonVisual(",
            "func persistedMediaItems(",
            "timelineWasExplicit:",
            "posterImageIndex == imageIndex",
            "SecureTransportPolicy.httpsURL(from:"
        ] {
            #expect(projector.contains(token))
        }
        for token in [
            "@Observable", "URLSession", "Task {", "Task.detached",
            "ModelContext", "SpeciesData", ".shared"
        ] {
            #expect(!projector.contains(token))
        }

        for token in [
            "private let mediaProjector:",
            "mediaProjector.projectVisual(",
            "mediaProjector.projectNonVisual(",
            "mediaProjector.persistedMediaItems("
        ] {
            #expect(submission.contains(token))
        }
        #expect(!engine.contains("private let liveMediaProjector:"))
        #expect(!engine.contains("liveMediaProjector.projectVisual("))
        #expect(!engine.contains("liveMediaProjector.projectNonVisual("))
        #expect(!engine.contains("liveMediaProjector.persistedMediaItems("))
        for token in [
            "private func resolvedAudioPath(",
            "private func resolvedVideoPath(",
            "private func mediaItems(",
            "FileManager.default"
        ] {
            #expect(!engine.contains(token))
        }
        for token in [
            "visualDefaultTimelineUsesDisplayImagesAndFiltersContexts",
            "explicitTimelinePreservesOwnerOrderAndVideoPosterPolicy",
            "persistedRemappingRetainsPosterAndTimelineOrder",
            "adjacentStillIsNotMistakenForVideoPoster",
            "localPathResolutionPreservesCompatibilityFallbacks",
            "nonVisualDefaultProjectionFiltersEmptyLegacyInputs",
            "explicitTimelineDoesNotInventLegacyAudioModality"
        ] {
            #expect(focusedTests.contains(token))
        }
    }

    @Test func presentationLifecycleOwnsEphemeralIdentityOnly() throws {
        let coordinator = try contents(
            of: sourceRoot().appendingPathComponent(
                "Presentation/InferencePresentationCoordinator.swift"
            )
        )
        let engine = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/AI/InferenceEngine.swift"
            )
        )
        let lifecycle = try contents(
            of: sourceRoot().appendingPathComponent(
                "Lifecycle/InferenceSessionLifecycleCoordinator.swift"
            )
        )
        let submission = try contents(
            of: sourceRoot().appendingPathComponent(
                "Pipeline/InferenceLiveSubmissionCoordinator.swift"
            )
        )
        let focusedTests = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/MerianTests/Core/AI/Inference/InferencePresentationCoordinatorTests.swift"
            )
        )

        for token in [
            "final class InferencePresentationCoordinator",
            "private var preparedOwner:",
            "private var activeOwner:",
            "private var queuedVisualScanId:",
            "private var firstRenderMetric:",
            "func transitionToQueue(",
            "func finishActivePresentation(",
            "func rebindFirstRenderMetric(",
            "func consumeFirstRenderStart("
        ] {
            #expect(coordinator.contains(token))
        }
        for token in [
            "@Observable", "SpeciesData", "ActiveScanMedia", "MerianLog",
            "FileManager", "URLSession", "Task {", "Task.detached", ".shared"
        ] {
            #expect(!coordinator.contains(token))
        }

        for token in [
            "private let presentationLifecycleCoordinator:",
            "sessionLifecycleCoordinator.prepareForNewScan(",
            "sessionLifecycleCoordinator.transitionToQueue(",
            "sessionLifecycleCoordinator.dismissAnalyzingPresentation()"
        ] {
            #expect(engine.contains(token))
        }
        for token in [
            "presentationCoordinator.prepare(",
            "presentationCoordinator.transitionToQueue(",
            "presentationCoordinator.reset()"
        ] {
            #expect(lifecycle.contains(token))
        }
        #expect(submission.contains("presentationCoordinator.activate("))
        for token in [
            "struct AnalysisPresentationOwner",
            "preparedPresentationOwner",
            "activePresentationOwner",
            "queuedVisualPresentationScanId",
            "queuedPresentationCarriesLiveMedia",
            "queuedPresentationScanningPhrases",
            "pendingFirstRenderMetric"
        ] {
            #expect(!engine.contains(token))
        }
        for token in [
            "preparedVisualHandoffUsesGenericPhrasesWithoutLiveMedia",
            "activeVisualHandoffRequiresExactOwnerAndCurrentAttempt",
            "nonVisualHandoffNeverCarriesVisualContext",
            "firstRenderMetricIsExactAndConsumedOnce",
            "firstRenderMetricRebindRequiresItsExactSource",
            "authAdmissionClearsOwnersWhilePreservingRenderTiming"
        ] {
            #expect(focusedTests.contains(token))
        }
    }

    @Test func historicalRecordProjectionOwnsMappingAndHydrationPlanning() throws {
        let projection = try contents(
            of: sourceRoot().appendingPathComponent(
                "Hydration/InferenceHistoricalRecordProjection.swift"
            )
        )
        let historicalHydration = try contents(
            of: sourceRoot().appendingPathComponent(
                "Hydration/InferenceHistoricalHydrationCoordinator.swift"
            )
        )
        let historicalLoad = try contents(
            of: sourceRoot().appendingPathComponent(
                "Hydration/InferenceHistoricalLoadCoordinator.swift"
            )
        )
        let engine = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/AI/InferenceEngine.swift"
            )
        )
        let focusedTests = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/MerianTests/Core/AI/Inference/InferenceHistoricalRecordProjectionTests.swift"
            )
        )
        let orchestrationTests = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/MerianTests/Core/AI/Inference/InferenceHistoricalHydrationCoordinatorTests.swift"
            )
        )
        let loadTests = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/MerianTests/Core/AI/Inference/InferenceHistoricalLoadCoordinatorTests.swift"
            )
        )

        for token in [
            "struct InferenceHistoricalRecordProjection: Sendable",
            "struct HydrationPlan: Equatable, Sendable",
            "struct DeferredContent: Sendable",
            "@MainActor\n    init(",
            "record.hasResolvedBiologicalIdentification",
            "record.shouldSuppressReferenceImages",
            "taxonomy?.hasUsableLookalikeValidation != true",
            "Task.detached(priority: .userInitiated)",
            "ExternalReferenceImagePolicy.allowedURLStrings("
        ] {
            #expect(projection.contains(token))
        }
        for token in [
            "MerianNetworkClient", "BackgroundDatabaseActor", "ModelContext",
            "URLSession", "UserDefaults", "@unchecked Sendable", "Task {"
        ] {
            #expect(!projection.contains(token))
        }
        for token in [
            "final class InferenceHistoricalHydrationCoordinator",
            "taskCoordinator.replaceTask(in: .historic)",
            "await dependencies.decodeDeferredContent(",
            "await callbacks.hydrateDisplayedOverride(override)",
            "await withTaskGroup(of: Void.self)",
            "await self.hydrateEnrichmentAndGBIF(",
            "taskCoordinator.beginHistoricEnrichmentAttempt(",
            "await speciesHydrationCoordinator.hydrateGBIF(",
            "callbacks.speciesHydration.isPresentationCurrent(identity)",
            "callbacks.speciesHydration.currentReferenceState() == .loading",
            "callbacks.speciesHydration.publishReferenceState(.empty)"
        ] {
            #expect(historicalHydration.contains(token))
        }
        for token in [
            "LocalScanRecord", "record.", "MerianNetworkClient", "URLSession",
            "UserDefaults", "BackgroundDatabaseActor", ".shared",
            "@unchecked Sendable"
        ] {
            #expect(!historicalHydration.contains(token))
        }

        for token in [
            "final class InferenceHistoricalLoadCoordinator",
            "private let attemptCoordinator:",
            "private let sessionLifecycleCoordinator:",
            "private let presentationState:",
            "private let writeCoordinator:",
            "private let speciesPresentationCoordinator:",
            "private let historicalHydrationCoordinator:",
            "private let lookalikeCacheResetService:",
            "private let reviewWorkflowCoordinator:",
            "func load(from record: LocalScanRecord)"
        ] {
            #expect(historicalLoad.contains(token))
        }
        for token in [
            "MerianNetworkClient", "BackgroundDatabaseActor", "URLSession",
            "UserDefaults", "MerianLog", "FileManager", ".shared",
            "Task {", "Task.detached", "private var ", "@Observable"
        ] {
            #expect(!historicalLoad.contains(token))
        }

        let loadStart = try #require(historicalLoad.range(
            of: "func load(from record: LocalScanRecord)"
        ))
        let loadSection = historicalLoad[loadStart.lowerBound...]
        let admission = try #require(
            loadSection.range(
                of: "sessionLifecycleCoordinator.beginHistoricalLoad()"
            )
        )
        let identityAssignment = try #require(
            loadSection.range(
                of: "attemptCoordinator.setActiveScanId(record.id)"
            )
        )
        let liveMediaRelease = try #require(
            loadSection.range(of: "presentationState.releaseLiveMedia()")
        )
        let containerSnapshot = try #require(
            loadSection.range(
                of: "let modelContainer = record.modelContext?.container"
            )
        )
        let projectionCreation = try #require(
            loadSection.range(of: "let projection = InferenceHistoricalRecordProjection(")
        )
        let compatibilityReset = try #require(
            loadSection.range(
                of: "lookalikeCacheResetService.scheduleIfNeeded(in: modelContainer)"
            )
        )
        let historicalMediaPublication = try #require(
            loadSection.range(
                of: "presentationState.publishHistoricalProjection("
            )
        )
        let presentationGeneration = try #require(
            loadSection.range(
                of: "let presentationGeneration = writeCoordinator.generation"
            )
        )
        let reviewAction = try #require(
            loadSection.range(
                of: "speciesPresentationCoordinator.beginReviewAction("
            )
        )
        let reviewCallbacks = try #require(
            loadSection.range(
                of: "let reviewCallbacks = speciesPresentationCoordinator"
            )
        )
        let historicTaskStart = try #require(
            loadSection.range(
                of: "historicalHydrationCoordinator.scheduleHydration("
            )
        )
        #expect(admission.lowerBound < identityAssignment.lowerBound)
        #expect(identityAssignment.lowerBound < liveMediaRelease.lowerBound)
        #expect(liveMediaRelease.lowerBound < containerSnapshot.lowerBound)
        #expect(containerSnapshot.lowerBound < projectionCreation.lowerBound)
        #expect(projectionCreation.lowerBound < compatibilityReset.lowerBound)
        #expect(
            compatibilityReset.lowerBound <
                historicalMediaPublication.lowerBound
        )
        #expect(
            historicalMediaPublication.lowerBound <
                presentationGeneration.lowerBound
        )
        #expect(presentationGeneration.lowerBound < reviewAction.lowerBound)
        #expect(reviewAction.lowerBound < reviewCallbacks.lowerBound)
        #expect(reviewCallbacks.lowerBound < historicTaskStart.lowerBound)

        let historicTask = loadSection[
            historicTaskStart.lowerBound..<loadSection.endIndex
        ]
        #expect(!historicTask.contains("record."))
        for retiredToken in [
            "SpeciesData(", "record.candidatesData", "record.lookalikesData",
            "record.similarSpecies", "JSONDecoder()", "Task.detached",
            "withTaskGroup", "decodeDeferredContent(",
            "beginHistoricEnrichmentAttempt(", ".hydrateGBIF("
        ] {
            #expect(!loadSection.contains(retiredToken))
        }
        for token in [
            "sessionLifecycleCoordinator.beginHistoricalLoad()",
            "InferenceHistoricalRecordProjection(",
            "presentationState.releaseLiveMedia()",
            "presentationState.publishHistoricalProjection(",
            "historicalHydrationCoordinator.scheduleHydration("
        ] {
            #expect(!engine.contains(token))
        }
        let engineLoadStart = try #require(
            engine.range(of: "func load(from record: LocalScanRecord)")
        )
        let engineLoadEnd = try #require(engine.range(
            of: "func handleApplicationActiveStateChange(",
            range: engineLoadStart.upperBound..<engine.endIndex
        ))
        let engineLoad = engine[
            engineLoadStart.lowerBound..<engineLoadEnd.lowerBound
        ]
        #expect(
            engineLoad.contains(
                "historicalLoadCoordinator.load(from: record)"
            )
        )

        #expect(
            focusedTests.contains(
                "struct InferenceHistoricalRecordProjectionTests"
            )
        )
        #expect(
            focusedTests.split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).count <= 600
        )
        #expect(
            orchestrationTests.contains(
                "struct HistoricalHydrationCoordinatorTests"
            )
        )
        #expect(
            orchestrationTests.split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).count <= 600
        )
        for token in [
            "struct InferenceHistoricalLoadCoordinatorTests",
            "publishesProjectionBeforeDeferredHydrationCompletes",
            "authFenceRejectsLoadWithoutChangingPresentation",
            "replacementRejectsCancellationIgnoringPriorDecode",
            "schedulesRequiredLookalikeResetWithRecordContainer"
        ] {
            #expect(loadTests.contains(token))
        }
        #expect(
            loadTests.split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).count <= 600
        )
    }

    @Test func engineDoesNotReclaimExtractedMutableOrWireState() throws {
        let source = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/AI/InferenceEngine.swift"
            )
        )

        #expect(source.contains("private let speciesPresentationCoordinator:"))
        #expect(!source.contains("private let speciesHydrationCoordinator:"))
        #expect(
            source.contains("private let historicalLoadCoordinator:")
        )
        #expect(!source.contains("private let historicalHydrationCoordinator:"))
        #expect(!source.contains("private let lookalikeCacheResetService:"))
        #expect(!source.contains("private let speciesReferenceService:"))
        #expect(!source.contains("private let speciesEnrichmentService:"))
        #expect(!source.contains("private let hydrationPersistenceService:"))
        #expect(source.contains("private let hydrationCoordinator:"))
        #expect(source.contains("private let writeCoordinator"))
        #expect(source.contains("private let localAnalysisCoordinator:"))
        #expect(source.contains("private let liveAttemptCoordinator:"))
        #expect(!source.contains("private let liveCompletionCoordinator:"))
        #expect(!source.contains("private let livePipelineCoordinator:"))
        #expect(!source.contains("private let liveMediaProjector:"))
        #expect(source.contains("private let liveSubmissionCoordinator:"))
        #expect(
            source.contains(
                "private let livePipelinePresentationCoordinator:"
            )
        )
        #expect(!source.contains("private let liveRequestService:"))
        #expect(!source.contains("private let liveResultService:"))
        #expect(!source.contains("private let liveFailureCoordinator:"))
        #expect(!source.contains("private let identificationReviewCoordinator:"))
        #expect(
            source.contains(
                "private let identificationReviewWorkflowCoordinator:"
            )
        )
        #expect(!source.contains("private let identificationReviewService:"))
        #expect(!source.contains("private let identificationReviewSnapshotService:"))
        #expect(!source.contains("resetEnrichmentRateLimit()"))
        #expect(!source.contains("replaceAndAwaitTask("))
        #expect(!source.contains("in: .review"))
        #expect(!source.contains("in: .gbif"))
        for retiredToken in [
            "externalAPISession",
            "WikiMobileSectionsResponse",
            "GBIFMediaResponse",
            "backgroundWriteTasks =",
            "pendingBackgroundTasks:",
            "identificationReviewWriteTail",
            "historicHydrationTask",
            "liveHydrationTask",
            "gbifHydrationTask",
            "enrichmentWriteTask",
            "wikiFetchAttemptedIds",
            "enrichmentAttemptedScanIds",
            "enrichmentRateLimitedUntil",
            "private var enrichedSpeciesTimestamps",
            "fetchWikipediaAndHydrate(",
            "fetchGBIFImagesAndHydrate(",
            "hydrateMissingReviewReferenceImages(",
            "fetchAndPatchOverrideData(",
            "shouldResetLocalLookalikesCache(",
            "scheduleLocalLookalikesCacheResetIfNeeded(",
            "localClassificationTask",
            "localVisualTraitTask",
            "foundationVisualCueTask",
            "phaseRotationTask",
            "localVisualAnalysisImage",
            "localVisionClassification",
            "didFinishLocalVisionClassification",
            "didSendInferenceRequestBody",
            "didPauseLocalVisualAnalysisForInactivity",
            "private var scanningPhraseCoordinator",
            "observationContextJSONStrings(",
            "identifyMultiModal(",
            "uploadStagedVideoFiles(",
            "InferenceProcessingActor.shared",
            "parseAndSave(",
            "skipImageRequirement:",
            "private static let networkTimeoutRecoveryReason",
            "makeErrorSpeciesData(",
            "MerianNetworkClient.stableEdgeErrorCode(",
            "EdgeFunctionErrorPolicy.stableCode(",
            "MerianNetworkClient.isRecoverableInferenceConflict(",
            "publishLiveInferenceFailure(",
            "logLiveInferenceFailure(",
            "publishQueuedRecoveryHandoffIfNeeded(",
            "publishQueuedRetiredOwnershipHandoffIfNeeded(",
            "releaseQueueBackedLiveInferenceForRecovery(",
            "CircuitBreakerManager.shared",
            "UsageManager.shared",
            "refundScan(scanId:",
            "SupabaseManager.shared",
            "OfflineQueueManager.shared",
            ".from(\"",
            ".rpc("
        ] {
            #expect(
                !source.contains(retiredToken),
                "InferenceEngine reclaimed \(retiredToken)"
            )
        }
    }

    @Test func liveAttemptOwnerContainsStateAndDurableQueueAccess() throws {
        let root = try repositoryRoot()
        let engine = try contents(of: root.appendingPathComponent(
            "apps/ios/Merian/Core/AI/InferenceEngine.swift"
        ))
        let coordinator = try contents(
            of: sourceRoot().appendingPathComponent(
                "State/InferenceLiveAttemptCoordinator.swift"
            )
        )
        let service = try contents(
            of: sourceRoot().appendingPathComponent(
                "Services/InferenceLiveQueueService.swift"
            )
        )
        let liveService = try contents(
            of: sourceRoot().appendingPathComponent(
                "Services/InferenceLiveQueueService+Live.swift"
            )
        )
        let pipeline = try contents(
            of: sourceRoot().appendingPathComponent(
                "Pipeline/InferenceLivePipelineCoordinator.swift"
            )
        )
        let submission = try contents(
            of: sourceRoot().appendingPathComponent(
                "Pipeline/InferenceLiveSubmissionCoordinator.swift"
            )
        )
        let lifecycle = try contents(
            of: sourceRoot().appendingPathComponent(
                "Lifecycle/InferenceSessionLifecycleCoordinator.swift"
            )
        )
        let appDI = try contents(of: root.appendingPathComponent(
            "apps/ios/Merian/Core/AppDIContainer.swift"
        ))

        for token in [
            "private(set) var task:",
            "private(set) var activeScanId:",
            "private(set) var activeAttemptGeneration:",
            "private(set) var activeForegroundGeneration:",
            "private(set) var recoverablePresentationScanId:",
            "private var displacedTasks:",
            "private var displacedTaskWaiters:",
            "private var followUpAuthorizationGeneration:",
            "private var activeFollowUpAuthorizationGeneration:",
            "func cancelAllTasks()",
            "func awaitQuiescence() async",
            "func cancelAndClearActiveAttempt()",
            "func invalidateFollowUpAuthorization()",
            "func canAuthorizeFollowUps(",
            "func invalidateActiveAttempt(",
            "func completeQueuedInferenceIfNeeded(",
            "return scanId == nil && foregroundGeneration == nil",
            "guard !Task.isCancelled,",
            "followUpAuthorizationIsCurrent,",
            "func canCommitRecoveredBackgroundResult("
        ] {
            #expect(coordinator.contains(token))
        }
        let completionStart = try #require(coordinator.range(
            of: "func completeQueuedInferenceIfNeeded("
        ))
        let recoveryStart = try #require(coordinator.range(
            of: "func canCommitRecoveredBackgroundResult(",
            range: completionStart.upperBound..<coordinator.endIndex
        ))
        let completion = coordinator[
            completionStart.lowerBound..<recoveryStart.lowerBound
        ]
        #expect(completion.contains("isLocalAttemptCurrent("))
        #expect(!completion.contains("canAuthorizeFollowUps("))
        #expect(coordinator.contains("private let queueService:"))
        #expect(!coordinator.contains("OfflineQueueManager"))
        #expect(!coordinator.contains("InferenceEngine"))

        for token in [
            "struct InferenceLiveQueueService {",
            "struct Dependencies: Sendable",
            "@MainActor @Sendable (String, UUID?, String) -> Void",
            "@MainActor @Sendable (String, [String], UUID) async -> Bool"
        ] {
            #expect(service.contains(token))
        }
        for token in [
            "OfflineQueueManager.shared", "InferenceEngine(", "SpeciesData",
            "Task {", "Task.detached", "ModelContext"
        ] {
            #expect(!service.contains(token))
        }

        for token in [
            "OfflineQueueManager.shared.releaseDeferredLiveUpload(",
            "OfflineQueueManager.shared.retireForegroundInference(",
            "OfflineQueueManager.shared.claimForegroundInferenceStart(",
            ".isForegroundInferenceAttemptCurrent(",
            ".foregroundInferenceGenerations[scanId]",
            "preservePreferredGoalHint: true",
            "ForegroundInferenceGenerationExpectation(",
            "httpStatus: 400",
            "needsAttention: false"
        ] {
            #expect(liveService.contains(token))
        }
        #expect(!engine.contains("OfflineQueueManager.shared"))
        #expect(!engine.contains("foregroundInferenceGenerations["))
        #expect(!engine.contains("requestAttemptCoordinator"))
        #expect(!engine.contains("livePipelineCoordinator.activate("))
        #expect(!engine.contains("livePipelineCoordinator.admit("))
        #expect(submission.contains("pipelineCoordinator.activate("))
        #expect(submission.contains("pipelineCoordinator.admit("))
        #expect(
            !engine.contains(
                "liveAttemptCoordinator.invalidateActiveAttempt("
            )
        )
        #expect(
            lifecycle.contains(
                "attemptCoordinator.invalidateActiveAttempt("
            )
        )
        #expect(
            pipeline.contains(
                "let durableAttemptCoordinator = attemptCoordinator"
            )
        )
        #expect(pipeline.contains("attemptCoordinator.activate("))
        #expect(pipeline.contains("attemptCoordinator.checkAttempt("))
        #expect(pipeline.contains("clearActiveAttemptIfCurrent("))
        #expect(appDI.contains("liveInferenceQueueService"))
        #expect(appDI.contains("liveQueueService:"))

        let cancellationStart = try #require(
            coordinator.range(of: "func cancelAndClearActiveAttempt()")
        )
        let scanSetterStart = try #require(
            coordinator.range(
                of: "func setActiveScanId(",
                range: cancellationStart.upperBound..<coordinator.endIndex
            )
        )
        let cancellation = coordinator[
            cancellationStart.lowerBound..<scanSetterStart.lowerBound
        ]
        let detachTask = try #require(
            cancellation.range(of: "task = nil")
        )
        let clear = try #require(
            cancellation.range(of: "clearActiveAttempt()")
        )
        let retainTask = try #require(
            cancellation.range(of: "retainUntilCompletion(displacedTask)")
        )
        let cancelTask = try #require(
            cancellation.range(of: "displacedTask.cancel()")
        )
        #expect(detachTask.lowerBound < clear.lowerBound)
        #expect(clear.lowerBound < retainTask.lowerBound)
        #expect(retainTask.lowerBound < cancelTask.lowerBound)

        let invalidationStart = try #require(
            coordinator.range(of: "func invalidateActiveAttempt(")
        )
        let retirementStart = try #require(
            coordinator.range(
                of: "func retireForegroundInferenceIfCurrent(",
                range: invalidationStart.upperBound..<coordinator.endIndex
            )
        )
        let invalidation = coordinator[
            invalidationStart.lowerBound..<retirementStart.lowerBound
        ]
        let localCancellation = try #require(
            invalidation.range(of: "cancelAndClearActiveAttempt()")
        )
        let durableRelease = try #require(
            invalidation.range(of: "releaseAndRetire(")
        )
        #expect(localCancellation.lowerBound < durableRelease.lowerBound)
    }

    @Test func sharedQueueFixturesKeepTheirCrossFrameworkLease() throws {
        let testRoot = try repositoryRoot().appendingPathComponent("apps/ios/MerianTests")
        for path in [
            "Core/AI/InferenceEngineTests.swift",
            "Core/AI/Inference/InferenceIntegrationAuditTests.swift",
            "Core/Data/OfflineQueueManagerTests.swift",
            "Core/Data/OfflineSync/BackgroundTransferOwnershipTests.swift",
            "Core/Data/OfflineSync/OfflineQueuedScanDeletionTests.swift",
            "Core/Data/OfflineSync/OfflineJobSchedulerTests.swift",
            "Core/Data/BackgroundDatabaseActorTests.swift",
            "Core/Data/ScanRepositoryTests.swift",
            "Core/Data/OfflineSync/ProfileActorCacheTests.swift",
            "Core/Data/OfflineSync/QueueActorCacheTests.swift",
            "Core/Hardware/HardwareOrchestratorTests.swift",
            "App/Lifecycle/AppLifecycleManagerTests.swift",
            "Features/Capture/Shell/CaptureWorkspaceStagingTests.swift"
        ] {
            let source = try contents(of: testRoot.appendingPathComponent(path))
            #expect(source.contains(".sharedProcessState("), "Missing process lease in \(path)")
            #expect(source.contains(".offlineQueueManager"), "Missing queue resource in \(path)")
        }
        let capture = try contents(of: testRoot.appendingPathComponent(
            "Features/Capture/Shell/CaptureWorkspaceTestCase.swift"
        ))
        #expect(capture.contains("CaptureWorkspaceViewModelRefinementTests: OfflineQueueTestCase"))
        for path in [
            "Features/Insights/Shell/InsightSheetTestSupport.swift",
            "Core/Data/ScanRepositoryTests.swift"
        ] {
            let source = try contents(of: testRoot.appendingPathComponent(path))
            #expect(!source.contains("ScanRepository.shared.configure("))
        }
    }

    @Test func liveRequestServiceOwnsProviderPayloadAndDispatch() throws {
        let requestSource = try contents(
            of: sourceRoot().appendingPathComponent(
                "Request/InferenceLiveRequestService.swift"
            )
        )
        for requiredToken in [
            "struct VisualRequest: Sendable",
            "struct NonVisualRequest: Sendable",
            "r2ObjectKeys: []",
            "observationContextJSONStrings(",
            "uploadStagedVideoFiles(",
            "MerianNetworkClient.shared.identifyMultiModal(",
            "try validateAttempt()"
        ] {
            #expect(requestSource.contains(requiredToken))
        }
        #expect(!requestSource.contains("@unchecked Sendable"))
        #expect(!requestSource.contains("OfflineQueueManager.shared"))
        #expect(!requestSource.contains("ModelContext"))
        #expect(!requestSource.contains("SpeciesData"))
        #expect(requestSource.contains("private static func imageMIMEType("))
        #expect(
            requestSource.contains(
                "private static func observationContextJSONStrings("
            )
        )

        let appDISource = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/AppDIContainer.swift"
            )
        )
        #expect(appDISource.contains("liveInferenceRequestService"))
        #expect(appDISource.contains("liveRequestService:"))
    }

    @Test func liveResultServiceOwnsPersistenceMappingWithoutEngineEffects() throws {
        let resultSource = try contents(
            of: sourceRoot().appendingPathComponent(
                "Result/InferenceLiveResultService.swift"
            )
        )
        for requiredToken in [
            "private let dependencies:",
            "enum Media: Sendable",
            "enum Outcome",
            "case persisted(CompletedResult)",
            "case completedWithoutRecord(CompletedResult)",
            "case persistenceRejected",
            "InferenceProcessingActor.shared.parseAndSave(",
            "guard parsed.didCompletePersistence",
            "private func persistenceRequest(",
            "try validateAttempt()"
        ] {
            #expect(resultSource.contains(requiredToken))
        }
        for forbiddenToken in [
            "@unchecked Sendable", "Task {", "Task.detached",
            "MerianNetworkClient", "OfflineQueueManager", "GamificationManager",
            "PushNotificationManager", "AppDIContainer", "HapticManager",
            "AppTelemetry", "CircuitBreakerManager"
        ] {
            #expect(!resultSource.contains(forbiddenToken))
        }
        let appDISource = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/AppDIContainer.swift"
            )
        )
        #expect(appDISource.contains("liveInferenceResultService"))
        #expect(appDISource.contains("liveResultService:"))
    }

    @Test func enrichmentMappingAndPersistenceHaveFocusedOwners() throws {
        let enrichment = try contents(
            of: sourceRoot().appendingPathComponent(
                "Hydration/InferenceSpeciesEnrichmentService.swift"
            )
        )
        let liveEnrichment = try contents(
            of: sourceRoot().appendingPathComponent(
                "Hydration/InferenceSpeciesEnrichmentService+Live.swift"
            )
        )
        let persistence = try contents(
            of: sourceRoot().appendingPathComponent(
                "Hydration/InferenceHydrationPersistenceService.swift"
            )
        )
        let livePersistence = try contents(
            of: sourceRoot().appendingPathComponent(
                "Hydration/InferenceHydrationPersistenceService+Live.swift"
            )
        )
        let hydrationCoordinator = try contents(
            of: sourceRoot().appendingPathComponent(
                "Hydration/InferenceSpeciesHydrationCoordinator.swift"
            )
        )
        let enrichmentCoordinator = try contents(
            of: sourceRoot().appendingPathComponent(
                "Hydration/InferenceSpeciesEnrichmentCoordinator.swift"
            )
        )
        let hydrationModels = try contents(
            of: sourceRoot().appendingPathComponent(
                "Hydration/InferenceSpeciesHydrationModels.swift"
            )
        )
        let speciesPresentation = try contents(
            of: sourceRoot().appendingPathComponent(
                "Hydration/InferenceSpeciesPresentationCoordinator.swift"
            )
        )
        let liveHydrationCoordinator = try contents(
            of: sourceRoot().appendingPathComponent(
                "Hydration/InferenceSpeciesHydrationCoordinator+Live.swift"
            )
        )
        let cacheReset = try contents(
            of: sourceRoot().appendingPathComponent(
                "Hydration/InferenceLookalikeCacheResetService.swift"
            )
        )
        let liveCacheReset = try contents(
            of: sourceRoot().appendingPathComponent(
                "Hydration/InferenceLookalikeCacheResetService+Live.swift"
            )
        )
        let historicalLoad = try contents(
            of: sourceRoot().appendingPathComponent(
                "Hydration/InferenceHistoricalLoadCoordinator.swift"
            )
        )
        let engine = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/AI/InferenceEngine.swift"
            )
        )
        let appDI = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/AppDIContainer.swift"
            )
        )

        for token in [
            "struct MetadataPatch: Sendable",
            "struct LookalikesPatch: Sendable",
            "SpeciesData.sanitizeAlternativeNames(",
            "private static func mapLookalike("
        ] {
            #expect(enrichment.contains(token))
        }
        for token in [
            "MerianNetworkClient", "BackgroundDatabaseActor", "ModelContext",
            "ModelContainer", "Task {", "Task.detached", "JSONEncoder"
        ] {
            #expect(!enrichment.contains(token))
        }
        #expect(
            liveEnrichment.contains(
                "MerianNetworkClient.shared.fetchEnrichment("
            )
        )
        #expect(liveEnrichment.contains("scope: scope.rawValue"))
        #expect(!liveEnrichment.contains("BackgroundDatabaseActor"))

        for token in [
            "struct ReferenceSnapshot: Equatable, Sendable",
            "struct MetadataSnapshot: Sendable",
            "struct LookalikesSnapshot: Sendable"
        ] {
            #expect(persistence.contains(token))
        }
        for token in [
            "MerianNetworkClient", "BackgroundDatabaseActor", "Task.detached",
            "JSONEncoder"
        ] {
            #expect(!persistence.contains(token))
        }
        #expect(livePersistence.contains("BackgroundDatabaseActor("))
        #expect(livePersistence.contains("Task.detached("))
        #expect(livePersistence.contains("JSONEncoder().encode(entries)"))
        #expect(!livePersistence.contains("MerianNetworkClient"))

        for source in [
            hydrationCoordinator,
            enrichmentCoordinator,
            hydrationModels,
            speciesPresentation,
            cacheReset
        ] {
            for token in [
                "MerianNetworkClient", "MerianLog", "UserDefaults",
                "BackgroundDatabaseActor", "Task.detached"
            ] {
                #expect(!source.contains(token))
            }
        }
        for token in [
            "func scheduleLiveHydration(", "func hydrateWikipedia(",
            "func hydrateGBIF(", "func hydrateMissingReferenceImages(",
            "replaceTask(in: .live)"
        ] {
            #expect(hydrationCoordinator.contains(token))
        }
        #expect(
            enrichmentCoordinator.contains("await withTaskGroup(of: Void.self)")
        )
        #expect(
            enrichmentCoordinator.contains("recordEnrichmentRateLimit()")
        )
        #expect(liveHydrationCoordinator.contains("MerianLog.general.debug("))
        #expect(cacheReset.contains("struct InferenceLookalikeCacheResetService"))
        #expect(liveCacheReset.contains("UserDefaults.standard"))
        #expect(liveCacheReset.contains("BackgroundDatabaseActor("))
        #expect(liveCacheReset.contains("Task.detached("))
        #expect(engine.contains("private let speciesPresentationCoordinator:"))
        #expect(!engine.contains("private let speciesHydrationCoordinator:"))
        #expect(!engine.contains("private let lookalikeCacheResetService:"))
        #expect(
            historicalLoad.contains(
                "private let lookalikeCacheResetService:"
            )
        )
        #expect(!engine.contains("private let speciesReferenceService:"))
        #expect(!engine.contains("private let speciesEnrichmentService:"))
        #expect(!engine.contains("private let hydrationPersistenceService:"))
        #expect(appDI.contains("liveInferenceSpeciesReferenceService"))
        #expect(appDI.contains("liveInferenceSpeciesEnrichmentService"))
        #expect(appDI.contains("speciesEnrichmentService:"))
        #expect(appDI.contains("liveInferenceHydrationPersistenceService"))
        #expect(appDI.contains("hydrationPersistenceService:"))
        #expect(appDI.contains("liveInferenceSpeciesHydrationDependencies"))
        #expect(appDI.contains("speciesHydrationDependencies:"))
        #expect(appDI.contains("liveInferenceLookalikeCacheResetService"))
        #expect(appDI.contains("lookalikeCacheResetService:"))
    }

    @Test func identificationReviewOwnersKeepEffectsAtLiveBoundary() throws {
        let root = try repositoryRoot()
        let service = try contents(of: root.appendingPathComponent(
            "apps/ios/Merian/Core/Network/Inference/InferenceIdentificationReviewService.swift"
        ))
        let snapshotService = try contents(
            of: sourceRoot().appendingPathComponent(
                "IdentificationReview/InferenceReviewSnapshotService.swift"
            )
        )
        let coordinator = try contents(
            of: sourceRoot().appendingPathComponent(
                "IdentificationReview/InferenceIdentificationReviewCoordinator.swift"
            )
        )
        let liveCoordinator = try contents(
            of: sourceRoot().appendingPathComponent(
                "IdentificationReview/InferenceIdentificationReviewCoordinator+Live.swift"
            )
        )
        let workflow = try contents(
            of: sourceRoot().appendingPathComponent(
                "IdentificationReview/InferenceReviewWorkflowCoordinator.swift"
            )
        )
        let presentation = try contents(
            of: sourceRoot().appendingPathComponent(
                "IdentificationReview/IdentificationReviewPresentation.swift"
            )
        )
        let engine = try contents(of: root.appendingPathComponent(
            "apps/ios/Merian/Core/AI/InferenceEngine.swift"
        ))
        let appDI = try contents(of: root.appendingPathComponent(
            "apps/ios/Merian/Core/AppDIContainer.swift"
        ))

        for token in [
            "struct InferenceSpeciesDictionaryRecord",
            "struct InferenceIdentificationReviewMutation",
            "let userReviewState: UserReviewState",
            "static func userOverride(",
            "static func aiConfirmation(",
            "static func reset(scanID:",
            "private init(",
            "container.encode(userReviewState.rawValue",
            "beginUnownedAccountBoundWork()",
            "finishAccountBoundWork(lease)",
            "isAccountBoundWorkLeaseCurrent(lease)",
            ".from(\"species_dictionary\")",
            ".rpc("
        ] {
            #expect(service.contains(token))
        }
        #expect(!service.contains("let userReviewState: String"))
        for token in ["SupabaseManager.shared", ".from(\"", ".rpc("] {
            #expect(!engine.contains(token))
        }
        for token in [
            "FetchDescriptor<LocalScanRecord>",
            "descriptor.fetchLimit = 1",
            "try modelContext.fetch(descriptor).first.map"
        ] {
            #expect(snapshotService.contains(token))
        }
        #expect(!snapshotService.contains("try?"))
        #expect(!engine.contains("try? context.fetch"))

        for token in [
            "beginReviewAction(scanId:",
            "enqueueOverrideAdmission(",
            "enqueueReviewMutation(",
            "enqueueFlagReset(",
            "enqueueSpeciesPatch(",
            "reviewService.syncReview(mutation)",
            "dependencies.sendPostRefresh(postID)",
            "dependencies.processIdentificationUpdate(mutation.scanID)"
        ] {
            #expect(coordinator.contains(token))
        }
        #expect(!coordinator.contains("localReviewState:"))
        for token in [
            "BackgroundDatabaseActor", "AppDIContainer",
            "ExploreShareStateStore", "Task.detached", "@unchecked Sendable",
            ".from(\"", ".rpc("
        ] {
            #expect(!coordinator.contains(token))
        }
        #expect(
            coordinator.range(
                of: #"\.shared\b"#,
                options: .regularExpression
            ) == nil
        )
        for token in [
            "func applyOverride(",
            "func confirm(",
            "func reset(",
            "func hydrateDisplayedSpecies(",
            "resolveDisplayedSpecies(",
            "enqueueOverrideAdmission(",
            "enqueueReviewMutation(",
            "enqueueFlagReset(",
            "enqueueSpeciesPatch(",
            "replaceAndAwaitTask(in: .review)",
            "callbacks.applyPresentation(",
            "callbacks.speciesHydration"
        ] {
            #expect(workflow.contains(token))
        }
        #expect(
            !workflow.contains("let currentSpeciesData:"),
            "The workflow must use the hydration callback bundle's single presentation source"
        )
        #expect(
            !workflow.contains("let currentPresentationGeneration:"),
            "The workflow must use the hydration callback bundle's single generation source"
        )
        #expect(
            workflow.contains(
                "callbacks.speciesHydration.currentSpeciesData()"
            )
        )
        #expect(
            workflow.contains(
                "callbacks.speciesHydration\n            .currentPresentationGeneration()"
            )
        )
        for token in [
            "BackgroundDatabaseActor", "AppDIContainer",
            "ExploreShareStateStore", "Task.detached", "@unchecked Sendable",
            "MerianNetworkClient", ".from(\"", ".rpc(", ".shared"
        ] {
            #expect(!workflow.contains(token))
        }
        for token in [
            "BackgroundDatabaseActor(",
            "userReviewState: mutation.userReviewState",
            "ExploreShareStateStore.sharedPostId(for:",
            "AppDIContainer.shared.appEventPublisher",
            "AppDIContainer.shared.scanMilestoneCoordinator",
            "static func composed("
        ] {
            #expect(liveCoordinator.contains(token))
        }
        for token in [
            "MerianNetworkClient", "BackgroundDatabaseActor", "ModelContext",
            "AppDIContainer", "ExploreShareStateStore", "Task {",
            "Task.detached", "await ", ".shared"
        ] {
            #expect(!presentation.contains(token))
        }

        let reviewSectionStart = try #require(engine.range(
            of: "// MARK: - Identification Override"
        ))
        let reviewSectionEnd = try #require(engine.range(
            of: "// MARK: - Pipeline Modifiers",
            range: reviewSectionStart.upperBound..<engine.endIndex
        ))
        let reviewSection = engine[
            reviewSectionStart.lowerBound..<reviewSectionEnd.lowerBound
        ]
        for token in [
            "BackgroundDatabaseActor(", "AppDIContainer.shared",
            "ExploreShareStateStore", "identificationReviewService.",
            "identificationReviewSnapshotService.",
            "syncIdentificationReviewToCloud(",
            "IdentificationReviewPresentation.",
            "identificationReviewCoordinator.",
            "InferenceIdentificationReviewMutation(",
            ".userOverride(",
            ".aiConfirmation(",
            ".reset(scanID:",
            "replaceAndAwaitTask("
        ] {
            #expect(!reviewSection.contains(token))
        }
        for delegation in [
            "identificationReviewWorkflowCoordinator.applyOverride(",
            "identificationReviewWorkflowCoordinator.confirm(",
            "identificationReviewWorkflowCoordinator.reset("
        ] {
            #expect(reviewSection.contains(delegation))
        }

        let confirmationStart = try #require(workflow.range(
            of: "func confirm("
        ))
        let resetStart = try #require(workflow.range(
            of: "func reset("
        ))
        let confirmation = workflow[
            confirmationStart.lowerBound..<resetStart.lowerBound
        ]
        let confirmationRead = try #require(confirmation.range(
            of: "reviewCoordinator.loadSnapshot("
        ))
        let confirmationMutation = try #require(confirmation.range(
            of: "reviewCoordinator.beginConfirmationAction("
        ))
        #expect(confirmationRead.lowerBound < confirmationMutation.lowerBound)

        let reset = workflow[resetStart.lowerBound...]
        let resetRead = try #require(reset.range(
            of: "reviewCoordinator.loadSnapshot("
        ))
        let resetMutation = try #require(reset.range(
            of: "reviewCoordinator.beginReviewAction("
        ))
        #expect(resetRead.lowerBound < resetMutation.lowerBound)

        #expect(appDI.contains("liveInferenceIdentificationReviewService"))
        #expect(appDI.contains("identificationReviewService:"))
        #expect(
            appDI.contains(
                "liveInferenceReviewSnapshotService"
            )
        )
        #expect(appDI.contains("identificationReviewSnapshotService:"))
        #expect(
            appDI.contains(
                "liveInferenceIdentificationReviewDependencies"
            )
        )
        #expect(appDI.contains("identificationReviewDependencies:"))
        #expect(
            appDI.contains(
                "InferenceIdentificationReviewCoordinator.Dependencies.composed("
            )
        )
        #expect(
            service.split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).count <= 600
        )
        #expect(
            workflow.split(
                separator: "\n",
                omittingEmptySubsequences: false
            ).count <= 600
        )
    }

    @Test func recoveryPoliciesRemainStatelessAndEffectFree() throws {
        for path in [
            "Recovery/InferenceLiveFailurePolicy.swift",
            "Recovery/InferenceFailurePresentation.swift"
        ] {
            let source = try contents(of: sourceRoot().appendingPathComponent(path))
            for token in [
                ".shared", "Task {", "Task.detached", "await ",
                "@unchecked Sendable", "import SwiftUI", "import SwiftData",
                "AppTelemetry", "HapticManager", "CircuitBreakerManager",
                "OfflineQueueManager", "AppDIContainer", "ModelContext"
            ] {
                #expect(!source.contains(token), "\(path) must not own \(token)")
            }
        }
        let policy = try contents(of: sourceRoot().appendingPathComponent(
            "Recovery/InferenceLiveFailurePolicy.swift"
        ))
        #expect(policy.contains("private static func providerPolicyFailure("))
        #expect(policy.contains("ScanConnectivityFailurePolicy.isDurableRecoveryFailure(error)"))
    }

    @Test func coordinatorKeepsItsMutableTaskStatePrivate() throws {
        let writeSource = try contents(
            of: sourceRoot().appendingPathComponent(
                "State/InferenceWriteCoordinator.swift"
            )
        )

        for declaration in [
            "private var activeTasks",
            "private var pendingTasks",
            "private var reviewActionGenerations",
            "private var confirmationActionGenerations",
            "private var flagActionGenerations",
            "private var reviewWriteTail"
        ] {
            #expect(writeSource.contains(declaration))
        }

        let hydrationSource = try contents(
            of: sourceRoot().appendingPathComponent(
                "Hydration/InferenceHydrationCoordinator.swift"
            )
        )
        for declaration in [
            "private var activeTasks",
            "private var currentTaskIds",
            "private var wikipediaHydrationSuccesses",
            "private var historicEnrichmentAttempts",
            "private var enrichedSpeciesTimestamps",
            "private var rateLimitedUntil"
        ] {
            #expect(hydrationSource.contains(declaration))
        }
        #expect(hydrationSource.contains("case review"))
        #expect(hydrationSource.contains("func replaceAndAwaitTask("))
        #expect(!hydrationSource.contains("case gbif"))
        #expect(!writeSource.contains("@unchecked Sendable"))
        #expect(!hydrationSource.contains("@unchecked Sendable"))

        let localAnalysisSource = try contents(
            of: sourceRoot().appendingPathComponent(
                "LocalAnalysis/InferenceLocalAnalysisCoordinator.swift"
            )
        )
        for declaration in [
            "private var activeContext",
            "private var classificationTask",
            "private var traitTask",
            "private var foundationCueTask",
            "private var phraseRotationTask",
            "private var analysisImage",
            "private var visionClassification",
            "private var didFinishVisionClassification",
            "private var didSendInferenceRequestBody",
            "private var isPausedForInactivity",
            "private var phraseCoordinator"
        ] {
            #expect(localAnalysisSource.contains(declaration))
        }
        #expect(!localAnalysisSource.contains("@unchecked Sendable"))
    }

    @Test func localAnalysisAggregateIsRetired() throws {
        let legacyFile = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/AI/LocalVisualAnalysis.swift"
        )
        #expect(!FileManager.default.fileExists(atPath: legacyFile.path))

        let coordinatorSource = try contents(
            of: sourceRoot().appendingPathComponent(
                "LocalAnalysis/InferenceLocalAnalysisCoordinator.swift"
            )
        )
        #expect(coordinatorSource.contains("final class InferenceLocalAnalysisCoordinator"))
        #expect(coordinatorSource.contains("func pauseForInactivity"))
        #expect(coordinatorSource.contains("func resumeAfterInactivity"))
        #expect(coordinatorSource.contains("func markInferenceRequestBodySent"))

        let engineSource = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/AI/InferenceEngine.swift"
            )
        )
        #expect(!engineSource.contains("triggerLightImpact(intensity: 0.3)"))

        let appDISource = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/AppDIContainer.swift"
            )
        )
        #expect(appDISource.contains("localAnalysisStartFeedback:"))
        #expect(appDISource.contains("triggerLightImpact(intensity: 0.3)"))
    }

    @Test func hydrationOrchestrationKeepsReferenceWorkStructured() throws {
        let engine = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/Core/AI/InferenceEngine.swift"
            )
        )
        let hydration = try contents(
            of: sourceRoot().appendingPathComponent(
                "Hydration/InferenceSpeciesHydrationCoordinator.swift"
            )
        )
        let speciesPresentation = try contents(
            of: sourceRoot().appendingPathComponent(
                "Hydration/InferenceSpeciesPresentationCoordinator.swift"
            )
        )
        let historicalHydration = try contents(
            of: sourceRoot().appendingPathComponent(
                "Hydration/InferenceHistoricalHydrationCoordinator.swift"
            )
        )
        let reviewWorkflow = try contents(
            of: sourceRoot().appendingPathComponent(
                "IdentificationReview/InferenceReviewWorkflowCoordinator.swift"
            )
        )
        let enrichment = try contents(
            of: sourceRoot().appendingPathComponent(
                "Hydration/InferenceSpeciesEnrichmentCoordinator.swift"
            )
        )
        let enrichmentStart = try #require(
            engine.range(of: "func fetchAndApplyEnrichment(")
        )
        let reviewStart = try #require(
            engine.range(
                of: "// MARK: - Identification Override",
                range: enrichmentStart.upperBound..<engine.endIndex
            )
        )
        let enrichmentFacade = engine[
            enrichmentStart.lowerBound..<reviewStart.lowerBound
        ]
        let liveHydrationStart = try #require(
            speciesPresentation.range(
                of: "func scheduleLiveHydrationIfNeeded("
            )
        )
        let enrichmentDelegateStart = try #require(
            speciesPresentation.range(
                of: "func fetchAndApplyEnrichment(",
                range:
                    liveHydrationStart.upperBound..<speciesPresentation.endIndex
            )
        )
        let liveHydrationFacade = speciesPresentation[
            liveHydrationStart.lowerBound..<enrichmentDelegateStart.lowerBound
        ]

        #expect(
            enrichmentFacade.contains(
                "speciesPresentationCoordinator.fetchAndApplyEnrichment("
            )
        )
        #expect(!enrichmentFacade.contains("withTaskGroup"))
        #expect(
            liveHydrationFacade.contains(
                "speciesHydrationCoordinator.scheduleLiveHydration("
            )
        )
        #expect(
            !liveHydrationFacade.split(separator: "\n").contains {
                $0.trimmingCharacters(in: .whitespaces)
                    .hasPrefix("Task {")
            }
        )
        #expect(!liveHydrationFacade.contains("MainActor.run"))
        #expect(
            speciesPresentation.contains(
                "InferenceSpeciesHydrationCoordinator.Callbacks("
            )
        )
        #expect(!engine.contains("InferenceSpeciesHydrationCoordinator.Callbacks("))
        #expect(hydration.contains("replaceTask(in: .live)"))
        #expect(hydration.contains("await self.fetchAndApplyEnrichment("))
        #expect(hydration.contains("await self.hydrateGBIF("))
        #expect(hydration.contains("recordWikipediaHydrationSuccess("))
        #expect(
            hydration.contains(
                "callbacks.isPresentationCurrent(identity),"
            )
        )
        #expect(
            historicalHydration.contains(
                "taskCoordinator.replaceTask(in: .historic)"
            )
        )
        #expect(
            historicalHydration.contains("await withTaskGroup(of: Void.self)")
        )
        #expect(
            historicalHydration.contains(
                "await callbacks.hydrateDisplayedOverride(override)"
            )
        )
        let enrichmentCall = try #require(
            historicalHydration.range(
                of: "await speciesHydrationCoordinator.fetchAndApplyEnrichment("
            )
        )
        let gbifCall = try #require(
            historicalHydration.range(
                of: "await speciesHydrationCoordinator.hydrateGBIF("
            )
        )
        #expect(enrichmentCall.lowerBound < gbifCall.lowerBound)
        #expect(enrichment.contains("await withTaskGroup(of: Void.self)"))
        #expect(enrichment.contains("allowLookalikesRetry"))
        #expect(
            hydration.contains(
                "ExternalReferenceImagePolicy.sanitizedURL("
            )
        )
        #expect(
            hydration.contains(
                "ExternalReferenceImagePolicy.allowedURLStrings("
            )
        )
        #expect(!engine.contains("func fetchWikipediaAndHydrate("))
        #expect(!engine.contains("func fetchGBIFImagesAndHydrate("))
        #expect(!engine.contains("func hydrateMissingReviewReferenceImages("))
        #expect(!engine.contains("replaceTask(in: .historic)"))
        #expect(!engine.contains("beginHistoricEnrichmentAttempt("))
        #expect(!engine.contains("enrichOnCacheMiss:"))
        #expect(!engine.contains("replacingSpeciesIdentity:"))
        #expect(!engine.contains("channel: .confirmation"))
        #expect(reviewWorkflow.contains("enrichOnCacheMiss: false"))
        #expect(reviewWorkflow.contains("replacingSpeciesIdentity: false"))
        #expect(reviewWorkflow.contains("channel: .confirmation"))
    }

    @Test func identificationReviewKeepsAdmissionAndHydrationOrdering() throws {
        let source = try contents(
            of: sourceRoot().appendingPathComponent(
                "IdentificationReview/InferenceReviewWorkflowCoordinator.swift"
            )
        )
        let applyStart = try #require(
            source.range(of: "func applyOverride(")
        )
        let confirmStart = try #require(
            source.range(
                of: "func confirm(",
                range: applyStart.upperBound..<source.endIndex
            )
        )
        let resetStart = try #require(
            source.range(
                of: "func reset(",
                range: confirmStart.upperBound..<source.endIndex
            )
        )
        let applySource = source[
            applyStart.lowerBound..<confirmStart.lowerBound
        ]
        let admissionAwait = try #require(
            applySource.range(of: "await admission?.value")
        )
        let hydrationStart = try #require(
            applySource.range(of: "replaceAndAwaitTask(")
        )
        let admissionStart = try #require(
            applySource.range(of: "enqueueOverrideAdmission(")
        )
        #expect(admissionStart.lowerBound < admissionAwait.lowerBound)
        #expect(admissionAwait.lowerBound < hydrationStart.lowerBound)

        let confirmationSource = source[
            confirmStart.lowerBound..<resetStart.lowerBound
        ]
        #expect(confirmationSource.contains("channel: .confirmation"))
        #expect(
            confirmationSource.contains(
                "current.userIdentificationOverride == nil"
            )
        )
        #expect(
            !confirmationSource.contains("beginReviewAction(")
        )

        let fallbackStart = try #require(
            source.range(
                of: "let speciesID = await reviewCoordinator.loadSpeciesIDIfAvailable("
            )
        )
        let fallbackReturn = try #require(
            source.range(
                of: "return speciesID",
                range: fallbackStart.upperBound..<source.endIndex
            )
        )
        let postFallbackFence = source[
            fallbackStart.lowerBound..<fallbackReturn.lowerBound
        ]
        #expect(postFallbackFence.contains("guard !Task.isCancelled,"))
        #expect(
            postFallbackFence.contains("isCurrent(identity, callbacks: callbacks)")
        )
    }

    private func sourceRoot() throws -> URL {
        try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/AI/Inference"
        )
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("project.yml").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }
}

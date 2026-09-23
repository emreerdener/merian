import Foundation
import SwiftData

/// Adapts live-pipeline outcomes into the focused presentation owners.
///
/// The execution coordinator retains request, result, and follow-up ordering;
/// this owner is the sole production constructor of its presentation callbacks.
/// It synchronously fences persisted-media projection and successful
/// publication, routes typed failures, and preserves the captured hydration and
/// local-analysis context. A queue-less response transfers its pending render
/// clock from the process-local request ID to the authoritative server scan ID.
/// The coordinator owns no networking, persistence, tasks, or observable state
/// of its own.
@MainActor
final class InferenceLivePresentationCoordinator {
    private let attemptCoordinator: InferenceLiveAttemptCoordinator
    private let sessionLifecycleCoordinator:
        InferenceSessionLifecycleCoordinator
    private let presentationState: InferencePresentationState
    private let speciesPresentationCoordinator:
        InferenceSpeciesPresentationCoordinator
    private let completionCoordinator: InferenceLiveCompletionCoordinator
    private let localAnalysisCoordinator: InferenceLocalAnalysisCoordinator

    init(
        attemptCoordinator: InferenceLiveAttemptCoordinator,
        sessionLifecycleCoordinator: InferenceSessionLifecycleCoordinator,
        presentationState: InferencePresentationState,
        speciesPresentationCoordinator:
            InferenceSpeciesPresentationCoordinator,
        completionCoordinator: InferenceLiveCompletionCoordinator,
        localAnalysisCoordinator: InferenceLocalAnalysisCoordinator
    ) {
        self.attemptCoordinator = attemptCoordinator
        self.sessionLifecycleCoordinator = sessionLifecycleCoordinator
        self.presentationState = presentationState
        self.speciesPresentationCoordinator = speciesPresentationCoordinator
        self.completionCoordinator = completionCoordinator
        self.localAnalysisCoordinator = localAnalysisCoordinator
    }

    func makeCallbacks(
        for session: InferenceLivePipelineCoordinator.Session,
        persistedMediaItems:
            @escaping @MainActor ([String]) -> [MediaItem]?,
        modelContainer: ModelContainer?,
        referencePolicy:
            InferenceSpeciesHydrationCoordinator.ReferencePolicy
    ) -> InferenceLivePipelineCoordinator.Callbacks {
        InferenceLivePipelineCoordinator.Callbacks(
            finish: { [weak self] session in
                self?.sessionLifecycleCoordinator
                    .finishLivePipelinePresentation(
                        attemptGeneration: session.attemptGeneration
                    )
            },
            publishCompletion: { [weak self] completion in
                guard let self else { return false }
                return self.commitSuccessfulResult(
                    for: session.scanId,
                    firstRenderMetricScanId: session.resolvedClientScanId,
                    attemptGeneration: session.attemptGeneration,
                    foregroundInferenceGeneration:
                        session.foregroundGeneration,
                    speciesData: completion.speciesData,
                    comparisonCapture: completion.comparisonCapture,
                    resolvePersistedMediaItems: {
                        persistedMediaItems(completion.savedImagePaths)
                    }
                )
            },
            scheduleHydration: { [weak self] speciesData in
                self?.speciesPresentationCoordinator
                    .scheduleLiveHydrationIfNeeded(
                        for: speciesData,
                        modelContainer: modelContainer,
                        referencePolicy: referencePolicy
                    )
            },
            applyFailure: { [weak self] action in
                self?.applyFailurePresentation(action)
            }
        )
    }

    func makeVisualCallbacks(
        for session: InferenceLivePipelineCoordinator.Session,
        persistedMediaItems:
            @escaping @MainActor ([String]) -> [MediaItem]?,
        modelContainer: ModelContainer?,
        referencePolicy:
            InferenceSpeciesHydrationCoordinator.ReferencePolicy
    ) -> InferenceLivePipelineCoordinator.VisualCallbacks {
        InferenceLivePipelineCoordinator.VisualCallbacks(
            shared: makeCallbacks(
                for: session,
                persistedMediaItems: persistedMediaItems,
                modelContainer: modelContainer,
                referencePolicy: referencePolicy
            ),
            cancelLocalAnalysis: { [weak self] in
                self?.localAnalysisCoordinator.cancel(
                    resetPhraseCoordinator: false
                )
            },
            markRequestBodySent: { @MainActor [weak self] session in
                self?.localAnalysisCoordinator.markInferenceRequestBodySent(
                    for: InferenceLocalAnalysisCoordinator.Session(
                        scanId: session.scanId,
                        attemptGeneration: session.attemptGeneration,
                        foregroundGeneration: session.foregroundGeneration
                    )
                )
            }
        )
    }

    @discardableResult
    func commitSuccessfulResult(
        for scanId: String?,
        attemptGeneration: UUID,
        foregroundInferenceGeneration: UUID?,
        speciesData: SpeciesData,
        persistedMediaItems: [MediaItem]?
    ) -> Bool {
        commitSuccessfulResult(
            for: scanId,
            firstRenderMetricScanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundInferenceGeneration: foregroundInferenceGeneration,
            speciesData: speciesData,
            resolvePersistedMediaItems: { persistedMediaItems }
        )
    }

    private func commitSuccessfulResult(
        for scanId: String?,
        firstRenderMetricScanId: String?,
        attemptGeneration: UUID,
        foregroundInferenceGeneration: UUID?,
        speciesData: SpeciesData,
        comparisonCapture: IdentificationComparisonCapture? = nil,
        resolvePersistedMediaItems: @MainActor () -> [MediaItem]?
    ) -> Bool {
        guard attemptCoordinator.isAttemptCurrent(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            foregroundGeneration: foregroundInferenceGeneration
        ) else {
            return false
        }

        if scanId == nil,
           let firstRenderMetricScanId,
           let resultScanId = speciesData.scanId {
            sessionLifecycleCoordinator.rebindFirstRenderMetric(
                from: firstRenderMetricScanId,
                to: resultScanId
            )
        }

        sessionLifecycleCoordinator.publishSuccessfulResult(
            speciesData,
            persistedMediaItems: resolvePersistedMediaItems()
        )
        if let comparisonCapture, comparisonCapture.matches(scanId: speciesData.scanId),
           let resultScanId = speciesData.scanId {
            sessionLifecycleCoordinator.armComparisonRender(comparisonCapture, scanId: resultScanId)
        }
        completionCoordinator.publishForegroundCompletionEventIfNeeded(
            for: speciesData
        )
        return true
    }

    private func applyFailurePresentation(
        _ action: InferenceLiveFailureCoordinator.PresentationAction
    ) {
        switch action {
        case .retainRecoverableScan(let scanId):
            attemptCoordinator.setRecoverablePresentationScanId(scanId)
        case .transitionToQueue(let scanId, let attemptGeneration):
            _ = sessionLifecycleCoordinator.transitionToQueue(
                scanId: scanId,
                source: .active(attemptGeneration: attemptGeneration),
                activeVisualPhrases: localAnalysisCoordinator.handoffPhraseDeck
            )
        case .publishFailure(let failureData):
            presentationState.replaceSpeciesData(failureData)
        }
    }
}

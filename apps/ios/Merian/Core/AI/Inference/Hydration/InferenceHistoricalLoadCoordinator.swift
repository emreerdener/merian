import Foundation
import SwiftData

/// Starts one persisted-record presentation and its registered hydration work.
///
/// This coordinator owns the synchronous historical-load sequence across the
/// existing lifecycle, attempt, presentation, review, and hydration owners. It
/// creates no task, resolves no live dependency, and retains no managed record
/// after `load(from:)` returns.
@MainActor
final class InferenceHistoricalLoadCoordinator {
    private let attemptCoordinator: InferenceLiveAttemptCoordinator
    private let sessionLifecycleCoordinator:
        InferenceSessionLifecycleCoordinator
    private let presentationState: InferencePresentationState
    private let writeCoordinator: InferenceWriteCoordinator
    private let speciesPresentationCoordinator:
        InferenceSpeciesPresentationCoordinator
    private let historicalHydrationCoordinator:
        InferenceHistoricalHydrationCoordinator
    private let lookalikeCacheResetService:
        InferenceLookalikeCacheResetService
    private let reviewWorkflowCoordinator:
        InferenceReviewWorkflowCoordinator

    init(
        attemptCoordinator: InferenceLiveAttemptCoordinator,
        sessionLifecycleCoordinator:
            InferenceSessionLifecycleCoordinator,
        presentationState: InferencePresentationState,
        writeCoordinator: InferenceWriteCoordinator,
        speciesPresentationCoordinator:
            InferenceSpeciesPresentationCoordinator,
        historicalHydrationCoordinator:
            InferenceHistoricalHydrationCoordinator,
        lookalikeCacheResetService:
            InferenceLookalikeCacheResetService,
        reviewWorkflowCoordinator:
            InferenceReviewWorkflowCoordinator
    ) {
        self.attemptCoordinator = attemptCoordinator
        self.sessionLifecycleCoordinator = sessionLifecycleCoordinator
        self.presentationState = presentationState
        self.writeCoordinator = writeCoordinator
        self.speciesPresentationCoordinator = speciesPresentationCoordinator
        self.historicalHydrationCoordinator = historicalHydrationCoordinator
        self.lookalikeCacheResetService = lookalikeCacheResetService
        self.reviewWorkflowCoordinator = reviewWorkflowCoordinator
    }

    func load(from record: LocalScanRecord) {
        guard sessionLifecycleCoordinator.beginHistoricalLoad() else { return }

        attemptCoordinator.setActiveScanId(record.id)

        // Release large live-capture buffers before faulting and projecting the
        // persisted record so both presentations are never retained together.
        presentationState.releaseLiveMedia()

        let modelContainer = record.modelContext?.container
        let projection = InferenceHistoricalRecordProjection(
            record: record,
            resetLocalLookalikes: lookalikeCacheResetService.needsReset
        )
        if projection.hydrationPlan.shouldResetLocalLookalikes {
            lookalikeCacheResetService.scheduleIfNeeded(in: modelContainer)
        }

        presentationState.publishHistoricalProjection(
            media: projection.mediaSnapshot.activeScanMedia,
            speciesData: projection.speciesData
        )
        let presentationGeneration = writeCoordinator.generation
        let reviewActionGeneration =
            speciesPresentationCoordinator.beginReviewAction(
                scanId: projection.scanId
            )
        let reviewCallbacks = speciesPresentationCoordinator
            .makeReviewWorkflowCallbacks()

        historicalHydrationCoordinator.scheduleHydration(
            .init(
                projection: projection,
                modelContainer: modelContainer,
                presentationGeneration: presentationGeneration,
                reviewActionGeneration: reviewActionGeneration
            ),
            callbacks: .init(
                speciesHydration: reviewCallbacks.speciesHydration,
                hydrateDisplayedOverride: { [weak self] override in
                    guard let self else { return }
                    _ = await self.reviewWorkflowCoordinator
                        .hydrateDisplayedSpecies(
                            .init(
                                scientificName: override,
                                scanID: projection.scanId,
                                modelContainer: modelContainer,
                                presentationGeneration:
                                    presentationGeneration,
                                reviewActionGeneration:
                                    reviewActionGeneration
                            ),
                            callbacks: reviewCallbacks
                        )
                }
            )
        )
    }
}

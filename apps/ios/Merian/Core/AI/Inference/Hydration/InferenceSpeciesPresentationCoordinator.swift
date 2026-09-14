import Foundation
import SwiftData

/// Bridges species hydration with the exact observable inference presentation.
///
/// This owner builds the single callback bundle shared by live, historical,
/// enrichment, and identification-review flows. It owns no task registry,
/// network transport, persistence implementation, or observable state of its
/// own; those responsibilities remain in its injected focused owners.
@MainActor
final class InferenceSpeciesPresentationCoordinator {
    private let presentationState: InferencePresentationState
    private let writeCoordinator: InferenceWriteCoordinator
    private let reviewCoordinator: InferenceIdentificationReviewCoordinator
    private let speciesHydrationCoordinator:
        InferenceSpeciesHydrationCoordinator

    init(
        presentationState: InferencePresentationState,
        writeCoordinator: InferenceWriteCoordinator,
        reviewCoordinator: InferenceIdentificationReviewCoordinator,
        speciesHydrationCoordinator: InferenceSpeciesHydrationCoordinator
    ) {
        self.presentationState = presentationState
        self.writeCoordinator = writeCoordinator
        self.reviewCoordinator = reviewCoordinator
        self.speciesHydrationCoordinator = speciesHydrationCoordinator
    }

    func beginReviewAction(scanId: String) -> UInt64 {
        reviewCoordinator.beginReviewAction(scanId: scanId)
    }

    func markAlternativesExhausted(expectedScanId: String?) {
        guard let scanId = presentationState.speciesData?.scanId,
              expectedScanId == nil ||
              expectedScanId?.caseInsensitiveCompare(scanId) == .orderedSame else {
            return
        }
        _ = beginReviewAction(scanId: scanId)
        presentationState.markAlternativesExhausted()
    }

    func makeHydrationCallbacks()
        -> InferenceSpeciesHydrationCoordinator.Callbacks {
        InferenceSpeciesHydrationCoordinator.Callbacks(
            currentSpeciesData: { [weak self] in
                self?.presentationState.speciesData
            },
            currentReferenceState: { [weak self] in
                self?.presentationState.activeMedia.referenceState ?? .empty
            },
            currentPresentationGeneration: { [weak self] in
                self?.writeCoordinator.generation ?? 0
            },
            isPresentationCurrent: { [weak self] identity in
                self?.isPresentationCurrent(identity) ?? false
            },
            publishSpeciesData: { [weak self] data in
                self?.presentationState.replaceSpeciesData(data)
            },
            publishReferenceState: { [weak self] state in
                self?.presentationState.replaceReferenceState(state)
            },
            setLoading: { [weak self] scope, isLoading in
                self?.setLoading(scope, isLoading: isLoading)
            },
            enqueuePersistence: { [weak self] work in
                self?.enqueuePersistence(work)
            }
        )
    }

    func makeReviewWorkflowCallbacks()
        -> InferenceReviewWorkflowCoordinator.Callbacks {
        .init(
            applyPresentation: { [weak self] action in
                self?.applyReviewPresentation(action)
            },
            speciesHydration: makeHydrationCallbacks()
        )
    }

    func scheduleLiveHydrationIfNeeded(
        for speciesData: SpeciesData,
        modelContainer: ModelContainer?,
        referencePolicy:
            InferenceSpeciesHydrationCoordinator.ReferencePolicy
    ) {
        guard speciesData.hasResolvedBiologicalIdentification,
              !speciesData.isHumanSubject,
              let scanId = speciesData.scanId else {
            return
        }

        let reviewActionGeneration = beginReviewAction(scanId: scanId)
        speciesHydrationCoordinator.scheduleLiveHydration(
            .init(
                speciesData: speciesData,
                modelContainer: modelContainer,
                referencePolicy: referencePolicy,
                presentationGeneration: writeCoordinator.generation,
                reviewActionGeneration: reviewActionGeneration
            ),
            callbacks: makeHydrationCallbacks()
        )
    }

    func fetchAndApplyEnrichment(
        _ request: InferenceSpeciesHydrationCoordinator.EnrichmentRequest
    ) async {
        await speciesHydrationCoordinator.fetchAndApplyEnrichment(
            request,
            callbacks: makeHydrationCallbacks()
        )
    }

    private func isPresentationCurrent(
        _ identity: InferenceSpeciesHydrationCoordinator.Identity
    ) -> Bool {
        guard let current = presentationState.speciesData,
              current.scanId?.caseInsensitiveCompare(identity.scanId)
                == .orderedSame,
              current.scientificName.caseInsensitiveCompare(
                  identity.scientificName
              ) == .orderedSame,
              writeCoordinator.generation
                == identity.presentationGeneration else {
            return false
        }
        guard let reviewActionGeneration = identity.reviewActionGeneration else {
            return true
        }
        return reviewCoordinator.isReviewActionCurrent(
            scanId: identity.scanId,
            generation: reviewActionGeneration
        )
    }

    private func applyReviewPresentation(
        _ action: IdentificationReviewPresentation.Action
    ) {
        presentationState.replaceSpeciesData(action.speciesData)
        if let referenceState = action.referenceState {
            presentationState.replaceReferenceState(referenceState)
        }
    }

    private func setLoading(
        _ scope: InferenceSpeciesHydrationCoordinator.LoadingScope,
        isLoading: Bool
    ) {
        switch scope {
        case .metadata:
            presentationState.setEnrichmentLoading(isLoading)
        case .lookalikes:
            presentationState.setLookalikesLoading(isLoading)
        }
    }

    private func enqueuePersistence(
        _ work: InferenceSpeciesHydrationCoordinator.PersistenceWork
    ) {
        guard !writeCoordinator.isAuthTransitionFenceActive else { return }
        let guardedOperation: @Sendable () async -> Void = { [weak self] in
            guard !Task.isCancelled,
                  let self,
                  await self.isPresentationCurrent(work.identity) else {
                return
            }
            await work.operation()
        }

        if let reviewActionGeneration = work.identity.reviewActionGeneration {
            reviewCoordinator.enqueueWrite(
                scanId: work.identity.scanId,
                actionGeneration: reviewActionGeneration,
                operation: guardedOperation
            )
        } else {
            writeCoordinator.enqueueBackgroundWrite(guardedOperation)
        }
    }
}

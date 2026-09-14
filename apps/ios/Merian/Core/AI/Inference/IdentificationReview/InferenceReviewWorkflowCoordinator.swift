import Foundation
import SwiftData

/// Owns the complete interactive identification-review workflow.
///
/// The coordinator sequences local admission, presentation replacement,
/// dictionary resolution, serialized review writes, and tracked species-media
/// hydration. `InferenceSpeciesPresentationCoordinator` exposes the observable
/// presentation-state owner only through narrow callbacks.
@MainActor
final class InferenceReviewWorkflowCoordinator {
    struct OverrideRequest {
        let scientificName: String
        let expectedScanID: String?
        let modelContainer: ModelContainer?
    }

    struct ConfirmationRequest {
        let expectedScanID: String?
        let modelContext: ModelContext?
    }

    struct ResetRequest {
        let expectedScanID: String?
        let modelContext: ModelContext?
    }

    struct DisplayedSpeciesHydrationRequest {
        let scientificName: String
        let scanID: String
        let modelContainer: ModelContainer?
        let presentationGeneration: UInt64
        let reviewActionGeneration: UInt64
    }

    struct Callbacks: Sendable {
        let applyPresentation:
            @MainActor @Sendable (
                IdentificationReviewPresentation.Action
            ) -> Void
        let speciesHydration:
            InferenceSpeciesHydrationCoordinator.Callbacks
    }

    private let reviewCoordinator:
        InferenceIdentificationReviewCoordinator
    private let taskCoordinator: InferenceHydrationCoordinator
    private let speciesHydrationCoordinator:
        InferenceSpeciesHydrationCoordinator

    init(
        reviewCoordinator: InferenceIdentificationReviewCoordinator,
        taskCoordinator: InferenceHydrationCoordinator,
        speciesHydrationCoordinator:
            InferenceSpeciesHydrationCoordinator
    ) {
        self.reviewCoordinator = reviewCoordinator
        self.taskCoordinator = taskCoordinator
        self.speciesHydrationCoordinator = speciesHydrationCoordinator
    }

    func applyOverride(
        _ request: OverrideRequest,
        callbacks: Callbacks
    ) async {
        guard !reviewCoordinator.isAuthTransitionFenceActive,
              let current = callbacks.speciesHydration.currentSpeciesData(),
              let scanID = current.scanId,
              matchesExpectedScan(request.expectedScanID, scanID: scanID) else {
            return
        }

        let reviewGeneration = reviewCoordinator.beginReviewAction(
            scanId: scanID
        )
        _ = reviewCoordinator.beginFlagAction(scanId: scanID)
        let presentationGeneration = callbacks.speciesHydration
            .currentPresentationGeneration()
        let identity = InferenceSpeciesHydrationCoordinator.Identity(
            scanId: scanID,
            scientificName: request.scientificName,
            presentationGeneration: presentationGeneration,
            reviewActionGeneration: reviewGeneration
        )
        cancelSpeciesHydration(callbacks: callbacks)

        callbacks.applyPresentation(
            IdentificationReviewPresentation.override(
                current,
                scientificName: request.scientificName
            )
        )

        let admission = request.modelContainer.flatMap { container in
            reviewCoordinator.enqueueOverrideAdmission(
                scanId: scanID,
                scientificName: request.scientificName,
                actionGeneration: reviewGeneration,
                modelContainer: container
            )
        }
        await admission?.value
        guard isCurrent(identity, callbacks: callbacks) else { return }

        let scientificName = request.scientificName
        let modelContainer = request.modelContainer
        await taskCoordinator.replaceAndAwaitTask(in: .review) { [weak self] in
            guard let self else { return }
            let confirmedSpeciesID = await self.resolveDisplayedSpecies(
                scientificName: scientificName,
                identity: identity,
                modelContainer: modelContainer,
                restoringAIReasoning: nil,
                enrichOnCacheMiss: true,
                replacingSpeciesIdentity: true,
                callbacks: callbacks
            )
            guard !Task.isCancelled,
                  self.isCurrent(identity, callbacks: callbacks) else {
                return
            }

            self.reviewCoordinator.enqueueReviewMutation(
                .userOverride(
                    scanID: scanID,
                    scientificName: scientificName,
                    confirmedSpeciesID: confirmedSpeciesID
                ),
                actionGeneration: reviewGeneration,
                modelContainer: modelContainer
            )

            await self.speciesHydrationCoordinator
                .hydrateMissingReferenceImages(
                    identity: identity,
                    modelContainer: modelContainer,
                    callbacks: callbacks.speciesHydration
                )
        }
    }

    func confirm(
        _ request: ConfirmationRequest,
        callbacks: Callbacks
    ) async {
        guard !reviewCoordinator.isAuthTransitionFenceActive,
              let current = callbacks.speciesHydration.currentSpeciesData(),
              let scanID = current.scanId,
              current.userIdentificationOverride == nil,
              matchesExpectedScan(request.expectedScanID, scanID: scanID) else {
            return
        }

        let confirmedSpeciesID: String?
        if let modelContext = request.modelContext {
            switch reviewCoordinator.loadSnapshot(
                scanId: scanID,
                modelContext: modelContext,
                purpose: .confirmation
            ) {
            case .success(let snapshot):
                confirmedSpeciesID = snapshot?.speciesId
            case .failure:
                return
            }
        } else {
            confirmedSpeciesID = nil
        }

        let actionGeneration = reviewCoordinator.beginConfirmationAction(
            scanId: scanID
        )
        taskCoordinator.cancelCurrentTask(in: .review)
        callbacks.applyPresentation(
            IdentificationReviewPresentation.confirmation(current)
        )
        reviewCoordinator.enqueueReviewMutation(
            .aiConfirmation(
                scanID: scanID,
                confirmedSpeciesID: confirmedSpeciesID
            ),
            actionGeneration: actionGeneration,
            channel: .confirmation,
            modelContainer: request.modelContext?.container
        )
    }

    func reset(
        _ request: ResetRequest,
        callbacks: Callbacks
    ) async {
        guard !reviewCoordinator.isAuthTransitionFenceActive,
              let current = callbacks.speciesHydration.currentSpeciesData(),
              let scanID = current.scanId,
              matchesExpectedScan(request.expectedScanID, scanID: scanID),
              !current.aiScientificName.isEmpty else {
            return
        }

        let originalAIReasoning: String?
        if let modelContext = request.modelContext {
            switch reviewCoordinator.loadSnapshot(
                scanId: scanID,
                modelContext: modelContext,
                purpose: .reset
            ) {
            case .success(let snapshot):
                originalAIReasoning = snapshot?.aiReasoning
            case .failure:
                return
            }
        } else {
            originalAIReasoning = nil
        }

        let scientificName = current.aiScientificName
        let reviewGeneration = reviewCoordinator.beginReviewAction(
            scanId: scanID
        )
        let flagGeneration = reviewCoordinator.beginFlagAction(scanId: scanID)
        let presentationGeneration = callbacks.speciesHydration
            .currentPresentationGeneration()
        let identity = InferenceSpeciesHydrationCoordinator.Identity(
            scanId: scanID,
            scientificName: scientificName,
            presentationGeneration: presentationGeneration,
            reviewActionGeneration: reviewGeneration
        )
        cancelSpeciesHydration(callbacks: callbacks)

        let restoredReasoning = originalAIReasoning
            ?? current.aiReasoning
            ?? ""
        callbacks.applyPresentation(
            IdentificationReviewPresentation.reset(
                current,
                scientificName: scientificName,
                aiReasoning: restoredReasoning
            )
        )

        let modelContainer = request.modelContext?.container
        if let modelContainer {
            reviewCoordinator.enqueueFlagReset(
                scanId: scanID,
                actionGeneration: flagGeneration,
                modelContainer: modelContainer
            )
        }
        reviewCoordinator.enqueueReviewMutation(
            .reset(scanID: scanID),
            actionGeneration: reviewGeneration,
            modelContainer: modelContainer
        )

        await taskCoordinator.replaceAndAwaitTask(in: .review) { [weak self] in
            guard let self else { return }
            _ = await self.resolveDisplayedSpecies(
                scientificName: scientificName,
                identity: identity,
                modelContainer: modelContainer,
                restoringAIReasoning: restoredReasoning,
                enrichOnCacheMiss: true,
                replacingSpeciesIdentity: true,
                callbacks: callbacks
            )
            guard !Task.isCancelled,
                  self.isCurrent(identity, callbacks: callbacks) else {
                return
            }
            await self.speciesHydrationCoordinator
                .hydrateMissingReferenceImages(
                    identity: identity,
                    modelContainer: modelContainer,
                    callbacks: callbacks.speciesHydration
                )
        }
    }

    @discardableResult
    func hydrateDisplayedSpecies(
        _ request: DisplayedSpeciesHydrationRequest,
        callbacks: Callbacks
    ) async -> String? {
        let identity = InferenceSpeciesHydrationCoordinator.Identity(
            scanId: request.scanID,
            scientificName: request.scientificName,
            presentationGeneration: request.presentationGeneration,
            reviewActionGeneration: request.reviewActionGeneration
        )
        return await resolveDisplayedSpecies(
            scientificName: request.scientificName,
            identity: identity,
            modelContainer: request.modelContainer,
            restoringAIReasoning: nil,
            enrichOnCacheMiss: false,
            replacingSpeciesIdentity: false,
            callbacks: callbacks
        )
    }

    private func resolveDisplayedSpecies(
        scientificName: String,
        identity: InferenceSpeciesHydrationCoordinator.Identity,
        modelContainer: ModelContainer?,
        restoringAIReasoning: String?,
        enrichOnCacheMiss: Bool,
        replacingSpeciesIdentity: Bool,
        callbacks: Callbacks
    ) async -> String? {
        let lookup = await reviewCoordinator.loadSpecies(
            scientificName: scientificName
        )
        guard !Task.isCancelled,
              let reviewGeneration = identity.reviewActionGeneration,
              isCurrent(identity, callbacks: callbacks) else {
            return nil
        }

        switch lookup {
        case .record(let record):
            let resolution = IdentificationReviewPresentation
                .dictionaryResolution(
                    record: record,
                    current: callbacks.speciesHydration.currentSpeciesData(),
                    scientificName: scientificName,
                    restoringAIReasoning: restoringAIReasoning,
                    replacingSpeciesIdentity: replacingSpeciesIdentity
                )
            if let action = resolution.action {
                callbacks.applyPresentation(action)
            }
            if let modelContainer {
                reviewCoordinator.enqueueSpeciesPatch(
                    resolution.persistencePatch,
                    scanId: identity.scanId,
                    actionGeneration: reviewGeneration,
                    modelContainer: modelContainer
                )
            }
            return resolution.speciesID
        case .missing:
            if enrichOnCacheMiss {
                await speciesHydrationCoordinator.fetchAndApplyEnrichment(
                    .init(
                        modelContainer: modelContainer,
                        reviewActionGeneration:
                            identity.reviewActionGeneration
                    ),
                    callbacks: callbacks.speciesHydration
                )
            }
        case .failure:
            break
        }

        guard !Task.isCancelled,
              isCurrent(identity, callbacks: callbacks) else {
            return nil
        }
        let speciesID = await reviewCoordinator.loadSpeciesIDIfAvailable(
            scientificName: scientificName
        )
        guard !Task.isCancelled,
              isCurrent(identity, callbacks: callbacks) else {
            return nil
        }
        return speciesID
    }

    private func cancelSpeciesHydration(callbacks: Callbacks) {
        taskCoordinator.cancelAllTasks()
        callbacks.speciesHydration.setLoading(.metadata, false)
        callbacks.speciesHydration.setLoading(.lookalikes, false)
    }

    private func isCurrent(
        _ identity: InferenceSpeciesHydrationCoordinator.Identity,
        callbacks: Callbacks
    ) -> Bool {
        guard !reviewCoordinator.isAuthTransitionFenceActive,
              let reviewGeneration = identity.reviewActionGeneration,
              reviewCoordinator.isReviewActionCurrent(
                  scanId: identity.scanId,
                  generation: reviewGeneration
              ) else {
            return false
        }
        return callbacks.speciesHydration.isPresentationCurrent(identity)
    }

    private func matchesExpectedScan(
        _ expectedScanID: String?,
        scanID: String
    ) -> Bool {
        expectedScanID == nil ||
            expectedScanID?.caseInsensitiveCompare(scanID) == .orderedSame
    }
}

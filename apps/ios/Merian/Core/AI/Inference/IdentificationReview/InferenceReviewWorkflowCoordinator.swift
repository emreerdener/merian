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

    struct Dependencies {
        var syncPendingIdentificationReviews: @MainActor () async -> Void
    }

    private let dependencies: Dependencies
    private let reviewCoordinator:
        InferenceIdentificationReviewCoordinator
    private let taskCoordinator: InferenceHydrationCoordinator
    private let speciesHydrationCoordinator:
        InferenceSpeciesHydrationCoordinator

    init(
        reviewCoordinator: InferenceIdentificationReviewCoordinator,
        taskCoordinator: InferenceHydrationCoordinator,
        speciesHydrationCoordinator:
            InferenceSpeciesHydrationCoordinator,
        dependencies: Dependencies? = nil
    ) {
        self.dependencies = dependencies ?? .live
        self.reviewCoordinator = reviewCoordinator
        self.taskCoordinator = taskCoordinator
        self.speciesHydrationCoordinator = speciesHydrationCoordinator
    }

    func submitOwnerReview(
        action: AIIdentificationReviewRequest.Action, expectedScanID: String?, scientificName: String? = nil,
        modelContext: ModelContext?, callbacks: Callbacks, onLocalSave: (@MainActor () -> Void)? = nil
    ) async {
        guard !reviewCoordinator.isAuthTransitionFenceActive,
              let context = modelContext,
              let current = callbacks.speciesHydration.currentSpeciesData(), let scanID = current.scanId,
              matchesExpectedScan(expectedScanID, scanID: scanID) else { return }
        let generation = callbacks.speciesHydration.currentPresentationGeneration()
        let reviewGeneration = reviewCoordinator.beginReviewAction(scanId: scanID)
        cancelSpeciesHydration(callbacks: callbacks)
        do {
            let state = try IdentificationReviewSyncService().enqueue(scanID: scanID, action: action,
                scientificName: scientificName, context: context)
            var updated = current; updated.aiReview = state
            if state.isUnresolved || action == .undo { updated.userConfirmedIdentification = false }
            callbacks.applyPresentation(.init(speciesData: updated, referenceState: nil))
            onLocalSave?()
            await dependencies.syncPendingIdentificationReviews()
            guard !reviewCoordinator.isAuthTransitionFenceActive,
                  callbacks.speciesHydration.currentPresentationGeneration() == generation,
                  callbacks.speciesHydration.currentSpeciesData()?.scanId == scanID,
                  reviewCoordinator.isReviewActionCurrent(scanId: scanID, generation: reviewGeneration),
                  let record = try IdentificationReviewSyncService.record(scanID, context: ModelContext(context.container)) else { return }
            var refreshed = updated; refreshed.aiReview = record.localAIIdentificationReview
            refreshed.userConfirmedIdentification = record.userConfirmedIdentification
            refreshed.userIdentificationOverride = record.userIdentificationOverride
            refreshed.confirmedSpeciesReview = record.confirmedSpeciesReview
            callbacks.applyPresentation(.init(speciesData: refreshed, referenceState: nil))
        } catch {
            MerianLog.data.error("Identification review could not be saved locally.")
        }
    }

    func applyOverride(
        _ request: OverrideRequest,
        callbacks: Callbacks
    ) async {
        if let current = callbacks.speciesHydration.currentSpeciesData(),
           current.aiReview.authority != nil || current.aiReview.pending != nil {
            await submitOwnerReview(action: .confirmName, expectedScanID: request.expectedScanID,
                scientificName: request.scientificName, modelContext: request.modelContainer.map { ModelContext($0) }, callbacks: callbacks)
            return
        }
        guard !reviewCoordinator.isAuthTransitionFenceActive,
              let current = callbacks.speciesHydration.currentSpeciesData(),
              let scanID = current.scanId,
              matchesExpectedScan(request.expectedScanID, scanID: scanID) else {
            return
        }

        if current.primaryIdentification != nil {
            guard let container = request.modelContainer else { return }
            submitVerified(.userOverride(scanID: scanID, scientificName: request.scientificName, confirmedSpeciesID: nil),
                           current: current, container: container, callbacks: callbacks)
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
        if let current = callbacks.speciesHydration.currentSpeciesData(),
           current.aiReview.authority != nil || current.aiReview.pending != nil {
            await submitOwnerReview(action: .confirmPrimary, expectedScanID: request.expectedScanID,
                modelContext: request.modelContext, callbacks: callbacks)
            return
        }
        guard !reviewCoordinator.isAuthTransitionFenceActive,
              let current = callbacks.speciesHydration.currentSpeciesData(),
              let scanID = current.scanId,
              current.userIdentificationOverride == nil,
              matchesExpectedScan(request.expectedScanID, scanID: scanID) else {
            return
        }

        if let primary = current.primaryIdentification {
            guard primary.value?.resolution == .species, let container = request.modelContext?.container else { return }
            let confirmation = submitVerified(.aiConfirmation(scanID: scanID, confirmedSpeciesID: nil),
                           current: current, container: container, callbacks: callbacks)
            await confirmation?.value
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
        if let current = callbacks.speciesHydration.currentSpeciesData(),
           current.aiReview.authority != nil || current.aiReview.pending != nil {
            await submitOwnerReview(action: .undo, expectedScanID: request.expectedScanID,
                modelContext: request.modelContext, callbacks: callbacks)
            return
        }
        guard !reviewCoordinator.isAuthTransitionFenceActive,
              let current = callbacks.speciesHydration.currentSpeciesData(),
              let scanID = current.scanId,
              matchesExpectedScan(request.expectedScanID, scanID: scanID),
              !current.aiScientificName.isEmpty else {
            return
        }

        if current.primaryIdentification != nil {
            guard let container = request.modelContext?.container else { return }
            submitVerified(.reset(scanID: scanID), current: current, container: container, callbacks: callbacks)
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

        guard current.primaryIdentification == nil || current.hasSpeciesLevelIdentification else { return }
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

    @discardableResult
    private func submitVerified(
        _ mutation: InferenceIdentificationReviewMutation, current: SpeciesData,
        container: ModelContainer, callbacks: Callbacks
    ) -> Task<Void, Never>? {
        guard current.primaryIdentification?.value != nil else { return nil }
        let generation = reviewCoordinator.beginReviewAction(scanId: mutation.scanID)
        let presentationGeneration = callbacks.speciesHydration.currentPresentationGeneration()
        cancelSpeciesHydration(callbacks: callbacks)
        // Optimistic flags are intent only. Keep original AI labels, context and
        // confidence unchanged; verified bytes arrive through the acknowledgement.
        var pending = current
        pending.userIdentificationOverride = mutation.override
        pending.userConfirmedIdentification = mutation.confirmed
        let pendingPresentation = pending
        return reviewCoordinator.enqueueVerifiedReviewMutation(
            mutation, actionGeneration: generation, modelContainer: container,
            didPrepare: {
                guard callbacks.speciesHydration.currentPresentationGeneration() == presentationGeneration,
                      callbacks.speciesHydration.currentSpeciesData()?.scanId == mutation.scanID else { return }
                callbacks.applyPresentation(.init(speciesData: pendingPresentation, referenceState: nil))
            }
        ) { review in
            guard callbacks.speciesHydration.currentPresentationGeneration() == presentationGeneration,
                  var latest = callbacks.speciesHydration.currentSpeciesData(), latest.scanId == mutation.scanID else { return }
            latest.confirmedSpeciesReview = review
            latest.userIdentificationOverride = review.userIdentificationOverride
            latest.userConfirmedIdentification = review.userConfirmedIdentification
            callbacks.applyPresentation(.init(speciesData: latest, referenceState: nil))
        }
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

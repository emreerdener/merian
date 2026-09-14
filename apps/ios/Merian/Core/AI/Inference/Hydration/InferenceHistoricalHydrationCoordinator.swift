import Foundation
import SwiftData

/// Runs deferred historical decoding and species hydration for one immutable
/// persisted-record projection.
///
/// `InferenceHydrationCoordinator` retains the replaceable task.
/// `InferenceHistoricalLoadCoordinator` coordinates synchronous
/// `InferencePresentationState` replacement;
/// `InferenceSpeciesPresentationCoordinator` supplies observable-state and
/// persistence-admission callbacks, while the review workflow supplies
/// displayed-override resolution.
@MainActor
final class InferenceHistoricalHydrationCoordinator {
    struct Request: Sendable {
        let projection: InferenceHistoricalRecordProjection
        let modelContainer: ModelContainer?
        let presentationGeneration: UInt64
        let reviewActionGeneration: UInt64
    }

    struct Callbacks: Sendable {
        let speciesHydration:
            InferenceSpeciesHydrationCoordinator.Callbacks
        let hydrateDisplayedOverride:
            @MainActor @Sendable (_ scientificName: String) async -> Void
    }

    struct Dependencies: Sendable {
        let decodeDeferredContent:
            @Sendable (InferenceHistoricalRecordProjection) async
                -> InferenceHistoricalRecordProjection.DecodedContent

        static let live = Self(
            decodeDeferredContent: { projection in
                await InferenceHistoricalRecordProjection
                    .decodeDeferredContent(projection.deferredContent)
            }
        )
    }

    private let taskCoordinator: InferenceHydrationCoordinator
    private let speciesHydrationCoordinator:
        InferenceSpeciesHydrationCoordinator
    private let dependencies: Dependencies

    init(
        taskCoordinator: InferenceHydrationCoordinator,
        speciesHydrationCoordinator:
            InferenceSpeciesHydrationCoordinator,
        dependencies: Dependencies = .live
    ) {
        self.taskCoordinator = taskCoordinator
        self.speciesHydrationCoordinator = speciesHydrationCoordinator
        self.dependencies = dependencies
    }

    func scheduleHydration(
        _ request: Request,
        callbacks: Callbacks
    ) {
        taskCoordinator.replaceTask(in: .historic) { [weak self] in
            guard let self else { return }
            await self.hydrate(request, callbacks: callbacks)
        }
    }

    private func hydrate(
        _ request: Request,
        callbacks: Callbacks
    ) async {
        let projection = request.projection
        let identity = InferenceSpeciesHydrationCoordinator.Identity(
            scanId: projection.scanId,
            scientificName: projection.displayedScientificName,
            presentationGeneration: request.presentationGeneration,
            reviewActionGeneration: request.reviewActionGeneration
        )
        guard !Task.isCancelled,
              callbacks.speciesHydration.isPresentationCurrent(identity) else {
            return
        }
        let referenceURLs = projection.referenceURLs
        let shouldLoadImages =
            projection.hydrationPlan.allowsReferenceImages &&
            referenceURLs.isEmpty &&
            (projection.gbifTaxonKey != nil ||
                projection.hydrationPlan.needsEnrichment)
        callbacks.speciesHydration.publishReferenceState(
            shouldLoadImages
                ? .loading
                : (referenceURLs.isEmpty
                    ? .empty
                    : .loaded(referenceURLs))
        )
        defer {
            if shouldLoadImages,
               callbacks.speciesHydration.isPresentationCurrent(identity),
               callbacks.speciesHydration.currentReferenceState() == .loading {
                callbacks.speciesHydration.publishReferenceState(.empty)
            }
        }

        let decodedContent = await dependencies.decodeDeferredContent(
            projection
        )
        guard !Task.isCancelled,
              callbacks.speciesHydration.isPresentationCurrent(identity) else {
            return
        }
        if var updated = callbacks.speciesHydration.currentSpeciesData() {
            updated.similarSpecies = decodedContent.similarSpecies
            updated.candidates = decodedContent.candidates
            callbacks.speciesHydration.publishSpeciesData(updated)
        }

        if let override = projection.overrideScientificName,
           projection.hydrationPlan.allowsSpeciesHydration {
            await callbacks.hydrateDisplayedOverride(override)
            guard !Task.isCancelled,
                  callbacks.speciesHydration.isPresentationCurrent(identity) else {
                return
            }
        }

        await withTaskGroup(of: Void.self) { group in
            if projection.hydrationPlan.needsWikipedia {
                group.addTask { @MainActor [weak self] in
                    guard let self, !Task.isCancelled else { return }
                    await self.speciesHydrationCoordinator.hydrateWikipedia(
                        .init(
                            identity: identity,
                            modelContainer: request.modelContainer
                        ),
                        callbacks: callbacks.speciesHydration
                    )
                }
            }

            group.addTask { @MainActor [weak self] in
                guard let self, !Task.isCancelled else { return }
                await self.hydrateEnrichmentAndGBIF(
                    request,
                    identity: identity,
                    callbacks: callbacks.speciesHydration
                )
            }
        }
    }

    private func hydrateEnrichmentAndGBIF(
        _ request: Request,
        identity: InferenceSpeciesHydrationCoordinator.Identity,
        callbacks: InferenceSpeciesHydrationCoordinator.Callbacks
    ) async {
        guard !Task.isCancelled,
              callbacks.isPresentationCurrent(identity) else {
            return
        }
        let projection = request.projection
        var taxonKey = projection.gbifTaxonKey
        let speciesIsEnriched = taskCoordinator.isSpeciesEnriched(
            projection.displayedScientificName
        )
        let plannedScopes = InferenceSpeciesHydrationCoordinator
            .plannedEnrichmentScopes(
                needsMetadata: projection.hydrationPlan.needsMetadata,
                needsLookalikes: projection.hydrationPlan.needsLookalikes,
                speciesIsEnriched: speciesIsEnriched
            )

        if plannedScopes.metadata || plannedScopes.lookalikes,
           taskCoordinator.beginHistoricEnrichmentAttempt(
               scanId: projection.scanId
           ) {
            guard !Task.isCancelled else { return }
            await speciesHydrationCoordinator.fetchAndApplyEnrichment(
                .init(
                    modelContainer: request.modelContainer,
                    needsMetadata: plannedScopes.metadata,
                    needsLookalikes: plannedScopes.lookalikes,
                    reviewActionGeneration:
                        request.reviewActionGeneration
                ),
                callbacks: callbacks
            )
            guard !Task.isCancelled,
                  callbacks.isPresentationCurrent(identity) else {
                return
            }
            if callbacks.currentSpeciesData()?.habitatDescription?
                .trimmedNonEmptyValue != nil,
                InferenceSpeciesHydrationCoordinator
                    .hasUsableLookalikeTaxonomy(
                        callbacks.currentSpeciesData()?.taxonomy
                    ) {
                taskCoordinator.markSpeciesEnriched(
                    projection.displayedScientificName
                )
            }
            taxonKey = callbacks.currentSpeciesData()?.gbifTaxonKey
                ?? taxonKey
        }

        guard !Task.isCancelled,
              callbacks.isPresentationCurrent(identity),
              let taxonKey,
              projection.hydrationPlan.allowsReferenceImages,
              let current = callbacks.currentSpeciesData(),
              current.scientificName.caseInsensitiveCompare(
                  projection.displayedScientificName
              ) == .orderedSame,
              current.scanId?.caseInsensitiveCompare(
                  projection.scanId
              ) == .orderedSame else {
            return
        }
        await speciesHydrationCoordinator.hydrateGBIF(
            .init(
                taxonKey: taxonKey,
                identity: .init(
                    scanId: projection.scanId,
                    scientificName: current.scientificName,
                    presentationGeneration:
                        request.presentationGeneration,
                    reviewActionGeneration:
                        request.reviewActionGeneration
                ),
                modelContainer: request.modelContainer
            ),
            callbacks: callbacks
        )
    }
}

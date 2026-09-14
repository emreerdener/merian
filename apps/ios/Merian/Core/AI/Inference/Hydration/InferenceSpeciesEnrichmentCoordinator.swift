import Foundation
import SwiftData

/// Owns the two independently rendered species-enrichment scopes.
///
/// Metadata and lookalikes publish and persist independently. The parent
/// hydration coordinator retains session lifetime and reference-image order.
@MainActor
final class InferenceSpeciesEnrichmentCoordinator {
    private typealias Callbacks = InferenceSpeciesHydrationCoordinator.Callbacks
    private typealias EnrichmentRequest =
        InferenceSpeciesHydrationCoordinator.EnrichmentRequest
    private typealias FailureScope =
        InferenceSpeciesHydrationCoordinator.FailureScope
    private typealias Identity = InferenceSpeciesHydrationCoordinator.Identity
    private typealias PersistenceWork =
        InferenceSpeciesHydrationCoordinator.PersistenceWork

    private let taskCoordinator: InferenceHydrationCoordinator
    private let enrichmentService: InferenceSpeciesEnrichmentService
    private let persistenceService: InferenceHydrationPersistenceService
    private let dependencies:
        InferenceSpeciesHydrationCoordinator.Dependencies

    init(
        taskCoordinator: InferenceHydrationCoordinator,
        enrichmentService: InferenceSpeciesEnrichmentService,
        persistenceService: InferenceHydrationPersistenceService,
        dependencies: InferenceSpeciesHydrationCoordinator.Dependencies
    ) {
        self.taskCoordinator = taskCoordinator
        self.enrichmentService = enrichmentService
        self.persistenceService = persistenceService
        self.dependencies = dependencies
    }

    func fetchAndApplyEnrichment(
        _ request: InferenceSpeciesHydrationCoordinator.EnrichmentRequest,
        callbacks: InferenceSpeciesHydrationCoordinator.Callbacks
    ) async {
        guard !Task.isCancelled,
              let data = callbacks.currentSpeciesData(),
              let scanId = data.scanId,
              data.isBiological,
              !data.scientificName.isEmpty,
              data.scientificName.lowercased() != "taxonomy unavailable",
              request.needsMetadata || request.needsLookalikes,
              taskCoordinator.canAttemptEnrichment() else {
            return
        }

        if request.needsMetadata {
            callbacks.setLoading(.metadata, true)
        }
        if request.needsLookalikes {
            callbacks.setLoading(.lookalikes, true)
        }

        let identity = Identity(
            scanId: scanId,
            scientificName: data.scientificName,
            presentationGeneration:
                callbacks.currentPresentationGeneration(),
            reviewActionGeneration: request.reviewActionGeneration
        )
        let serviceRequest = InferenceSpeciesEnrichmentService.Request(
            scanId: scanId,
            scientificName: data.scientificName,
            confidenceScore: data.confidenceScore,
            inferenceTier: data.inferenceTier ?? "flash"
        )

        await withTaskGroup(of: Void.self) { group in
            if request.needsMetadata {
                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    await self.fetchMetadata(
                        serviceRequest,
                        identity: identity,
                        modelContainer: request.modelContainer,
                        callbacks: callbacks
                    )
                }
            }

            if request.needsLookalikes {
                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    await self.fetchLookalikes(
                        serviceRequest,
                        identity: identity,
                        modelContainer: request.modelContainer,
                        callbacks: callbacks
                    )
                }
            }
        }

        if !Task.isCancelled,
           request.allowLookalikesRetry,
           request.needsMetadata,
           request.needsLookalikes,
           callbacks.isPresentationCurrent(identity),
           callbacks.currentSpeciesData()?.similarSpecies == nil,
           InferenceSpeciesHydrationCoordinator.hasUsableLookalikeTaxonomy(
               callbacks.currentSpeciesData()?.taxonomy
           ) {
            await fetchAndApplyEnrichment(
                EnrichmentRequest(
                    modelContainer: request.modelContainer,
                    needsMetadata: false,
                    needsLookalikes: true,
                    allowLookalikesRetry: false,
                    reviewActionGeneration:
                        request.reviewActionGeneration
                ),
                callbacks: callbacks
            )
        }
    }

    private func fetchMetadata(
        _ request: InferenceSpeciesEnrichmentService.Request,
        identity: Identity,
        modelContainer: ModelContainer?,
        callbacks: Callbacks
    ) async {
        defer {
            if callbacks.isPresentationCurrent(identity) {
                callbacks.setLoading(.metadata, false)
            }
        }

        do {
            let fetchedPatch = try await enrichmentService
                .fetchMetadata(for: request)
            guard !Task.isCancelled, let patch = fetchedPatch else {
                return
            }
            if var updated = callbacks.currentSpeciesData(),
               callbacks.isPresentationCurrent(identity) {
                updated = patch.applying(to: updated)
                callbacks.publishSpeciesData(updated)
            }

            guard let modelContainer else { return }
            let snapshot = InferenceHydrationPersistenceService.MetadataSnapshot(
                scanId: identity.scanId,
                habitatDescription: patch.habitatDescription,
                gbifTaxonKey: patch.gbifTaxonKey,
                taxonomy: patch.taxonomy,
                alternativeCommonNames:
                    patch.persistedAlternativeCommonNames,
                expectedScientificName: identity.scientificName
            )
            let persistence = persistenceService
            callbacks.enqueuePersistence(PersistenceWork(
                identity: identity,
                operation: {
                    await persistence.persistMetadata(
                        snapshot,
                        in: modelContainer
                    )
                }
            ))
        } catch {
            handleEnrichmentFailure(error, scope: .metadata)
        }
    }

    private func fetchLookalikes(
        _ request: InferenceSpeciesEnrichmentService.Request,
        identity: Identity,
        modelContainer: ModelContainer?,
        callbacks: Callbacks
    ) async {
        defer {
            if callbacks.isPresentationCurrent(identity) {
                callbacks.setLoading(.lookalikes, false)
            }
        }

        do {
            let fetchedPatch = try await enrichmentService
                .fetchLookalikes(for: request)
            guard !Task.isCancelled, let patch = fetchedPatch else {
                return
            }
            if var updated = callbacks.currentSpeciesData(),
               callbacks.isPresentationCurrent(identity) {
                updated = patch.applying(to: updated)
                callbacks.publishSpeciesData(updated)
            }

            guard let modelContainer else { return }
            let snapshot = InferenceHydrationPersistenceService
                .LookalikesSnapshot(
                    scanId: identity.scanId,
                    entries: patch.entries,
                    expectedScientificName: identity.scientificName
                )
            let persistence = persistenceService
            callbacks.enqueuePersistence(PersistenceWork(
                identity: identity,
                operation: {
                    await persistence.persistLookalikes(
                        snapshot,
                        in: modelContainer
                    )
                }
            ))
        } catch {
            handleEnrichmentFailure(error, scope: .lookalikes)
        }
    }

    private func handleEnrichmentFailure(
        _ error: Error,
        scope: FailureScope
    ) {
        guard !Task.isCancelled else { return }
        if case .httpError(let code, _)? = error as? MerianError {
            if code == 403 {
                return
            }
            if code == 429 {
                taskCoordinator.recordEnrichmentRateLimit()
                return
            }
        }
        dependencies.logFailure(scope, error)
    }
}

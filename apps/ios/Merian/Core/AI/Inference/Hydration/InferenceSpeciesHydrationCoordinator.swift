import Foundation
import SwiftData

/// Coordinates reference, enrichment, and lookalike hydration for one exact
/// inference presentation.
///
/// Task lifetime and retry history remain in `InferenceHydrationCoordinator`.
/// `InferenceSpeciesPresentationCoordinator` supplies narrow presentation-state
/// and write-admission callbacks; this owner resolves no live singleton, logger,
/// or database actor.
@MainActor
final class InferenceSpeciesHydrationCoordinator {
    private let taskCoordinator: InferenceHydrationCoordinator
    private let referenceService: SpeciesReferenceHydrationService
    private let persistenceService: InferenceHydrationPersistenceService
    private let enrichmentCoordinator: InferenceSpeciesEnrichmentCoordinator
    private let dependencies: Dependencies

    init(
        taskCoordinator: InferenceHydrationCoordinator,
        referenceService: SpeciesReferenceHydrationService,
        enrichmentService: InferenceSpeciesEnrichmentService,
        persistenceService: InferenceHydrationPersistenceService,
        dependencies: Dependencies
    ) {
        self.taskCoordinator = taskCoordinator
        self.referenceService = referenceService
        self.persistenceService = persistenceService
        self.enrichmentCoordinator = InferenceSpeciesEnrichmentCoordinator(
            taskCoordinator: taskCoordinator,
            enrichmentService: enrichmentService,
            persistenceService: persistenceService,
            dependencies: dependencies
        )
        self.dependencies = dependencies
    }

    nonisolated static func plannedEnrichmentScopes(
        needsMetadata: Bool,
        needsLookalikes: Bool,
        speciesIsEnriched: Bool
    ) -> (metadata: Bool, lookalikes: Bool) {
        (
            metadata: needsMetadata && !speciesIsEnriched,
            lookalikes: needsLookalikes
        )
    }

    static func hasUsableLookalikeTaxonomy(
        _ taxonomy: TaxonomyData?
    ) -> Bool {
        taxonomy?.hasUsableLookalikeValidation == true
    }

    func scheduleLiveHydration(
        _ request: LiveRequest,
        callbacks: Callbacks
    ) {
        let data = request.speciesData
        guard data.hasResolvedBiologicalIdentification,
              !data.isHumanSubject,
              let scanId = data.scanId else {
            return
        }

        let scientificName = data.scientificName
        let identity = Identity(
            scanId: scanId,
            scientificName: scientificName,
            presentationGeneration: request.presentationGeneration,
            reviewActionGeneration: request.reviewActionGeneration
        )
        let capturedGBIFKey = data.gbifTaxonKey
        let capturedHasWikipedia = data.wikipediaOverview != nil
        let shouldShowReferenceLoading =
            request.referencePolicy == .showLoadingWhenReferenceMissing &&
            capturedGBIFKey != nil &&
            Self.referenceURLs(from: data.referenceImageUrl).isEmpty

        taskCoordinator.replaceTask(in: .live) { [weak self] in
            guard let self else { return }
            guard !Task.isCancelled,
                  callbacks.isPresentationCurrent(identity) else {
                return
            }
            defer {
                if shouldShowReferenceLoading,
                   callbacks.isPresentationCurrent(identity),
                   callbacks.currentReferenceState() == .loading {
                    callbacks.publishReferenceState(.empty)
                }
            }

            if shouldShowReferenceLoading {
                callbacks.publishReferenceState(.loading)
            }

            let capturedIsEnriched = self.taskCoordinator
                .isSpeciesEnriched(scientificName)
            let scopes = Self.plannedEnrichmentScopes(
                needsMetadata: true,
                needsLookalikes: true,
                speciesIsEnriched: capturedIsEnriched
            )

            await withTaskGroup(of: Void.self) { group in
                if !capturedHasWikipedia {
                    group.addTask { @MainActor [weak self] in
                        guard let self else { return }
                        await self.hydrateWikipedia(
                            WikipediaRequest(
                                identity: identity,
                                modelContainer: request.modelContainer
                            ),
                            callbacks: callbacks
                        )
                    }
                }

                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    var taxonKey = capturedGBIFKey

                    if scopes.metadata || scopes.lookalikes {
                        await self.fetchAndApplyEnrichment(
                            EnrichmentRequest(
                                modelContainer: request.modelContainer,
                                needsMetadata: scopes.metadata,
                                needsLookalikes: scopes.lookalikes,
                                reviewActionGeneration:
                                    request.reviewActionGeneration
                            ),
                            callbacks: callbacks
                        )
                        taxonKey = callbacks.currentSpeciesData()?.gbifTaxonKey
                            ?? taxonKey
                    }

                    guard !Task.isCancelled, let taxonKey else { return }
                    await self.hydrateGBIF(
                        GBIFRequest(
                            taxonKey: taxonKey,
                            identity: identity,
                            modelContainer: request.modelContainer
                        ),
                        callbacks: callbacks
                    )
                }
            }

            if !capturedIsEnriched,
               !Task.isCancelled,
               callbacks.currentSpeciesData()?.habitatDescription?
                .trimmedNonEmptyValue != nil,
               Self.hasUsableLookalikeTaxonomy(
                   callbacks.currentSpeciesData()?.taxonomy
               ) {
                self.taskCoordinator.markSpeciesEnriched(scientificName)
            }
        }
    }

    func hydrateWikipedia(
        _ request: WikipediaRequest,
        callbacks: Callbacks
    ) async {
        let identity = request.identity
        let species = identity.scientificName
        guard !Task.isCancelled,
              !species.isEmpty,
              species.lowercased() != "taxonomy unavailable",
              species.lowercased() != "unknown subject",
              taskCoordinator.canHydrateWikipedia(for: species) else {
            return
        }

        do {
            let fetchedReference = try await referenceService
                .fetchWikipediaReference(for: species)
            guard !Task.isCancelled,
                  let reference = fetchedReference,
                  let overview = reference.overview else {
                return
            }
            let imageURL = ExternalReferenceImagePolicy.sanitizedURL(
                reference.imageURL
            )
            guard callbacks.isPresentationCurrent(identity),
                  var updated = callbacks.currentSpeciesData() else {
                return
            }

            taskCoordinator.recordWikipediaHydrationSuccess(for: species)
            dependencies.logWikipediaResponse(imageURL)
            updated.wikipediaOverview = overview
            updated.wikipediaUrl = reference.pageURL
            if let imageURL, !imageURL.isEmpty {
                var urls = Self.referenceURLs(from: updated.referenceImageUrl)
                if !urls.contains(imageURL) {
                    urls.insert(imageURL, at: 0)
                }
                let capped = Array(urls.prefix(5))
                updated.referenceImageUrl = capped.joined(separator: ",")
                callbacks.publishReferenceState(.loaded(capped))
                dependencies.logWikipediaApplied(capped)
            }
            callbacks.publishSpeciesData(updated)

            guard let modelContainer = request.modelContainer else { return }
            let snapshot = InferenceHydrationPersistenceService
                .ReferenceSnapshot(
                    scanId: identity.scanId,
                    extract: overview,
                    url: reference.pageURL,
                    imageUrl: updated.referenceImageUrl,
                    expectedScientificName: species
                )
            let persistence = persistenceService
            callbacks.enqueuePersistence(PersistenceWork(
                identity: identity,
                operation: {
                    await persistence.persistReference(
                        snapshot,
                        in: modelContainer
                    )
                }
            ))
        } catch {
            guard !Task.isCancelled else { return }
            dependencies.logFailure(.wikipedia, error)
        }
    }

    func fetchAndApplyEnrichment(
        _ request: EnrichmentRequest,
        callbacks: Callbacks
    ) async {
        await enrichmentCoordinator.fetchAndApplyEnrichment(
            request,
            callbacks: callbacks
        )
    }

    func hydrateGBIF(
        _ request: GBIFRequest,
        callbacks: Callbacks
    ) async {
        guard !Task.isCancelled else { return }
        do {
            let fetchedURLs = try await referenceService
                .fetchGBIFImageURLs(taxonKey: request.taxonKey)
            guard !Task.isCancelled else { return }
            let urls = fetchedURLs.compactMap(
                ExternalReferenceImagePolicy.sanitizedURL
            )
            dependencies.logGBIFResponse(urls)
            guard !urls.isEmpty else { return }

            let identity = request.identity
            var persistedURLs: String?
            if var updated = callbacks.currentSpeciesData(),
               callbacks.isPresentationCurrent(identity) {
                var currentURLs = Self.referenceURLs(
                    from: updated.referenceImageUrl
                )
                for url in urls where !currentURLs.contains(url) {
                    currentURLs.append(url)
                }
                let capped = Array(currentURLs.prefix(5))
                updated.referenceImageUrl = capped.joined(separator: ",")
                persistedURLs = updated.referenceImageUrl
                callbacks.publishReferenceState(.loaded(capped))
                callbacks.publishSpeciesData(updated)
            }

            guard let modelContainer = request.modelContainer,
                  let persistedURLs else {
                return
            }
            let snapshot = InferenceHydrationPersistenceService
                .ReferenceSnapshot(
                    scanId: identity.scanId,
                    extract: nil,
                    url: nil,
                    imageUrl: persistedURLs,
                    expectedScientificName: identity.scientificName
                )
            let persistence = persistenceService
            callbacks.enqueuePersistence(PersistenceWork(
                identity: identity,
                operation: {
                    await persistence.persistReference(
                        snapshot,
                        in: modelContainer
                    )
                }
            ))
        } catch {
            guard !Task.isCancelled else { return }
            dependencies.logFailure(.gbif, error)
        }
    }

    func hydrateMissingReferenceImages(
        identity: Identity,
        modelContainer: ModelContainer?,
        callbacks: Callbacks
    ) async {
        guard !Task.isCancelled,
              callbacks.isPresentationCurrent(identity),
              Self.referenceURLs(
                  from: callbacks.currentSpeciesData()?.referenceImageUrl
              ).isEmpty,
              let taxonKey = callbacks.currentSpeciesData()?.gbifTaxonKey else {
            return
        }

        await hydrateGBIF(
            GBIFRequest(
                taxonKey: taxonKey,
                identity: identity,
                modelContainer: modelContainer
            ),
            callbacks: callbacks
        )
    }

    private static func referenceURLs(from rawValue: String?) -> [String] {
        ExternalReferenceImagePolicy.allowedURLStrings(from: rawValue)
    }
}

import Foundation
import Testing

@testable import Merian

private actor HistoricalHydrationEventRecorder {
    private var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }

    func snapshot() -> [String] {
        events
    }
}

@MainActor
private final class HistoricalHydrationPresentationHarness {
    var speciesData: SpeciesData?
    var referenceState: ReferenceState = .empty
    var presentationGeneration: UInt64
    var reviewActionGeneration: UInt64
    var referenceTransitions: [ReferenceState] = []
    var publishedScanIDs: [String] = []
    var isMetadataLoading = false
    var isLookalikesLoading = false

    init(
        speciesData: SpeciesData,
        presentationGeneration: UInt64 = 1,
        reviewActionGeneration: UInt64 = 11
    ) {
        self.speciesData = speciesData
        self.presentationGeneration = presentationGeneration
        self.reviewActionGeneration = reviewActionGeneration
    }

    func replacePresentation(
        with speciesData: SpeciesData,
        presentationGeneration: UInt64,
        reviewActionGeneration: UInt64
    ) {
        self.speciesData = speciesData
        referenceState = .empty
        self.presentationGeneration = presentationGeneration
        self.reviewActionGeneration = reviewActionGeneration
    }

    func callbacks() -> InferenceSpeciesHydrationCoordinator.Callbacks {
        .init(
            currentSpeciesData: { [weak self] in self?.speciesData },
            currentReferenceState: { [weak self] in
                self?.referenceState ?? .empty
            },
            currentPresentationGeneration: { [weak self] in
                self?.presentationGeneration ?? 0
            },
            isPresentationCurrent: { [weak self] identity in
                guard let self,
                      presentationGeneration == identity
                        .presentationGeneration,
                      reviewActionGeneration == identity
                        .reviewActionGeneration,
                      speciesData?.scanId?.caseInsensitiveCompare(
                          identity.scanId
                      ) == .orderedSame,
                      speciesData?.scientificName.caseInsensitiveCompare(
                          identity.scientificName
                      ) == .orderedSame else {
                    return false
                }
                return true
            },
            publishSpeciesData: { [weak self] data in
                self?.speciesData = data
                if let scanId = data.scanId {
                    self?.publishedScanIDs.append(scanId)
                }
            },
            publishReferenceState: { [weak self] state in
                self?.referenceState = state
                self?.referenceTransitions.append(state)
            },
            setLoading: { [weak self] scope, isLoading in
                switch scope {
                case .metadata:
                    self?.isMetadataLoading = isLoading
                case .lookalikes:
                    self?.isLookalikesLoading = isLoading
                }
            },
            enqueuePersistence: { _ in }
        )
    }
}

@MainActor
@Suite("Inference Historical Hydration Coordinator")
struct HistoricalHydrationCoordinatorTests {
    @Test func preservesRegisteredHistoricalHydrationOrder() async throws {
        let events = HistoricalHydrationEventRecorder()
        let metadataGate = InferenceOperationGate()
        let lookalikesGate = InferenceOperationGate()
        let taskCoordinator = makeTaskCoordinator()
        let coordinator = try makeCoordinator(
            taskCoordinator: taskCoordinator,
            events: events,
            metadataGate: metadataGate,
            lookalikesGate: lookalikesGate
        )
        let projection = InferenceHistoricalRecordProjection(
            record: LocalScanRecord(
                id: "historical-sequence",
                speciesId: "monarch-id",
                scientificName: "Danaus erippus",
                commonName: "Southern Monarch",
                isBiological: true,
                userIdentificationOverride: "Danaus plexippus"
            ),
            resetLocalLookalikes: false
        )
        let harness = HistoricalHydrationPresentationHarness(
            speciesData: projection.speciesData
        )
        let decodingCoordinator = InferenceHistoricalHydrationCoordinator(
            taskCoordinator: taskCoordinator,
            speciesHydrationCoordinator: coordinator,
            dependencies: .init(decodeDeferredContent: { projection in
                await events.append("decode")
                return await InferenceHistoricalRecordProjection
                    .decodeDeferredContent(projection.deferredContent)
            })
        )

        decodingCoordinator.scheduleHydration(
            request(for: projection, harness: harness),
            callbacks: .init(
                speciesHydration: harness.callbacks(),
                hydrateDisplayedOverride: { _ in
                    await events.append("override")
                }
            )
        )
        await metadataGate.waitUntilStarted()
        await lookalikesGate.waitUntilStarted()
        #expect(!(await events.snapshot()).contains("gbif"))
        await metadataGate.release()
        await lookalikesGate.release()
        await taskCoordinator.awaitCurrentTask(in: .historic)

        let recorded = await events.snapshot()
        let decodeIndex = try #require(recorded.firstIndex(of: "decode"))
        let overrideIndex = try #require(recorded.firstIndex(of: "override"))
        let wikipediaIndex = try #require(
            recorded.firstIndex(of: "wikipedia")
        )
        let metadataIndex = try #require(
            recorded.firstIndex(of: "metadata-complete")
        )
        let lookalikesIndex = try #require(
            recorded.firstIndex(of: "lookalikes-complete")
        )
        let gbifIndex = try #require(recorded.firstIndex(of: "gbif"))

        #expect(decodeIndex < overrideIndex)
        #expect(overrideIndex < wikipediaIndex)
        #expect(overrideIndex < metadataIndex)
        #expect(overrideIndex < lookalikesIndex)
        #expect(metadataIndex < gbifIndex)
        #expect(lookalikesIndex < gbifIndex)
        #expect(harness.referenceTransitions.first == .loading)
        #expect(harness.speciesData?.habitatDescription == "Open meadows")
        #expect(harness.speciesData?.gbifTaxonKey == 5_137_920)
        #expect(
            harness.speciesData?.similarSpecies?.entries.first?
                .scientificName == "Danaus gilippus"
        )
        #expect(harness.speciesData?.wikipediaOverview == "A butterfly.")
        #expect(
            Set(harness.referenceState.urls) == [
                "https://example.com/wiki.jpg",
                "https://example.com/gbif.jpg"
            ]
        )
        #expect(taskCoordinator.isSpeciesEnriched("Danaus plexippus"))
        #expect(!harness.isMetadataLoading)
        #expect(!harness.isLookalikesLoading)
    }

    @Test func replacementRejectsCancellationIgnoringDecodedContent()
        async throws {
        let gate = InferenceOperationGate()
        let events = HistoricalHydrationEventRecorder()
        let taskCoordinator = makeTaskCoordinator()
        let speciesCoordinator = try makeCoordinator(
            taskCoordinator: taskCoordinator,
            events: events
        )
        let oldProjection = try completeProjection(
            scanId: "historical-old",
            scientificName: "Procyon lotor",
            candidateName: "Bassariscus astutus"
        )
        let newProjection = try completeProjection(
            scanId: "historical-new",
            scientificName: "Nasua narica",
            candidateName: "Nasua nasua"
        )
        taskCoordinator.markSpeciesEnriched("Procyon lotor")
        taskCoordinator.markSpeciesEnriched("Nasua narica")
        let harness = HistoricalHydrationPresentationHarness(
            speciesData: oldProjection.speciesData
        )
        let coordinator = InferenceHistoricalHydrationCoordinator(
            taskCoordinator: taskCoordinator,
            speciesHydrationCoordinator: speciesCoordinator,
            dependencies: .init(decodeDeferredContent: { projection in
                if projection.scanId == oldProjection.scanId {
                    await gate.wait()
                }
                return await InferenceHistoricalRecordProjection
                    .decodeDeferredContent(projection.deferredContent)
            })
        )

        coordinator.scheduleHydration(
            request(for: oldProjection, harness: harness),
            callbacks: .init(
                speciesHydration: harness.callbacks(),
                hydrateDisplayedOverride: { _ in }
            )
        )
        await gate.waitUntilStarted()

        harness.replacePresentation(
            with: newProjection.speciesData,
            presentationGeneration: 2,
            reviewActionGeneration: 22
        )
        coordinator.scheduleHydration(
            request(for: newProjection, harness: harness),
            callbacks: .init(
                speciesHydration: harness.callbacks(),
                hydrateDisplayedOverride: { _ in }
            )
        )
        await taskCoordinator.awaitCurrentTask(in: .historic)
        _ = taskCoordinator.beginAuthTransitionFence()
        await gate.release()
        await taskCoordinator.awaitQuiescence()

        #expect(Set(harness.publishedScanIDs) == ["historical-new"])
        #expect(harness.speciesData?.scanId == "historical-new")
        #expect(
            harness.speciesData?.candidates?.first?.scientificName ==
                "Nasua nasua"
        )
    }

    @Test func emptyReferenceResponsesEndHistoricalLoadingState() async throws {
        let events = HistoricalHydrationEventRecorder()
        let taskCoordinator = makeTaskCoordinator()
        let speciesCoordinator = try makeCoordinator(
            taskCoordinator: taskCoordinator,
            events: events,
            wikipediaData: Data("{}".utf8),
            gbifData: Data(#"{"results":[]}"#.utf8)
        )
        let projection = try completeProjection(
            scanId: "historical-empty-references",
            scientificName: "Danaus plexippus",
            candidateName: "Danaus gilippus",
            referenceImageURL: nil,
            gbifTaxonKey: 5_137_920
        )
        let harness = HistoricalHydrationPresentationHarness(
            speciesData: projection.speciesData
        )
        let coordinator = InferenceHistoricalHydrationCoordinator(
            taskCoordinator: taskCoordinator,
            speciesHydrationCoordinator: speciesCoordinator
        )

        coordinator.scheduleHydration(
            request(for: projection, harness: harness),
            callbacks: .init(
                speciesHydration: harness.callbacks(),
                hydrateDisplayedOverride: { _ in }
            )
        )
        await taskCoordinator.awaitCurrentTask(in: .historic)

        #expect(harness.referenceTransitions.first == .loading)
        #expect(harness.referenceTransitions.last == .empty)
        #expect(harness.referenceState == .empty)
    }

    @Test func cancellationAfterOverridePreventsRemoteHydration() async throws {
        let gate = InferenceOperationGate()
        let events = HistoricalHydrationEventRecorder()
        let taskCoordinator = makeTaskCoordinator()
        let speciesCoordinator = try makeCoordinator(
            taskCoordinator: taskCoordinator,
            events: events
        )
        let projection = InferenceHistoricalRecordProjection(
            record: LocalScanRecord(
                id: "historical-cancelled-override",
                speciesId: "monarch-id",
                scientificName: "Danaus erippus",
                commonName: "Southern Monarch",
                isBiological: true,
                userIdentificationOverride: "Danaus plexippus"
            ),
            resetLocalLookalikes: false
        )
        let harness = HistoricalHydrationPresentationHarness(
            speciesData: projection.speciesData
        )
        let coordinator = InferenceHistoricalHydrationCoordinator(
            taskCoordinator: taskCoordinator,
            speciesHydrationCoordinator: speciesCoordinator
        )

        coordinator.scheduleHydration(
            request(for: projection, harness: harness),
            callbacks: .init(
                speciesHydration: harness.callbacks(),
                hydrateDisplayedOverride: { _ in
                    await gate.wait()
                }
            )
        )
        await gate.waitUntilStarted()
        taskCoordinator.cancelCurrentTask(in: .historic)
        _ = taskCoordinator.beginAuthTransitionFence()
        await gate.release()
        await taskCoordinator.awaitQuiescence()

        #expect(await events.snapshot() == [])
        #expect(harness.speciesData?.wikipediaOverview == nil)
        #expect(harness.speciesData?.gbifTaxonKey == nil)
    }

    @Test func speciesCacheSuppressesOnlyHistoricalMetadataScope()
        async throws {
        let events = HistoricalHydrationEventRecorder()
        let taskCoordinator = makeTaskCoordinator()
        taskCoordinator.markSpeciesEnriched("Danaus plexippus")
        let speciesCoordinator = try makeCoordinator(
            taskCoordinator: taskCoordinator,
            events: events
        )
        let projection = InferenceHistoricalRecordProjection(
            record: LocalScanRecord(
                id: "historical-cached-species",
                speciesId: "monarch-id",
                scientificName: "Danaus plexippus",
                commonName: "Monarch",
                isBiological: true,
                wikipediaOverview: "A butterfly.",
                referenceImageUrl: "https://example.com/existing.jpg",
                taxonomyKingdom: "Animalia",
                taxonomyOrder: "Lepidoptera",
                habitatDescription: "Open meadows"
            ),
            resetLocalLookalikes: false
        )
        let harness = HistoricalHydrationPresentationHarness(
            speciesData: projection.speciesData
        )
        let coordinator = InferenceHistoricalHydrationCoordinator(
            taskCoordinator: taskCoordinator,
            speciesHydrationCoordinator: speciesCoordinator
        )

        coordinator.scheduleHydration(
            request(for: projection, harness: harness),
            callbacks: .init(
                speciesHydration: harness.callbacks(),
                hydrateDisplayedOverride: { _ in }
            )
        )
        await taskCoordinator.awaitCurrentTask(in: .historic)

        #expect(await events.snapshot() == ["lookalikes"])
        #expect(
            harness.speciesData?.similarSpecies?.entries.first?
                .scientificName == "Danaus gilippus"
        )
        #expect(
            taskCoordinator.snapshot.historicEnrichmentAttemptCount == 1
        )
    }

    private func request(
        for projection: InferenceHistoricalRecordProjection,
        harness: HistoricalHydrationPresentationHarness
    ) -> InferenceHistoricalHydrationCoordinator.Request {
        .init(
            projection: projection,
            modelContainer: nil,
            presentationGeneration: harness.presentationGeneration,
            reviewActionGeneration: harness.reviewActionGeneration
        )
    }

    private func makeTaskCoordinator() -> InferenceHydrationCoordinator {
        InferenceHydrationCoordinator(
            dependencies: .init(
                now: { Date(timeIntervalSinceReferenceDate: 10_000) },
                loadEnrichedSpeciesTimestamps: { [:] },
                persistEnrichedSpeciesTimestamps: { _ in }
            )
        )
    }

    private func makeCoordinator(
        taskCoordinator: InferenceHydrationCoordinator,
        events: HistoricalHydrationEventRecorder,
        metadataGate: InferenceOperationGate? = nil,
        lookalikesGate: InferenceOperationGate? = nil,
        wikipediaData: Data = Self.wikipediaData,
        gbifData: Data = Self.gbifData
    ) throws -> InferenceSpeciesHydrationCoordinator {
        let responses = try makeEnrichmentResponses()
        return InferenceSpeciesHydrationCoordinator(
            taskCoordinator: taskCoordinator,
            referenceService: SpeciesReferenceHydrationService { request in
                let url = try #require(request.url)
                let isGBIF = url.host == "api.gbif.org"
                await events.append(isGBIF ? "gbif" : "wikipedia")
                let response = try #require(
                    HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )
                )
                return (
                    isGBIF ? gbifData : wikipediaData,
                    response
                )
            },
            enrichmentService: InferenceSpeciesEnrichmentService(
                dependencies: .init { _, scope in
                    let isMetadata = scope == .metadata
                    await events.append(isMetadata ? "metadata" : "lookalikes")
                    let gate = isMetadata ? metadataGate : lookalikesGate
                    if let gate {
                        await gate.wait()
                        await events.append(
                            isMetadata
                                ? "metadata-complete"
                                : "lookalikes-complete"
                        )
                    }
                    return scope == .metadata
                        ? responses.metadata
                        : responses.lookalikes
                }
            ),
            persistenceService: InferenceHydrationPersistenceService(
                dependencies: .init(
                    persistReference: { _, _ in },
                    persistMetadata: { _, _ in },
                    persistLookalikes: { _, _ in }
                )
            ),
            dependencies: .init(
                logWikipediaResponse: { _ in },
                logWikipediaApplied: { _ in },
                logGBIFResponse: { _ in },
                logFailure: { _, _ in }
            )
        )
    }

    private func makeEnrichmentResponses() throws -> (
        metadata: EnrichScanResponse,
        lookalikes: EnrichScanResponse
    ) {
        let metadata = try JSONDecoder().decode(
            EnrichScanResponse.self,
            from: Data(
                """
                {
                  "success": true,
                  "data": {
                    "habitat_description": "Open meadows",
                    "gbif_taxon_key": 5137920,
                    "taxonomy": {
                      "kingdom": "Animalia",
                      "order": "Lepidoptera"
                    }
                  }
                }
                """.utf8
            )
        )
        let lookalikes = try JSONDecoder().decode(
            EnrichScanResponse.self,
            from: Data(
                """
                {
                  "success": true,
                  "data": {
                    "similar_species": [{
                      "scientific_name": "Danaus gilippus",
                      "common_name": "Queen"
                    }]
                  }
                }
                """.utf8
            )
        )
        return (metadata, lookalikes)
    }

    private func completeProjection(
        scanId: String,
        scientificName: String,
        candidateName: String,
        referenceImageURL: String? = "https://example.com/existing.jpg",
        gbifTaxonKey: Int? = nil
    ) throws -> InferenceHistoricalRecordProjection {
        let lookalikes = [
            SimilarSpeciesEntry(
                scientificName: "Bassariscus astutus",
                commonName: "Ringtail",
                referenceImageUrl: nil,
                iucnRedListStatus: nil
            )
        ]
        let candidates = [
            IdentificationCandidate(
                scientificName: candidateName,
                confidenceScore: 0.7
            )
        ]
        let record = LocalScanRecord(
            id: scanId,
            speciesId: "test-species",
            scientificName: scientificName,
            commonName: "Test Species",
            isBiological: true,
            wikipediaOverview: "Existing overview.",
            referenceImageUrl: referenceImageURL,
            taxonomyKingdom: "Animalia",
            taxonomyOrder: "Carnivora",
            lookalikesData: try JSONEncoder().encode(lookalikes),
            candidatesData: try JSONEncoder().encode(candidates),
            habitatDescription: "Existing habitat.",
            gbifTaxonKey: gbifTaxonKey
        )
        return InferenceHistoricalRecordProjection(
            record: record,
            resetLocalLookalikes: false
        )
    }

    private nonisolated static let wikipediaData = Data(
        """
        {
          "lead": {
            "normalizedtitle": "Danaus plexippus",
            "originalimage": {
              "source": "https://example.com/wiki.jpg"
            }
          },
          "remaining": {
            "sections": [{
              "title": "Description",
              "text": "<p>A butterfly.</p>"
            }]
          }
        }
        """.utf8
    )

    private nonisolated static let gbifData = Data(
        """
        {
          "results": [{
            "media": [{
              "type": "StillImage",
              "identifier": "https://example.com/gbif.jpg"
            }]
          }]
        }
        """.utf8
    )
}

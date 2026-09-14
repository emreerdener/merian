import Foundation
import SwiftData
import Testing

@testable import Merian

private actor SpeciesHydrationTransport {
    private let wikipediaData: Data
    private let gbifData: Data
    private var requests: [URL] = []

    init(wikipediaData: Data, gbifData: Data) {
        self.wikipediaData = wikipediaData
        self.gbifData = gbifData
    }

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        let url = try #require(request.url)
        requests.append(url)
        let data = url.host == "api.gbif.org" ? gbifData : wikipediaData
        let response = try #require(
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )
        return (data, response)
    }

    func requestedURLs() -> [URL] {
        requests
    }
}

@MainActor
private final class SpeciesHydrationPresentationHarness {
    var speciesData: SpeciesData?
    var referenceState: ReferenceState = .empty
    var presentationGeneration: UInt64 = 7
    var acceptsPresentation = true
    var isMetadataLoading = false
    var isLookalikesLoading = false
    var referenceTransitions: [ReferenceState] = []
    var persistenceWork:
        [InferenceSpeciesHydrationCoordinator.PersistenceWork] = []

    init(speciesData: SpeciesData) {
        self.speciesData = speciesData
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
                      acceptsPresentation,
                      presentationGeneration == identity
                        .presentationGeneration,
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
            enqueuePersistence: { [weak self] work in
                self?.persistenceWork.append(work)
            }
        )
    }
}

@MainActor
private final class SpeciesHydrationLogRecorder {
    var wikipediaResponseCount = 0
    var wikipediaAppliedCount = 0
    var gbifResponseCount = 0
    var failures: [InferenceSpeciesHydrationCoordinator.FailureScope] = []

    var dependencies: InferenceSpeciesHydrationCoordinator.Dependencies {
        .init(
            logWikipediaResponse: { [weak self] _ in
                self?.wikipediaResponseCount += 1
            },
            logWikipediaApplied: { [weak self] _ in
                self?.wikipediaAppliedCount += 1
            },
            logGBIFResponse: { [weak self] _ in
                self?.gbifResponseCount += 1
            },
            logFailure: { [weak self] scope, _ in
                self?.failures.append(scope)
            }
        )
    }
}

@MainActor
@Suite("Inference Species Hydration Coordinator")
struct SpeciesHydrationCoordinatorTests {
    @Test func liveHydrationSequencesEnrichmentBeforeGBIFAndPublishesScopes()
        async throws {
        let transport = makeTransport()
        let responses = try makeEnrichmentResponses()
        var requestedScopes: [InferenceSpeciesEnrichmentService.Scope] = []
        let enrichment = InferenceSpeciesEnrichmentService(
            dependencies: .init { _, scope in
                requestedScopes.append(scope)
                switch scope {
                case .metadata:
                    return responses.metadata
                case .lookalikes:
                    return responses.lookalikes
                }
            }
        )
        let persistence = noOpPersistenceService()
        let taskCoordinator = makeTaskCoordinator()
        let logs = SpeciesHydrationLogRecorder()
        let coordinator = InferenceSpeciesHydrationCoordinator(
            taskCoordinator: taskCoordinator,
            referenceService: SpeciesReferenceHydrationService { request in
                try await transport.load(request)
            },
            enrichmentService: enrichment,
            persistenceService: persistence,
            dependencies: logs.dependencies
        )
        let harness = SpeciesHydrationPresentationHarness(
            speciesData: makeSpeciesData(gbifTaxonKey: 11)
        )
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()

        coordinator.scheduleLiveHydration(
            .init(
                speciesData: try #require(harness.speciesData),
                modelContainer: container,
                referencePolicy: .showLoadingWhenReferenceMissing,
                presentationGeneration: harness.presentationGeneration,
                reviewActionGeneration: 3
            ),
            callbacks: harness.callbacks()
        )
        await taskCoordinator.awaitCurrentTask(in: .live)

        #expect(
            Set(requestedScopes.map(\.rawValue)) ==
                Set(["enrichment", "lookalikes"])
        )
        let requestedURLs = await transport.requestedURLs()
        #expect(
            requestedURLs.contains {
                $0.absoluteString.contains("taxonKey=5137920")
            }
        )
        #expect(
            !requestedURLs.contains {
                $0.absoluteString.contains("taxonKey=11&")
            }
        )
        #expect(harness.speciesData?.habitatDescription == "Open meadows")
        #expect(harness.speciesData?.gbifTaxonKey == 5_137_920)
        #expect(
            harness.speciesData?.similarSpecies?.entries.first?
                .scientificName == "Danaus gilippus"
        )
        #expect(harness.speciesData?.wikipediaOverview == "A butterfly.")
        #expect(!harness.isMetadataLoading)
        #expect(!harness.isLookalikesLoading)
        #expect(harness.referenceTransitions.first == .loading)
        #expect(
            Set(harness.referenceState.urls) == [
                "https://example.com/wiki.jpg",
                "https://example.com/gbif.jpg"
            ]
        )
        #expect(harness.persistenceWork.count == 4)
        #expect(taskCoordinator.isSpeciesEnriched("Danaus plexippus"))
        #expect(logs.wikipediaResponseCount == 1)
        #expect(logs.wikipediaAppliedCount == 1)
        #expect(logs.gbifResponseCount == 1)
        #expect(logs.failures.isEmpty)
    }

    @Test func staleWikipediaSuccessDoesNotPublishPersistOrConsumeRetry()
        async throws {
        let transport = makeTransport()
        let taskCoordinator = makeTaskCoordinator()
        let logs = SpeciesHydrationLogRecorder()
        let coordinator = makeCoordinator(
            taskCoordinator: taskCoordinator,
            transport: transport,
            enrichmentService: noOpEnrichmentService(),
            logs: logs
        )
        let harness = SpeciesHydrationPresentationHarness(
            speciesData: makeSpeciesData()
        )
        harness.acceptsPresentation = false
        let identity = makeIdentity(harness: harness)

        await coordinator.hydrateWikipedia(
            .init(
                identity: identity,
                modelContainer:
                    try DatabaseActorTestSupport.makeIsolatedContainer()
            ),
            callbacks: harness.callbacks()
        )

        #expect(harness.speciesData?.wikipediaOverview == nil)
        #expect(harness.referenceTransitions.isEmpty)
        #expect(harness.persistenceWork.isEmpty)
        #expect(taskCoordinator.canHydrateWikipedia(for: "Danaus plexippus"))
        #expect(logs.wikipediaResponseCount == 0)
        #expect(logs.wikipediaAppliedCount == 0)
    }

    @Test func stalePresentationBeforeTaskStartDoesNotPublishOrRequest()
        async throws {
        let transport = makeTransport()
        let taskCoordinator = makeTaskCoordinator()
        let logs = SpeciesHydrationLogRecorder()
        let coordinator = makeCoordinator(
            taskCoordinator: taskCoordinator,
            transport: transport,
            enrichmentService: noOpEnrichmentService(),
            logs: logs
        )
        var speciesData = makeSpeciesData(gbifTaxonKey: 11)
        speciesData.wikipediaOverview = "Existing overview."
        let harness = SpeciesHydrationPresentationHarness(
            speciesData: speciesData
        )

        coordinator.scheduleLiveHydration(
            .init(
                speciesData: speciesData,
                modelContainer: nil,
                referencePolicy: .showLoadingWhenReferenceMissing,
                presentationGeneration: harness.presentationGeneration,
                reviewActionGeneration: 3
            ),
            callbacks: harness.callbacks()
        )
        harness.presentationGeneration &+= 1
        await taskCoordinator.awaitCurrentTask(in: .live)

        let requestedURLs = await transport.requestedURLs()
        #expect(requestedURLs.isEmpty)
        #expect(harness.referenceState == .empty)
        #expect(harness.referenceTransitions.isEmpty)
        #expect(harness.persistenceWork.isEmpty)
    }

    @Test func replacedPresentationKeepsItsReferenceLoadingState() async {
        let gate = InferenceOperationGate()
        let transport = makeTransport()
        let taskCoordinator = makeTaskCoordinator()
        let logs = SpeciesHydrationLogRecorder()
        let coordinator = InferenceSpeciesHydrationCoordinator(
            taskCoordinator: taskCoordinator,
            referenceService: SpeciesReferenceHydrationService { request in
                await gate.wait()
                return try await transport.load(request)
            },
            enrichmentService: noOpEnrichmentService(),
            persistenceService: noOpPersistenceService(),
            dependencies: logs.dependencies
        )
        var speciesData = makeSpeciesData(gbifTaxonKey: 11)
        speciesData.wikipediaOverview = "Existing overview."
        let harness = SpeciesHydrationPresentationHarness(
            speciesData: speciesData
        )

        coordinator.scheduleLiveHydration(
            .init(
                speciesData: speciesData,
                modelContainer: nil,
                referencePolicy: .showLoadingWhenReferenceMissing,
                presentationGeneration: harness.presentationGeneration,
                reviewActionGeneration: 3
            ),
            callbacks: harness.callbacks()
        )
        await gate.waitUntilStarted()

        harness.presentationGeneration &+= 1
        harness.referenceState = .loading
        taskCoordinator.cancelCurrentTask(in: .live)
        _ = taskCoordinator.beginAuthTransitionFence()
        await gate.release()
        await taskCoordinator.awaitQuiescence()

        #expect(harness.referenceState == .loading)
        #expect(harness.referenceTransitions == [.loading])
    }

    @Test func cancelledWikipediaResponseCannotPublishPersistOrConsumeRetry()
        async throws {
        let gate = InferenceOperationGate()
        let transport = makeTransport()
        let taskCoordinator = makeTaskCoordinator()
        let logs = SpeciesHydrationLogRecorder()
        let coordinator = InferenceSpeciesHydrationCoordinator(
            taskCoordinator: taskCoordinator,
            referenceService: SpeciesReferenceHydrationService { request in
                await gate.wait()
                return try await transport.load(request)
            },
            enrichmentService: noOpEnrichmentService(),
            persistenceService: noOpPersistenceService(),
            dependencies: logs.dependencies
        )
        let harness = SpeciesHydrationPresentationHarness(
            speciesData: makeSpeciesData()
        )
        let identity = makeIdentity(harness: harness)
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let operation = Task { @MainActor in
            await coordinator.hydrateWikipedia(
                .init(
                    identity: identity,
                    modelContainer: container
                ),
                callbacks: harness.callbacks()
            )
        }

        await gate.waitUntilStarted()
        operation.cancel()
        await gate.release()
        await operation.value

        #expect(harness.speciesData?.wikipediaOverview == nil)
        #expect(harness.referenceTransitions.isEmpty)
        #expect(harness.persistenceWork.isEmpty)
        #expect(taskCoordinator.canHydrateWikipedia(for: "Danaus plexippus"))
        #expect(logs.wikipediaResponseCount == 0)
        #expect(logs.wikipediaAppliedCount == 0)
    }

    @Test func cancelledGBIFResponseCannotPublishOrPersist() async throws {
        let gate = InferenceOperationGate()
        let transport = makeTransport()
        let logs = SpeciesHydrationLogRecorder()
        let coordinator = InferenceSpeciesHydrationCoordinator(
            taskCoordinator: makeTaskCoordinator(),
            referenceService: SpeciesReferenceHydrationService { request in
                await gate.wait()
                return try await transport.load(request)
            },
            enrichmentService: noOpEnrichmentService(),
            persistenceService: noOpPersistenceService(),
            dependencies: logs.dependencies
        )
        let harness = SpeciesHydrationPresentationHarness(
            speciesData: makeSpeciesData()
        )
        let identity = makeIdentity(harness: harness)
        let container = try DatabaseActorTestSupport.makeIsolatedContainer()
        let operation = Task { @MainActor in
            await coordinator.hydrateGBIF(
                .init(
                    taxonKey: 5_137_920,
                    identity: identity,
                    modelContainer: container
                ),
                callbacks: harness.callbacks()
            )
        }

        await gate.waitUntilStarted()
        operation.cancel()
        await gate.release()
        await operation.value

        #expect(harness.speciesData?.referenceImageUrl == nil)
        #expect(harness.referenceTransitions.isEmpty)
        #expect(harness.persistenceWork.isEmpty)
        #expect(logs.gbifResponseCount == 0)
    }

    @Test func cancelledEnrichmentScopesCannotPublishOrPersist() async throws {
        let responses = try makeEnrichmentResponses()

        for requestsMetadata in [true, false] {
            let gate = InferenceOperationGate()
            let enrichment = InferenceSpeciesEnrichmentService(
                dependencies: .init { _, scope in
                    await gate.wait()
                    switch scope {
                    case .metadata:
                        return responses.metadata
                    case .lookalikes:
                        return responses.lookalikes
                    }
                }
            )
            let logs = SpeciesHydrationLogRecorder()
            let coordinator = makeCoordinator(
                taskCoordinator: makeTaskCoordinator(),
                transport: makeTransport(),
                enrichmentService: enrichment,
                logs: logs
            )
            let harness = SpeciesHydrationPresentationHarness(
                speciesData: makeSpeciesData()
            )
            let container = try DatabaseActorTestSupport
                .makeIsolatedContainer()
            let operation = Task { @MainActor in
                await coordinator.fetchAndApplyEnrichment(
                    .init(
                        modelContainer: container,
                        needsMetadata: requestsMetadata,
                        needsLookalikes: !requestsMetadata
                    ),
                    callbacks: harness.callbacks()
                )
            }

            await gate.waitUntilStarted()
            operation.cancel()
            await gate.release()
            await operation.value

            #expect(harness.speciesData?.habitatDescription == nil)
            #expect(harness.speciesData?.similarSpecies == nil)
            #expect(harness.persistenceWork.isEmpty)
            #expect(!harness.isMetadataLoading)
            #expect(!harness.isLookalikesLoading)
            #expect(logs.failures.isEmpty)
        }
    }

    @Test func enrichmentScopesCompleteIndependentlyWhenMetadataFails()
        async throws {
        let responses = try makeEnrichmentResponses()
        let enrichment = InferenceSpeciesEnrichmentService(
            dependencies: .init { _, scope in
                switch scope {
                case .metadata:
                    throw SpeciesHydrationTestError.unavailable
                case .lookalikes:
                    return responses.lookalikes
                }
            }
        )
        let transport = makeTransport()
        let logs = SpeciesHydrationLogRecorder()
        let coordinator = makeCoordinator(
            taskCoordinator: makeTaskCoordinator(),
            transport: transport,
            enrichmentService: enrichment,
            logs: logs
        )
        let harness = SpeciesHydrationPresentationHarness(
            speciesData: makeSpeciesData()
        )

        await coordinator.fetchAndApplyEnrichment(
            .init(
                modelContainer: nil,
                needsMetadata: true,
                needsLookalikes: true
            ),
            callbacks: harness.callbacks()
        )

        #expect(harness.speciesData?.habitatDescription == nil)
        #expect(
            harness.speciesData?.similarSpecies?.entries.first?
                .scientificName == "Danaus gilippus"
        )
        #expect(!harness.isMetadataLoading)
        #expect(!harness.isLookalikesLoading)
        #expect(logs.failures == [.metadata])
    }

    @Test func rateLimitFailureStartsBackoffAndSuppressesAnotherAttempt()
        async {
        var requestCount = 0
        let enrichment = InferenceSpeciesEnrichmentService(
            dependencies: .init { _, _ in
                requestCount += 1
                throw MerianError.httpError(
                    statusCode: 429,
                    message: "rate limited"
                )
            }
        )
        let taskCoordinator = makeTaskCoordinator()
        let logs = SpeciesHydrationLogRecorder()
        let coordinator = makeCoordinator(
            taskCoordinator: taskCoordinator,
            transport: makeTransport(),
            enrichmentService: enrichment,
            logs: logs
        )
        let harness = SpeciesHydrationPresentationHarness(
            speciesData: makeSpeciesData()
        )
        let request = InferenceSpeciesHydrationCoordinator.EnrichmentRequest(
            modelContainer: nil,
            needsMetadata: true,
            needsLookalikes: false
        )

        await coordinator.fetchAndApplyEnrichment(
            request,
            callbacks: harness.callbacks()
        )
        await coordinator.fetchAndApplyEnrichment(
            request,
            callbacks: harness.callbacks()
        )

        #expect(requestCount == 1)
        #expect(taskCoordinator.snapshot.rateLimitedUntil != nil)
        #expect(!harness.isMetadataLoading)
        #expect(logs.failures.isEmpty)
    }

    private func makeCoordinator(
        taskCoordinator: InferenceHydrationCoordinator,
        transport: SpeciesHydrationTransport,
        enrichmentService: InferenceSpeciesEnrichmentService,
        logs: SpeciesHydrationLogRecorder
    ) -> InferenceSpeciesHydrationCoordinator {
        InferenceSpeciesHydrationCoordinator(
            taskCoordinator: taskCoordinator,
            referenceService: SpeciesReferenceHydrationService { request in
                try await transport.load(request)
            },
            enrichmentService: enrichmentService,
            persistenceService: noOpPersistenceService(),
            dependencies: logs.dependencies
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

    private func makeTransport() -> SpeciesHydrationTransport {
        SpeciesHydrationTransport(
            wikipediaData: Data(
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
            ),
            gbifData: Data(
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

    private func noOpEnrichmentService()
        -> InferenceSpeciesEnrichmentService {
        InferenceSpeciesEnrichmentService(
            dependencies: .init { _, _ in
                EnrichScanResponse(success: true, data: nil)
            }
        )
    }

    private func noOpPersistenceService()
        -> InferenceHydrationPersistenceService {
        InferenceHydrationPersistenceService(
            dependencies: .init(
                persistReference: { _, _ in },
                persistMetadata: { _, _ in },
                persistLookalikes: { _, _ in }
            )
        )
    }

    private func makeSpeciesData(gbifTaxonKey: Int? = nil) -> SpeciesData {
        SpeciesData(
            scanId: "scan-hydration",
            commonName: "Monarch",
            scientificName: "Danaus plexippus",
            insightData: InsightData(
                aiReasoning: "Synthetic observation",
                hazardType: "none"
            ),
            confidenceScore: 0.94,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "terrestrial",
            gbifTaxonKey: gbifTaxonKey,
            inferenceTier: "pro"
        )
    }

    private func makeIdentity(
        harness: SpeciesHydrationPresentationHarness
    ) -> InferenceSpeciesHydrationCoordinator.Identity {
        .init(
            scanId: "scan-hydration",
            scientificName: "Danaus plexippus",
            presentationGeneration: harness.presentationGeneration,
            reviewActionGeneration: 3
        )
    }

    private enum SpeciesHydrationTestError: Error {
        case unavailable
    }
}

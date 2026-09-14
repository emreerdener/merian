import Foundation
import SwiftData
import Testing

@testable import Merian

@MainActor
private final class ReviewWorkflowPresentationHarness {
    var speciesData: SpeciesData?
    var referenceState: ReferenceState = .empty
    var presentationGeneration: UInt64 = 7
    var isMetadataLoading = false
    var isLookalikesLoading = false

    init(speciesData: SpeciesData) {
        self.speciesData = speciesData
    }

    func callbacks()
        -> InferenceReviewWorkflowCoordinator.Callbacks {
        let hydrationCallbacks =
            InferenceSpeciesHydrationCoordinator.Callbacks(
                currentSpeciesData: { [weak self] in self?.speciesData },
                currentReferenceState: { [weak self] in
                    self?.referenceState ?? .empty
                },
                currentPresentationGeneration: { [weak self] in
                    self?.presentationGeneration ?? 0
                },
                isPresentationCurrent: { [weak self] identity in
                    guard let self,
                          presentationGeneration ==
                            identity.presentationGeneration,
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
        return .init(
            applyPresentation: { [weak self] action in
                self?.speciesData = action.speciesData
                if let referenceState = action.referenceState {
                    self?.referenceState = referenceState
                }
            },
            speciesHydration: hydrationCallbacks
        )
    }
}

@MainActor
private struct IdentificationReviewWorkflowSubject {
    let workflow: InferenceReviewWorkflowCoordinator
    let review: InferenceIdentificationReviewCoordinator
}

@MainActor
private final class ReviewWorkflowHydrationRecorder {
    private(set) var requestedScopes =
        [InferenceSpeciesEnrichmentService.Scope]()

    func record(_ scope: InferenceSpeciesEnrichmentService.Scope) {
        requestedScopes.append(scope)
    }
}

@MainActor
@Suite("Inference Identification Review Workflow Coordinator")
struct InferenceReviewWorkflowCoordinatorTests {
    @Test func overrideAdmitsLocalStateBeforeLookupAndSerializesWrites()
        async throws {
        let reviewHarness = IdentificationReviewCoordinatorHarness()
        let syncGate = InferenceOperationGate()
        reviewHarness.syncGate = syncGate
        reviewHarness.speciesRecords["Procyon cancrivorus"] =
            dictionaryRecord(
                id: "crab-raccoon-id",
                scientificName: "Procyon cancrivorus",
                commonName: "Crab-eating raccoon"
            )
        let subject = makeSubject(reviewHarness: reviewHarness)
        let presentation = ReviewWorkflowPresentationHarness(
            speciesData: speciesData()
        )

        await subject.workflow.applyOverride(
            .init(
                scientificName: "Procyon cancrivorus",
                expectedScanID: "scan-review",
                modelContainer:
                    try DatabaseActorTestSupport.makeIsolatedContainer()
            ),
            callbacks: presentation.callbacks()
        )
        await syncGate.waitUntilStarted()

        #expect(reviewHarness.events == [
            .beginOverride("scan-review", "Procyon cancrivorus"),
            .loadSpecies("Procyon cancrivorus"),
            .persistPatch("scan-review", "Crab-Eating Raccoon"),
            .persistReview(
                .userOverride(
                    scanID: "scan-review",
                    scientificName: "Procyon cancrivorus",
                    confirmedSpeciesID: "crab-raccoon-id"
                ),
                UserReviewState.userOverridden.rawValue
            ),
            .sync(
                .userOverride(
                    scanID: "scan-review",
                    scientificName: "Procyon cancrivorus",
                    confirmedSpeciesID: "crab-raccoon-id"
                )
            )
        ])
        #expect(presentation.speciesData?.commonName == "Crab-Eating Raccoon")
        #expect(
            presentation.speciesData?.userIdentificationOverride ==
                "Procyon cancrivorus"
        )

        await syncGate.release()
    }

    @Test func newerOverrideRejectsCancellationIgnoringLookupResult() async {
        let reviewHarness = IdentificationReviewCoordinatorHarness()
        let olderLookupGate = InferenceOperationGate()
        let syncGate = InferenceOperationGate()
        reviewHarness.speciesLookupGates["Procyon cancrivorus"] =
            olderLookupGate
        reviewHarness.syncGate = syncGate
        reviewHarness.speciesRecords["Procyon cancrivorus"] =
            dictionaryRecord(
                id: "older-id",
                scientificName: "Procyon cancrivorus",
                commonName: "Older result"
            )
        reviewHarness.speciesRecords["Nasua nasua"] = dictionaryRecord(
            id: "newer-id",
            scientificName: "Nasua nasua",
            commonName: "South American coati"
        )
        let subject = makeSubject(reviewHarness: reviewHarness)
        let presentation = ReviewWorkflowPresentationHarness(
            speciesData: speciesData()
        )

        let olderTask = Task { @MainActor in
            await subject.workflow.applyOverride(
                .init(
                    scientificName: "Procyon cancrivorus",
                    expectedScanID: "scan-review",
                    modelContainer: nil
                ),
                callbacks: presentation.callbacks()
            )
        }
        await olderLookupGate.waitUntilStarted()

        await subject.workflow.applyOverride(
            .init(
                scientificName: "Nasua nasua",
                expectedScanID: "scan-review",
                modelContainer: nil
            ),
            callbacks: presentation.callbacks()
        )
        await syncGate.waitUntilStarted()

        #expect(presentation.speciesData?.scientificName == "Nasua nasua")
        #expect(presentation.speciesData?.commonName == "South American Coati")
        #expect(
            reviewMutations(in: reviewHarness.events) == [
                .userOverride(
                    scanID: "scan-review",
                    scientificName: "Nasua nasua",
                    confirmedSpeciesID: "newer-id"
                )
            ]
        )

        await syncGate.release()
        await olderLookupGate.release()
        await olderTask.value
        #expect(presentation.speciesData?.scientificName == "Nasua nasua")
        #expect(
            reviewMutations(in: reviewHarness.events) == [
                .userOverride(
                    scanID: "scan-review",
                    scientificName: "Nasua nasua",
                    confirmedSpeciesID: "newer-id"
                )
            ]
        )
    }

    @Test func missingDictionaryRowUsesEnrichmentThenIDFallback() async {
        let reviewHarness = IdentificationReviewCoordinatorHarness()
        let syncGate = InferenceOperationGate()
        let hydrationRecorder = ReviewWorkflowHydrationRecorder()
        reviewHarness.speciesID = "fallback-species-id"
        reviewHarness.syncGate = syncGate
        let subject = makeSubject(
            reviewHarness: reviewHarness,
            hydrationRecorder: hydrationRecorder
        )
        let presentation = ReviewWorkflowPresentationHarness(
            speciesData: speciesData()
        )

        await subject.workflow.applyOverride(
            .init(
                scientificName: "Procyon cancrivorus",
                expectedScanID: nil,
                modelContainer: nil
            ),
            callbacks: presentation.callbacks()
        )
        await syncGate.waitUntilStarted()

        #expect(reviewHarness.events == [
            .loadSpecies("Procyon cancrivorus"),
            .loadSpeciesID("Procyon cancrivorus"),
            .sync(
                .userOverride(
                    scanID: "scan-review",
                    scientificName: "Procyon cancrivorus",
                    confirmedSpeciesID: "fallback-species-id"
                )
            )
        ])
        #expect(!presentation.isMetadataLoading)
        #expect(!presentation.isLookalikesLoading)
        #expect(
            Set(hydrationRecorder.requestedScopes.map(\.rawValue)) ==
                Set(["enrichment", "lookalikes"])
        )

        await syncGate.release()
    }

    @Test func displayedSpeciesHydrationRejectsStaleDictionaryResult()
        async throws {
        let reviewHarness = IdentificationReviewCoordinatorHarness()
        let lookupGate = InferenceOperationGate()
        reviewHarness.speciesLookupGates["Procyon cancrivorus"] = lookupGate
        reviewHarness.speciesRecords["Procyon cancrivorus"] =
            dictionaryRecord(
                id: "stale-id",
                scientificName: "Procyon cancrivorus",
                commonName: "Stale dictionary result"
            )
        let subject = makeSubject(reviewHarness: reviewHarness)
        let presentation = ReviewWorkflowPresentationHarness(
            speciesData: speciesData(
                scientificName: "Procyon cancrivorus",
                override: "Procyon cancrivorus"
            )
        )
        let reviewGeneration = subject.review.beginReviewAction(
            scanId: "scan-review"
        )
        let modelContainer = try DatabaseActorTestSupport
            .makeIsolatedContainer()

        let task = Task { @MainActor in
            await subject.workflow.hydrateDisplayedSpecies(
                .init(
                    scientificName: "Procyon cancrivorus",
                    scanID: "scan-review",
                    modelContainer: modelContainer,
                    presentationGeneration: 7,
                    reviewActionGeneration: reviewGeneration
                ),
                callbacks: presentation.callbacks()
            )
        }
        await lookupGate.waitUntilStarted()

        presentation.presentationGeneration = 8
        presentation.speciesData = speciesData(
            scientificName: "Nasua nasua",
            override: "Nasua nasua"
        )
        _ = subject.review.beginReviewAction(scanId: "scan-review")
        await lookupGate.release()
        _ = await task.value

        #expect(presentation.speciesData?.scientificName == "Nasua nasua")
        #expect(reviewHarness.events == [
            .loadSpecies("Procyon cancrivorus")
        ])
    }

    @Test func displayedSpeciesHydrationRejectsStaleIDFallback() async {
        let reviewHarness = IdentificationReviewCoordinatorHarness()
        let fallbackGate = InferenceOperationGate()
        reviewHarness.speciesIDLookupGates["Procyon cancrivorus"] =
            fallbackGate
        reviewHarness.speciesID = "stale-fallback-id"
        let subject = makeSubject(reviewHarness: reviewHarness)
        let presentation = ReviewWorkflowPresentationHarness(
            speciesData: speciesData(
                scientificName: "Procyon cancrivorus",
                override: "Procyon cancrivorus"
            )
        )
        let reviewGeneration = subject.review.beginReviewAction(
            scanId: "scan-review"
        )

        let task = Task { @MainActor in
            await subject.workflow.hydrateDisplayedSpecies(
                .init(
                    scientificName: "Procyon cancrivorus",
                    scanID: "scan-review",
                    modelContainer: nil,
                    presentationGeneration: 7,
                    reviewActionGeneration: reviewGeneration
                ),
                callbacks: presentation.callbacks()
            )
        }
        await fallbackGate.waitUntilStarted()

        presentation.presentationGeneration = 8
        presentation.speciesData = speciesData(
            scientificName: "Nasua nasua",
            override: "Nasua nasua"
        )
        _ = subject.review.beginReviewAction(scanId: "scan-review")
        await fallbackGate.release()

        #expect(await task.value == nil)
        #expect(presentation.speciesData?.scientificName == "Nasua nasua")
        #expect(reviewHarness.events == [
            .loadSpecies("Procyon cancrivorus"),
            .loadSpeciesID("Procyon cancrivorus")
        ])
    }

    private func makeSubject(
        reviewHarness: IdentificationReviewCoordinatorHarness,
        hydrationRecorder: ReviewWorkflowHydrationRecorder? = nil
    ) -> IdentificationReviewWorkflowSubject {
        let taskCoordinator = InferenceHydrationCoordinator(
            dependencies: .init(
                now: { Date(timeIntervalSinceReferenceDate: 10_000) },
                loadEnrichedSpeciesTimestamps: { [:] },
                persistEnrichedSpeciesTimestamps: { _ in }
            )
        )
        let review = reviewHarness.makeSubject()
        let speciesHydration = InferenceSpeciesHydrationCoordinator(
            taskCoordinator: taskCoordinator,
            referenceService: SpeciesReferenceHydrationService { _ in
                throw WorkflowTestError.unexpectedReferenceRequest
            },
            enrichmentService: InferenceSpeciesEnrichmentService(
                dependencies: .init { _, scope in
                    hydrationRecorder?.record(scope)
                    return EnrichScanResponse(success: true, data: nil)
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
        return IdentificationReviewWorkflowSubject(
            workflow: InferenceReviewWorkflowCoordinator(
                reviewCoordinator: review,
                taskCoordinator: taskCoordinator,
                speciesHydrationCoordinator: speciesHydration
            ),
            review: review
        )
    }

    private func reviewMutations(
        in events: [IdentificationReviewCoordinatorHarness.Event]
    ) -> [InferenceIdentificationReviewMutation] {
        events.compactMap { event in
            guard case .sync(let mutation) = event else { return nil }
            return mutation
        }
    }

    private func speciesData(
        scientificName: String = "Procyon lotor",
        override: String? = nil
    ) -> SpeciesData {
        SpeciesData(
            scanId: "scan-review",
            commonName: scientificName,
            scientificName: scientificName,
            insightData: InsightData(
                aiReasoning: "Presented reasoning",
                hazardType: "none"
            ),
            confidenceScore: 0.92,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "Terrestrial",
            aiScientificName: "Procyon lotor",
            userIdentificationOverride: override
        )
    }

    private func dictionaryRecord(
        id: String,
        scientificName _: String,
        commonName: String
    ) -> InferenceSpeciesDictionaryRecord {
        InferenceSpeciesDictionaryRecord(
            id: id,
            commonNames: ["en": commonName],
            kingdom: "Animalia",
            phylum: "Chordata",
            className: "Mammalia",
            order: "Carnivora",
            family: "Procyonidae",
            genus: "Procyon",
            wikipediaOverview: nil,
            hazardType: "none",
            referenceImageURL: nil,
            wikipediaURL: nil,
            iucnRedListStatus: nil,
            habitatDescription: nil,
            gbifTaxonKey: nil
        )
    }

    private enum WorkflowTestError: Error {
        case unexpectedReferenceRequest
    }
}

import Foundation
import Testing

@testable import Merian

private enum SpeciesPresentationTestError: Error {
    case unexpectedReferenceRequest
}

private actor SpeciesPresentationPersistenceRecorder {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func snapshot() -> [String] {
        values
    }
}

@MainActor
private final class SpeciesPresentationDependencyRecorder {
    private(set) var enrichmentScopes:
        [InferenceSpeciesEnrichmentService.Scope] = []

    func record(_ scope: InferenceSpeciesEnrichmentService.Scope) {
        enrichmentScopes.append(scope)
    }
}

@MainActor
private final class SpeciesPresentationHarness {
    let state: InferencePresentationState
    let writes: InferenceWriteCoordinator
    let review: InferenceIdentificationReviewCoordinator
    let hydrationTasks: InferenceHydrationCoordinator
    let subject: InferenceSpeciesPresentationCoordinator

    init(recorder: SpeciesPresentationDependencyRecorder? = nil) {
        let recorder = recorder ?? SpeciesPresentationDependencyRecorder()
        state = InferencePresentationState()
        writes = InferenceWriteCoordinator()
        hydrationTasks = InferenceHydrationCoordinator(
            dependencies: .init(
                now: { Date(timeIntervalSinceReferenceDate: 1_000) },
                loadEnrichedSpeciesTimestamps: { [:] },
                persistEnrichedSpeciesTimestamps: { _ in }
            )
        )
        review = InferenceIdentificationReviewCoordinator(
            writeCoordinator: writes,
            reviewService: InferenceIdentificationReviewService(
                loadSpecies: { _ in nil },
                loadSpeciesID: { _ in nil },
                syncReview: { _ in }
            ),
            snapshotService: InferenceReviewSnapshotService { _, _ in nil },
            dependencies: .init(
                beginOverride: { _, _, _ in },
                persistReview: { _, _ in },
                clearFlag: { _, _ in },
                persistSpeciesPatch: { _, _, _ in },
                sharedPostID: { _ in nil },
                sendPostRefresh: { _ in },
                processIdentificationUpdate: { _ in },
                logSnapshotFailure: { _, _, _ in },
                logSpeciesLookupFailure: { _ in },
                logSyncFailure: { _ in }
            )
        )
        let hydration = InferenceSpeciesHydrationCoordinator(
            taskCoordinator: hydrationTasks,
            referenceService: SpeciesReferenceHydrationService { _ in
                throw SpeciesPresentationTestError.unexpectedReferenceRequest
            },
            enrichmentService: InferenceSpeciesEnrichmentService(
                dependencies: .init { _, scope in
                    recorder.record(scope)
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
        subject = InferenceSpeciesPresentationCoordinator(
            presentationState: state,
            writeCoordinator: writes,
            reviewCoordinator: review,
            speciesHydrationCoordinator: hydration
        )
    }
}

@MainActor
@Suite("Inference Species Presentation Coordinator")
struct SpeciesPresentationCoordinatorTests {
    @Test func callbackBundleReadsAndPublishesThroughPresentationState() {
        let harness = SpeciesPresentationHarness()
        let original = speciesData()
        harness.state.replaceSpeciesData(original)
        harness.state.replaceReferenceState(.loading)
        let callbacks = harness.subject.makeHydrationCallbacks()

        #expect(callbacks.currentSpeciesData()?.scanId == "scan-a")
        #expect(callbacks.currentReferenceState() == .loading)
        #expect(
            callbacks.currentPresentationGeneration()
                == harness.writes.generation
        )

        var updated = original
        updated.commonName = "Updated Monarch"
        callbacks.publishSpeciesData(updated)
        callbacks.publishReferenceState(
            .loaded(["https://example.com/reference.jpg"])
        )
        callbacks.setLoading(.metadata, true)
        callbacks.setLoading(.lookalikes, true)

        #expect(harness.state.speciesData?.commonName == "Updated Monarch")
        #expect(
            harness.state.activeMedia.referenceState
                == .loaded(["https://example.com/reference.jpg"])
        )
        #expect(harness.state.isEnrichmentLoading)
        #expect(harness.state.isLookalikesLoading)
    }

    @Test func reviewCallbacksUseTheSamePresentationAndHydrationBoundary() {
        let harness = SpeciesPresentationHarness()
        let original = speciesData()
        harness.state.replaceSpeciesData(original)
        harness.state.replaceReferenceState(
            .loaded(["https://example.com/original.jpg"])
        )
        let callbacks = harness.subject.makeReviewWorkflowCallbacks()

        callbacks.applyPresentation(
            IdentificationReviewPresentation.override(
                original,
                scientificName: "Danaus gilippus"
            )
        )

        #expect(
            harness.state.speciesData?.scientificName == "Danaus gilippus"
        )
        #expect(harness.state.activeMedia.referenceState == .empty)
        #expect(
            callbacks.speciesHydration.currentSpeciesData()?.scientificName
                == "Danaus gilippus"
        )
    }

    @Test func exactIdentityRequiresSpeciesPresentationAndReviewGenerations() {
        let harness = SpeciesPresentationHarness()
        harness.state.replaceSpeciesData(speciesData())
        let generation = harness.writes.generation
        let callbacks = harness.subject.makeHydrationCallbacks()

        #expect(callbacks.isPresentationCurrent(identity(generation: generation)))
        #expect(
            callbacks.isPresentationCurrent(
                identity(
                    scanId: "SCAN-A",
                    scientificName: "DANAUS PLEXIPPUS",
                    generation: generation
                )
            )
        )
        #expect(
            !callbacks.isPresentationCurrent(
                identity(scanId: "scan-b", generation: generation)
            )
        )
        #expect(
            !callbacks.isPresentationCurrent(
                identity(
                    scientificName: "Danaus gilippus",
                    generation: generation
                )
            )
        )

        let reviewGeneration = harness.subject.beginReviewAction(
            scanId: "scan-a"
        )
        let reviewedIdentity = identity(
            generation: generation,
            reviewGeneration: reviewGeneration
        )
        #expect(callbacks.isPresentationCurrent(reviewedIdentity))
        _ = harness.subject.beginReviewAction(scanId: "scan-a")
        #expect(!callbacks.isPresentationCurrent(reviewedIdentity))

        harness.writes.resetPresentationWrites()
        #expect(
            !callbacks.isPresentationCurrent(
                identity(generation: generation)
            )
        )
    }

    @Test func alternativesExhaustionAdvancesExactReviewOwner() {
        let harness = SpeciesPresentationHarness()
        harness.state.replaceSpeciesData(speciesData())
        let previousGeneration = harness.subject.beginReviewAction(
            scanId: "scan-a"
        )

        harness.subject.markAlternativesExhausted(expectedScanId: "SCAN-A")

        #expect(harness.state.speciesData?.alternativesExhausted == true)
        #expect(
            !harness.review.isReviewActionCurrent(
                scanId: "scan-a",
                generation: previousGeneration
            )
        )
    }

    @Test func alternativesExhaustionRejectsMismatchedPresentation() {
        let harness = SpeciesPresentationHarness()
        harness.state.replaceSpeciesData(speciesData())
        let currentGeneration = harness.subject.beginReviewAction(
            scanId: "scan-a"
        )

        harness.subject.markAlternativesExhausted(expectedScanId: "scan-b")

        #expect(harness.state.speciesData?.alternativesExhausted == false)
        #expect(
            harness.review.isReviewActionCurrent(
                scanId: "scan-a",
                generation: currentGeneration
            )
        )
    }

    @Test func alternativesExhaustionWithoutExpectedScanUsesCurrentOwner() {
        let harness = SpeciesPresentationHarness()
        harness.state.replaceSpeciesData(speciesData())
        let previousGeneration = harness.subject.beginReviewAction(
            scanId: "scan-a"
        )

        harness.subject.markAlternativesExhausted(expectedScanId: nil)

        #expect(harness.state.speciesData?.alternativesExhausted == true)
        #expect(
            !harness.review.isReviewActionCurrent(
                scanId: "scan-a",
                generation: previousGeneration
            )
        )
    }

    @Test func persistenceUsesBackgroundAndReviewSpecificWriteOwners()
        async {
        let harness = SpeciesPresentationHarness()
        harness.state.replaceSpeciesData(speciesData())
        let callbacks = harness.subject.makeHydrationCallbacks()
        let persistence = SpeciesPresentationPersistenceRecorder()
        let backgroundGate = InferenceOperationGate()

        callbacks.enqueuePersistence(
            .init(
                identity: identity(generation: harness.writes.generation),
                operation: {
                    await backgroundGate.wait()
                    await persistence.append("background")
                }
            )
        )
        await backgroundGate.waitUntilStarted()
        #expect(harness.writes.snapshot.active == 1)

        await backgroundGate.release()
        _ = harness.writes.beginAuthTransitionFence()
        await harness.writes.awaitQuiescence()
        harness.writes.finishAuthTransitionFence()
        #expect(await persistence.snapshot() == ["background"])

        let reviewGeneration = harness.subject.beginReviewAction(
            scanId: "scan-a"
        )
        let reviewGate = InferenceOperationGate()
        callbacks.enqueuePersistence(
            .init(
                identity: identity(
                    generation: harness.writes.generation,
                    reviewGeneration: reviewGeneration
                ),
                operation: {
                    await reviewGate.wait()
                    await persistence.append("review")
                }
            )
        )
        await reviewGate.waitUntilStarted()
        #expect(harness.writes.snapshot.active == 0)

        await reviewGate.release()
        _ = harness.writes.beginAuthTransitionFence()
        await harness.writes.awaitQuiescence()
        harness.writes.finishAuthTransitionFence()
        #expect(await persistence.snapshot() == ["background", "review"])
    }

    @Test func staleAndAuthFencedPersistenceCannotExecute() async {
        let harness = SpeciesPresentationHarness()
        harness.state.replaceSpeciesData(speciesData())
        let callbacks = harness.subject.makeHydrationCallbacks()
        let persistence = SpeciesPresentationPersistenceRecorder()
        let staleGeneration = harness.writes.generation
        harness.writes.resetPresentationWrites()

        callbacks.enqueuePersistence(
            .init(
                identity: identity(generation: staleGeneration),
                operation: { await persistence.append("stale") }
            )
        )
        _ = harness.writes.beginAuthTransitionFence()
        await harness.writes.awaitQuiescence()
        #expect(await persistence.snapshot().isEmpty)

        callbacks.enqueuePersistence(
            .init(
                identity: identity(generation: harness.writes.generation),
                operation: { await persistence.append("auth-fenced") }
            )
        )
        await Task.yield()
        #expect(await persistence.snapshot().isEmpty)
        harness.writes.finishAuthTransitionFence()
    }

    @Test func liveSchedulingAdmitsOnlyResolvedNonhumanBiologicalResults()
        async {
        let recorder = SpeciesPresentationDependencyRecorder()
        let harness = SpeciesPresentationHarness(recorder: recorder)
        var biological = speciesData()
        biological.wikipediaOverview = "Already hydrated."
        harness.state.replaceSpeciesData(biological)

        harness.subject.scheduleLiveHydrationIfNeeded(
            for: biological,
            modelContainer: nil,
            referencePolicy: .none
        )
        await harness.hydrationTasks.awaitCurrentTask(in: .live)

        #expect(
            Set(recorder.enrichmentScopes.map(\.rawValue))
                == Set(["enrichment", "lookalikes"])
        )

        let admittedScopes = recorder.enrichmentScopes
        let nonBiological = speciesData(
            commonName: "Rock",
            scientificName: "Inanimate object",
            isBiological: false
        )
        harness.state.replaceSpeciesData(nonBiological)
        harness.subject.scheduleLiveHydrationIfNeeded(
            for: nonBiological,
            modelContainer: nil,
            referencePolicy: .none
        )

        let human = speciesData(
            commonName: "Human",
            scientificName: "Homo sapiens"
        )
        harness.state.replaceSpeciesData(human)
        harness.subject.scheduleLiveHydrationIfNeeded(
            for: human,
            modelContainer: nil,
            referencePolicy: .none
        )

        #expect(recorder.enrichmentScopes == admittedScopes)
        #expect(
            !harness.hydrationTasks.snapshot.currentTaskSlots.contains(.live)
        )
    }

    private func identity(
        scanId: String = "scan-a",
        scientificName: String = "Danaus plexippus",
        generation: UInt64,
        reviewGeneration: UInt64? = nil
    ) -> InferenceSpeciesHydrationCoordinator.Identity {
        .init(
            scanId: scanId,
            scientificName: scientificName,
            presentationGeneration: generation,
            reviewActionGeneration: reviewGeneration
        )
    }

    private func speciesData(
        commonName: String = "Monarch",
        scientificName: String = "Danaus plexippus",
        isBiological: Bool = true
    ) -> SpeciesData {
        SpeciesData(
            scanId: "scan-a",
            commonName: commonName,
            scientificName: scientificName,
            insightData: InsightData(
                aiReasoning: "Orange wings",
                hazardType: "none"
            ),
            confidenceScore: 0.94,
            isBiological: isBiological,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "terrestrial",
            inferenceTier: "pro"
        )
    }
}

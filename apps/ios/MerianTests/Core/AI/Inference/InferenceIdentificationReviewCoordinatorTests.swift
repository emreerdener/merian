import SwiftData
import Testing

@testable import Merian

@MainActor
final class IdentificationReviewCoordinatorHarness {
    enum Event: Equatable {
        case loadSpecies(String)
        case loadSpeciesID(String)
        case beginOverride(String, String)
        case persistReview(InferenceIdentificationReviewMutation, String)
        case clearFlag(String)
        case persistPatch(String, String)
        case sync(InferenceIdentificationReviewMutation)
        case refresh(String)
        case milestone(String)
        case snapshotFailure(
            InferenceIdentificationReviewCoordinator.SnapshotPurpose,
            String
        )
        case speciesLookupFailure
        case syncFailure
    }

    var syncError: Error?
    var speciesLookupError: Error?
    var snapshotError: Error?
    var speciesID = "species-id"
    var speciesRecords = [String: InferenceSpeciesDictionaryRecord]()
    var speciesLookupGates = [String: InferenceOperationGate]()
    var speciesIDLookupGates = [String: InferenceOperationGate]()
    var syncGate: InferenceOperationGate?
    private(set) var events: [Event] = []

    var dependencies: InferenceIdentificationReviewCoordinator.Dependencies {
        .init(
            beginOverride: { [self] _, scanID, scientificName in
                events.append(.beginOverride(scanID, scientificName))
            },
            persistReview: { [self] _, mutation in
                events.append(
                    .persistReview(
                        mutation,
                        mutation.userReviewState.rawValue
                    )
                )
            },
            clearFlag: { [self] _, scanID in
                events.append(.clearFlag(scanID))
            },
            persistSpeciesPatch: { [self] _, scanID, patch in
                events.append(.persistPatch(scanID, patch.commonName))
            },
            sharedPostID: { _ in "post-id" },
            sendPostRefresh: { [self] postID in
                events.append(.refresh(postID))
            },
            processIdentificationUpdate: { [self] scanID in
                events.append(.milestone(scanID))
            },
            logSnapshotFailure: { [self] purpose, scanID, _ in
                events.append(.snapshotFailure(purpose, scanID))
            },
            logSpeciesLookupFailure: { [self] _ in
                events.append(.speciesLookupFailure)
            },
            logSyncFailure: { [self] _ in
                events.append(.syncFailure)
            }
        )
    }

    var reviewService: InferenceIdentificationReviewService {
        InferenceIdentificationReviewService(
            loadSpecies: { [self] scientificName in
                events.append(.loadSpecies(scientificName))
                if let gate = speciesLookupGates[scientificName] {
                    await gate.wait()
                }
                if let speciesLookupError { throw speciesLookupError }
                return speciesRecords[scientificName]
            },
            loadSpeciesID: { [self] scientificName in
                events.append(.loadSpeciesID(scientificName))
                if let gate = speciesIDLookupGates[scientificName] {
                    await gate.wait()
                }
                return speciesID
            },
            syncReview: { [self] mutation in
                events.append(.sync(mutation))
                if let syncGate {
                    await syncGate.wait()
                }
                if let syncError { throw syncError }
            }
        )
    }

    var snapshotService: InferenceReviewSnapshotService {
        InferenceReviewSnapshotService { [self] _, _ in
            if let snapshotError { throw snapshotError }
            return InferenceReviewSnapshot(
                speciesId: "snapshot-species",
                aiReasoning: "Snapshot reasoning"
            )
        }
    }

    func makeSubject(
        writeCoordinator: InferenceWriteCoordinator? = nil
    ) -> InferenceIdentificationReviewCoordinator {
        InferenceIdentificationReviewCoordinator(
            writeCoordinator: writeCoordinator ?? InferenceWriteCoordinator(),
            reviewService: reviewService,
            snapshotService: snapshotService,
            dependencies: dependencies
        )
    }
}

@MainActor
@Suite("Inference Identification Review Coordinator")
struct InferenceReviewCoordinatorTests {
    @Test func orderedMutationPersistsBeforeCloudAndPostSyncEffects() async throws {
        let harness = IdentificationReviewCoordinatorHarness()
        let subject = harness.makeSubject()
        let mutation = reviewMutation()
        let generation = subject.beginReviewAction(scanId: mutation.scanID)

        let task = subject.enqueueReviewMutation(
            mutation,
            actionGeneration: generation,
            modelContainer: try makeContainer()
        )
        await task?.value

        #expect(harness.events == [
            .persistReview(mutation, UserReviewState.userOverridden.rawValue),
            .sync(mutation),
            .refresh("post-id"),
            .milestone("scan-a")
        ])
    }

    @Test func syncFailureSuppressesRefreshAndMilestone() async {
        let harness = IdentificationReviewCoordinatorHarness()
        harness.syncError = ReviewTestError.expected
        let subject = harness.makeSubject()
        let mutation = reviewMutation()
        let generation = subject.beginReviewAction(scanId: mutation.scanID)

        let task = subject.enqueueReviewMutation(
            mutation,
            actionGeneration: generation,
            modelContainer: nil
        )
        await task?.value

        #expect(harness.events == [
            .sync(mutation),
            .syncFailure
        ])
    }

    @Test func replacedActionCannotEnterPersistenceOrTransport() async {
        let harness = IdentificationReviewCoordinatorHarness()
        let subject = harness.makeSubject()
        let mutation = reviewMutation()
        let replacedGeneration = subject.beginReviewAction(
            scanId: mutation.scanID
        )
        _ = subject.beginReviewAction(scanId: mutation.scanID)

        let task = subject.enqueueReviewMutation(
            mutation,
            actionGeneration: replacedGeneration,
            modelContainer: nil
        )
        await task?.value

        #expect(harness.events.isEmpty)
    }

    @Test func authFenceRejectsNewPersistenceAndTransport() {
        let harness = IdentificationReviewCoordinatorHarness()
        let writeCoordinator = InferenceWriteCoordinator()
        #expect(writeCoordinator.beginAuthTransitionFence())
        let subject = harness.makeSubject(
            writeCoordinator: writeCoordinator
        )
        let mutation = reviewMutation()
        let generation = subject.beginReviewAction(scanId: mutation.scanID)

        let task = subject.enqueueReviewMutation(
            mutation,
            actionGeneration: generation,
            modelContainer: nil
        )

        #expect(task == nil)
        #expect(harness.events.isEmpty)
    }

    @Test func snapshotFailureIsTypedLoggedAndFailsClosed() throws {
        let harness = IdentificationReviewCoordinatorHarness()
        harness.snapshotError = ReviewTestError.expected
        let subject = harness.makeSubject()

        let result = subject.loadSnapshot(
            scanId: "scan-a",
            modelContext: ModelContext(try makeContainer()),
            purpose: .confirmation
        )

        guard case .failure = result else {
            Issue.record("Expected a failed snapshot read")
            return
        }
        #expect(harness.events == [
            .snapshotFailure(.confirmation, "scan-a")
        ])
    }

    @Test func failedDictionaryLookupUsesSilentIDFallback() async {
        let harness = IdentificationReviewCoordinatorHarness()
        harness.speciesLookupError = ReviewTestError.expected
        let subject = harness.makeSubject()

        let lookup = await subject.loadSpecies(scientificName: "Procyon lotor")
        let speciesID = await subject.loadSpeciesIDIfAvailable(
            scientificName: "Procyon lotor"
        )

        guard case .failure = lookup else {
            Issue.record("Expected a failed dictionary lookup")
            return
        }
        #expect(speciesID == "species-id")
        #expect(harness.events == [
            .loadSpecies("Procyon lotor"),
            .speciesLookupFailure,
            .loadSpeciesID("Procyon lotor")
        ])
    }

    private func reviewMutation() -> InferenceIdentificationReviewMutation {
        .userOverride(
            scanID: "scan-a",
            scientificName: "Procyon cancrivorus",
            confirmedSpeciesID: "species-id"
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(CurrentSchema.models)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    private enum ReviewTestError: Error {
        case expected
    }
}

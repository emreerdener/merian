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
    var beforePersistence: (@MainActor () -> Void)?
    var beginOverrideOverride: (@MainActor (ModelContainer, String, String, LocalAIIdentificationReview?) async -> Bool)?
    var persistReviewOverride: (@MainActor (ModelContainer, InferenceIdentificationReviewMutation, LocalAIIdentificationReview?) async -> Bool)?
    var syncGate: InferenceOperationGate?
    private(set) var events: [Event] = []

    var dependencies: InferenceIdentificationReviewCoordinator.Dependencies {
        .init(
            beginOverride: { [self] container, scanID, scientificName, expected in
                beforePersistence?()
                if let beginOverrideOverride { return await beginOverrideOverride(container, scanID, scientificName, expected) }
                events.append(.beginOverride(scanID, scientificName))
                return true
            },
            persistReview: { [self] container, mutation, expectedReview in
                beforePersistence?()
                if let persistReviewOverride { return await persistReviewOverride(container, mutation, expectedReview) }
                events.append(
                    .persistReview(
                        mutation,
                        mutation.userReviewState.rawValue
                    )
                )
                return true
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
    @Test func staleAuthorityFreeConfirmationCannotPersistOrReachLegacyServer() async throws {
        let container = try makeContainer(), context = ModelContext(container)
        let record = try #require(try context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let rejected = LocalAIIdentificationReview(authority: .init(revision: 1, state: .aiRejected,
            originScanID: "00000000-0000-4000-8000-000000000001", originIdentification: nil))
        record.aiIdentificationReviewData = try rejected.storedData(); try context.save()
        let harness = IdentificationReviewCoordinatorHarness()
        harness.persistReviewOverride = { container, mutation, expected in
            await BackgroundDatabaseActor(modelContainer: container).updateScanWithOverride(scanId: mutation.scanID,
                override: mutation.override, confirmed: mutation.confirmed, newConfirmedSpeciesId: mutation.confirmedSpeciesID,
                userReviewState: mutation.userReviewState, expectedReview: expected)
        }
        let subject = harness.makeSubject()
        let mutation = InferenceIdentificationReviewMutation.aiConfirmation(scanID: "scan-a", confirmedSpeciesID: "species")
        var published = false
        await subject.enqueueReviewMutation(mutation, actionGeneration: subject.beginReviewAction(scanId: "scan-a"),
            modelContainer: container, expectedReview: .init(), didPersist: { published = true })?.value
        let saved = try #require(try ModelContext(container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(saved.localAIIdentificationReview == rejected && !saved.userConfirmedIdentification)
        #expect(!published && harness.events.isEmpty)
    }

    @Test func staleOverrideCannotAdmitOrPublishOverNewerDurableReview() async throws {
        let container = try makeContainer(), context = ModelContext(container)
        let record = try #require(try context.fetch(FetchDescriptor<LocalScanRecord>()).first)
        let rejected = LocalAIIdentificationReview(authority: .init(revision: 1, state: .aiRejected,
            originScanID: "00000000-0000-4000-8000-000000000001", originIdentification: nil))
        record.aiIdentificationReviewData = try rejected.storedData(); try context.save()
        let harness = IdentificationReviewCoordinatorHarness()
        harness.beginOverrideOverride = { container, scanID, name, expected in
            await BackgroundDatabaseActor(modelContainer: container).beginScanIdentificationOverride(
                scanId: scanID, scientificName: name, expectedReview: expected)
        }
        let subject = harness.makeSubject()
        var published = false
        await subject.enqueueOverrideAdmission(scanId: "scan-a", scientificName: "Fixtureus changed",
            actionGeneration: subject.beginReviewAction(scanId: "scan-a"), modelContainer: container,
            expectedReview: .init(), didPersist: { published = true })?.value
        let saved = try #require(try ModelContext(container).fetch(FetchDescriptor<LocalScanRecord>()).first)
        #expect(saved.localAIIdentificationReview == rejected && saved.userIdentificationOverride == nil)
        #expect(!published && harness.events.isEmpty)
    }

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

    @Test func syncFailureSuppressesRefreshAndMilestone() async throws {
        let harness = IdentificationReviewCoordinatorHarness()
        harness.syncError = ReviewTestError.expected
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
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.insert(LocalScanRecord(id: "scan-a", speciesId: "species", scientificName: "Procyon lotor", commonName: "Raccoon"))
        try context.save()
        return container
    }

    private enum ReviewTestError: Error {
        case expected
    }
}

import Foundation
import SwiftData
import Testing
@testable import Merian

@MainActor
private final class VerifiedReviewCoordinatorHarness {
    let legacy = IdentificationReviewCoordinatorHarness()
    let writes = InferenceWriteCoordinator()
    let container: ModelContainer
    var syncGate: InferenceOperationGate?
    var applyGate: InferenceOperationGate?
    var failure = false
    var preparationFailure = false
    var outcome: VerifiedSpeciesReviewOutcome
    var events: [String] = []

    init() throws {
        container = try ScanRepositoryTestSupport.makeContext().container
        outcome = .acknowledged(try VerifiedReviewFixtures.decode(VerifiedReviewFixtures.review()))
    }
    func seed() async throws {
        try await HistoricalDatabaseActor(modelContainer: container).reconcileScanPage(
            responses: [VerifiedReviewFixtures.row(VerifiedReviewFixtures.history())])
    }
    func makeSubject() -> InferenceIdentificationReviewCoordinator {
        let service = InferenceIdentificationReviewService(loadSpecies: { _ in nil }, loadSpeciesID: { _ in nil },
            syncReview: { _ in Issue.record("Explicit review reached legacy RPC") },
            syncVerifiedReview: { [self] _ in
                events.append("send")
                if let syncGate { await syncGate.wait() }
                if failure { throw ConfirmedSpeciesReview.IntegrityError.invalidEnvelope }
                return outcome
            })
        return InferenceIdentificationReviewCoordinator(writeCoordinator: writes, reviewService: service,
            snapshotService: legacy.snapshotService, dependencies: legacy.dependencies,
            verifiedDependencies: .init(prepare: { [self] container, mutation in
                if preparationFailure { throw ConfirmedSpeciesReview.IntegrityError.invalidEnvelope }
                let request = try await BackgroundDatabaseActor(modelContainer: container).prepareVerifiedSpeciesReview(mutation)
                events.append("prepared")
                return request
            }, apply: { [self] container, scanID, review, intent in
                if let applyGate { await applyGate.wait() }
                let saved = try await BackgroundDatabaseActor(modelContainer: container).applyVerifiedSpeciesReview(
                    scanID: scanID, review: review, acknowledging: intent)
                events.append("saved")
                return saved
            }))
    }
    func submit(_ subject: InferenceIdentificationReviewCoordinator) -> Task<Void, Never>? {
        let mutation = InferenceIdentificationReviewMutation.userOverride(scanID: VerifiedReviewFixtures.scanID,
            scientificName: "Examplea testus", confirmedSpeciesID: nil)
        return subject.enqueueVerifiedReviewMutation(mutation,
            actionGeneration: subject.beginReviewAction(scanId: mutation.scanID), modelContainer: container,
            didPrepare: { [self] in events.append("pending") },
            didReconcile: { [self] _ in events.append("present") })
    }
    func savedReview() throws -> ConfirmedSpeciesReview? {
        try ModelContext(container).fetch(FetchDescriptor<LocalScanRecord>()).first?.confirmedSpeciesReview
    }
}

@MainActor
struct VerifiedSpeciesReviewCoordinatorTests {
    @Test func durableIntentPrecedesSendAndAuthorityPrecedesPresentation() async throws {
        let harness = try VerifiedReviewCoordinatorHarness(); try await harness.seed()
        let subject = harness.makeSubject()
        await harness.submit(subject)?.value
        #expect(harness.events == ["prepared", "pending", "send", "saved", "present"])
        #expect(try harness.savedReview()?.revision == 1)
        #expect(harness.legacy.events.suffix(2) == [.refresh("post-id"), .milestone(VerifiedReviewFixtures.scanID)])
    }

    @Test func failedPreparationDoesNotPublishOrCallServer() async throws {
        let harness = try VerifiedReviewCoordinatorHarness(); try await harness.seed()
        harness.preparationFailure = true
        let subject = harness.makeSubject()
        await harness.submit(subject)?.value
        #expect(harness.events.isEmpty && harness.legacy.events == [.syncFailure])
    }

    @Test func missingScanNeverBeginsPreparationOrPublishes() async throws {
        let harness = try VerifiedReviewCoordinatorHarness()
        let subject = harness.makeSubject()
        await harness.submit(subject)?.value
        #expect(harness.events.isEmpty && harness.legacy.events.isEmpty)
    }

    @Test func failedRequestRetainsPendingIntentWithoutAuthorityOrSuccessEffects() async throws {
        let harness = try VerifiedReviewCoordinatorHarness(); try await harness.seed()
        harness.failure = true
        let subject = harness.makeSubject()
        await harness.submit(subject)?.value
        #expect(harness.events == ["prepared", "pending", "send"])
        #expect(try harness.savedReview() == nil)
        #expect(harness.legacy.events == [.syncFailure])
    }

    @Test func accountTransitionRejectsCancellationIgnoringServerResponse() async throws {
        let harness = try VerifiedReviewCoordinatorHarness(); try await harness.seed()
        let gate = InferenceOperationGate(); harness.syncGate = gate
        let subject = harness.makeSubject()
        let task = harness.submit(subject)
        await gate.waitUntilStarted()
        #expect(harness.writes.beginAuthTransitionFence())
        await gate.release(); await task?.value
        #expect(try harness.savedReview() == nil)
        #expect(!harness.events.contains("saved") && !harness.events.contains("present"))
        await harness.writes.awaitQuiescence()
        harness.writes.finishAuthTransitionFence()
    }

    @Test func accountTransitionDrainsApplyBeforeItCanReplaceTheStore() async throws {
        let harness = try VerifiedReviewCoordinatorHarness(); try await harness.seed()
        let gate = InferenceOperationGate(); harness.applyGate = gate
        let subject = harness.makeSubject(); let task = harness.submit(subject)
        await gate.waitUntilStarted()
        #expect(harness.writes.beginAuthTransitionFence())
        var transitionFinished = false
        let transition = Task { @MainActor in
            await harness.writes.awaitQuiescence(); transitionFinished = true
        }
        await Task.yield()
        #expect(!transitionFinished)
        await gate.release(); await task?.value; await transition.value
        #expect(transitionFinished && !harness.events.contains("present"))
        #expect(try harness.savedReview()?.revision == 1)
        harness.writes.finishAuthTransitionFence()
    }

    @Test func replacedActionSavesItsReceiptButCannotPublishOverNewerIntent() async throws {
        let harness = try VerifiedReviewCoordinatorHarness(); try await harness.seed()
        let gate = InferenceOperationGate(); harness.syncGate = gate
        let subject = harness.makeSubject(); let task = harness.submit(subject)
        await gate.waitUntilStarted()
        _ = subject.beginReviewAction(scanId: VerifiedReviewFixtures.scanID)
        await gate.release(); await task?.value
        #expect(try harness.savedReview()?.revision == 1)
        #expect(!harness.events.contains("present"))
    }

    @Test func revisionConflictReconcilesWithoutResubmittingSelection() async throws {
        let harness = try VerifiedReviewCoordinatorHarness(); try await harness.seed()
        harness.outcome = .reconciled(try VerifiedReviewFixtures.decode(VerifiedReviewFixtures.review(4, name: nil)))
        let subject = harness.makeSubject(); await harness.submit(subject)?.value
        #expect(harness.events.filter { $0 == "send" }.count == 1)
        #expect(try harness.savedReview()?.revision == 4 && harness.savedReview()?.identity == nil)
    }
}

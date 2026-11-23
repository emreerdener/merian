import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Accepted Capture execution recovery", .serialized, .sharedProcessState(.offlineQueueManager))
struct SharedMediaCaptureExecutionRecoveryTests {
    typealias Store = SharedMediaCaptureArtifactWriterTests.Store
    let fixture = SharedMediaCaptureResultWriterTests()

    @Test(arguments: SharedMediaCaptureReservationBoundary.allCases)
    func uncertainClaimSaveRecoversWithoutChangingInferenceIdentity(_ boundary: SharedMediaCaptureReservationBoundary) async throws {
        let store = try await Store(), owner = try await store.open()
        let plan = try await fixture.prepare(store, owner: owner)
        let beforePage = try await owner.captureExecutionRecoveryPage()
        let pending = try #require(beforePage.candidates.first)
        #expect(pending.status == .pending && pending.attemptCount == 0)
        try owner.configureCaptureSubmissionWritingForTesting { if $0 == boundary { throw SharedMediaStorageFailure.unavailable } }
        await #expect(throws: (any Error).self) { try await owner.beginAppCaptureExecution(pending, now: Date()) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open(); try await cold.resumeAppCaptureRoot()
        let page = try await cold.captureExecutionRecoveryPage()
        let recovered = try #require(page.candidates.first)
        #expect(recovered.scanID == plan.scanID && recovered.generation == plan.generation)
        #expect(recovered.attemptCount == (boundary == .afterSave ? 1 : 0))
        let claim = try await cold.beginAppCaptureExecution(recovered, now: Date())
        #expect(claim.status == .running && claim.generation == plan.generation)
        let due = Date().addingTimeInterval(30)
        let waiting = try await cold.postponeAppCaptureExecution(claim, until: due)
        #expect(waiting.status == .waiting && waiting.due == due)
        await #expect(throws: (any Error).self) { try await cold.postponeAppCaptureExecution(claim, until: due) }
        let context = ModelContext(store.container); context.autosaveEnabled = false
        let job = try #require(try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: plan.scanID.uuidString.lowercased())))
        #expect(InferenceGenerationMetadataContract.matches(plan.generation, in: job.metadataJSON))
        #expect(try context.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func exhaustedAttemptPausesAndQueueStateMustMatch() async throws {
        let store = try await Store(), owner = try await store.open()
        _ = try await fixture.prepare(store, owner: owner)
        let context = ModelContext(store.container); context.autosaveEnabled = false
        let job = try #require(try context.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        let row = try #require(try context.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        job.attemptCount = OfflineQueueRetryPolicy.maximumAutomaticRetryAttempts
        row.queueAttemptCount = job.attemptCount
        try context.save()
        let page = try await owner.captureExecutionRecoveryPage(), pending = try #require(page.candidates.first)
        await #expect(throws: (any Error).self) { try await owner.beginAppCaptureExecution(pending, now: Date()) }
        let paused = try await owner.postponeAppCaptureExecution(pending, until: Date())
        #expect(paused.status == .needsAttention && paused.due == nil)
        #expect(try await owner.captureExecutionRecoveryPage().candidates.isEmpty)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func lostDispatchAcknowledgementIsRecoveryOnlyAfterColdOpen() async throws {
        let store = try await Store(), owner = try await store.open()
        let plan = try await fixture.prepare(store, owner: owner)
        let page = try await owner.captureExecutionRecoveryPage()
        let pending = try #require(page.candidates.first)
        let claim = try await owner.beginAppCaptureExecution(pending, now: Date())
        try owner.configureCaptureSubmissionWritingForTesting { if $0 == .afterSave { throw SharedMediaStorageFailure.unavailable } }
        await #expect(throws: (any Error).self) { try await owner.reserveAppCaptureDispatch(claim) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open(); try await cold.resumeAppCaptureRoot()
        let recoveredPage = try await cold.captureExecutionRecoveryPage()
        let recovered = try #require(recoveredPage.candidates.first)
        let intent = try #require(recovered.dispatch)
        #expect(intent.scanID == plan.scanID && intent.generation == plan.generation)
        let nextClaim = try await cold.beginAppCaptureExecution(recovered, now: Date())
        #expect(nextClaim.dispatch == intent)
        await #expect(throws: (any Error).self) { try await cold.reserveAppCaptureDispatch(nextClaim) }
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func committedResultIsExcludedAndPartialResultCannotRedispatch() async throws {
        let store = try await Store(), owner = try await store.open()
        let plan = try await fixture.prepare(store, owner: owner)
        try await fixture.stage(plan, owner: owner)
        let account = InferenceCompletionAccountScope(ownerID: plan.ownerID, isCurrent: { true }, release: {})
        defer { account.finish() }
        _ = try await owner.completeAppCaptureSubmission(scanID: plan.scanID, submissionGeneration: plan.generation,
            attemptGeneration: plan.generation, resultData: fixture.response(plan), account: account)
        #expect(try await owner.captureExecutionRecoveryPage().candidates.isEmpty)
        let context = ModelContext(store.container); context.autosaveEnabled = false
        let job = try #require(try context.fetchOfflineJob(id: OfflineQueueManager.scanIngestionJobId(scanId: plan.scanID.uuidString.lowercased())))
        job.status = .pending
        job.metadataJSON = try SharedMediaCaptureSubmissionContextTests.context(plan).jobMetadataJSON
        try context.save()
        await #expect(throws: (any Error).self) { try await owner.captureExecutionRecoveryPage() }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
}

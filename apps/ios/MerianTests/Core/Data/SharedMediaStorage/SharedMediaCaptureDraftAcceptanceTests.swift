import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Capture whole draft handoff", .serialized, .sharedProcessState(.offlineQueueManager))
struct SharedMediaCaptureDraftAcceptanceTests {
    typealias Store = SharedMediaCaptureArtifactWriterTests.Store

    private func plan(_ store: Store) throws -> CaptureInitialEvidencePlan {
        try .init(ownerID: store.base.ownerID, scanID: store.input.scanID,
            generation: store.input.submissionGeneration, items: (0..<2).map { _ in
                .audio(.init(source: .init(mediaID: UUID(), contentType: "audio/wav", byteCount: store.bytes.count,
                    sha256: SharedMediaAcquisitionEncoding.digest(store.bytes)), preparedMediaID: UUID()))
            } + [.description("Synthetic whole draft note")])
    }

    @Test func wholeObservationCommitsBeforeAnyUploadAndReplayDoesNotReadSources() async throws {
        let store = try await Store(), owner = try await store.open(), plan = try plan(store)
        try await owner.resumeAppCaptureRoot()
        let context = try SharedMediaCaptureSubmissionContextTests.context(plan), bytes = store.bytes
        var requested: [UUID] = []
        let accepted = try await owner.acceptAppCaptureDraft(plan: plan, context: context) { input in
            requested.append(input.mediaID)
            #expect(input.scanID == plan.scanID && input.submissionGeneration == plan.generation)
            return bytes
        }
        #expect(requested == plan.uploads.map { $0.artifact.mediaID })
        #expect(owner.isReadyForCaptureDispatch && !owner.isReadyForAppDispatch)
        let read = ModelContext(store.container); read.autosaveEnabled = false
        let saved = try #require(try SharedMediaCaptureSubmissionReceipt.matching(scanID: plan.scanID, generation: plan.generation, in: read))
        #expect(saved.state == .accepted(accepted) && saved.artifacts.count == 2)
        #expect(saved.artifacts.allSatisfy { $0.remoteStage == nil })
        #expect(throws: (any Error).self) { try SharedMediaCaptureUploadReadiness.require(saved) }
        #expect(try read.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(try read.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 1)
        let page = try await owner.captureExecutionRecoveryPage()
        #expect(page.candidates.count == 1 && page.nextCursor == nil)
        let pending = try #require(page.candidates.first)
        let firstTime = Date(timeIntervalSince1970: 1_800_000_000)
        let secondTime = firstTime.addingTimeInterval(30)
        let due = secondTime.addingTimeInterval(30)
        let firstClaim = try await owner.beginAppCaptureExecution(pending, now: firstTime)
        let firstWaiting = try await owner.postponeAppCaptureExecution(firstClaim, until: secondTime)
        let secondClaim = try await owner.beginAppCaptureExecution(firstWaiting, now: secondTime)
        let waiting = try await owner.postponeAppCaptureExecution(secondClaim, until: due)
        #expect(waiting.status == .waiting && waiting.attemptCount == 2 && waiting.generation == plan.generation && waiting.due == due)
        let before = ModelContext(store.container); before.autosaveEnabled = false
        let job = try #require(try before.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        let queue = try #require(try before.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        let retainedState = RetrySnapshot(job: job, queue: queue)
        #expect(InferenceGenerationMetadataContract.matches(plan.generation, in: job.metadataJSON))
        #expect(queue.queueAttemptCount == 2 && queue.queueNextRetryAt == due)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        try await atStage("cold accepted-draft qualification") { try await cold.resumeAppCaptureRoot() }
        let replay = try await atStage("accepted-draft replay") {
            try await cold.acceptAppCaptureDraft(plan: plan, context: context) { _ in
                Issue.record("Accepted replay attempted a draft read")
                throw SharedMediaStorageFailure.closed
            }
        }
        #expect(replay == accepted)
        let after = ModelContext(store.container); after.autosaveEnabled = false
        let retained = try #require(try after.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        let retainedQueue = try #require(try after.fetch(FetchDescriptor<OfflineQueuedScan>()).first)
        #expect(RetrySnapshot(job: retained, queue: retainedQueue) == retainedState)
        #expect(retained.attemptCount == 2 && retained.status == .waiting)
        #expect(InferenceGenerationMetadataContract.matches(plan.generation, in: retained.metadataJSON))
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func foreignGenerationCannotQualifyOrReplayAnAcceptedDraft() async throws {
        let store = try await Store(), owner = try await store.open(), plan = try plan(store)
        try await owner.resumeAppCaptureRoot()
        let context = try SharedMediaCaptureSubmissionContextTests.context(plan), bytes = store.bytes
        _ = try await atStage("foreign-generation fixture acceptance") {
            try await owner.acceptAppCaptureDraft(plan: plan, context: context) { _ in bytes }
        }
        let read = ModelContext(store.container); read.autosaveEnabled = false
        let job = try #require(try read.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        job.metadataJSON = InferenceGenerationMetadataContract.setting(UUID(), in: job.metadataJSON)
        try read.save()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        await #expect(throws: (any Error).self) { try await cold.resumeAppCaptureRoot() }
        await #expect(throws: (any Error).self) {
            try await cold.acceptAppCaptureDraft(plan: plan, context: context) { _ in
                Issue.record("Foreign generation reached a source reader")
                throw SharedMediaStorageFailure.closed
            }
        }
        #expect(!cold.isReadyForCaptureDispatch)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    private func atStage<Value>(_ stage: String, operation: () async throws -> Value) async throws -> Value {
        do { return try await operation() } catch {
            Issue.record("Unexpected draft handoff failure at stage: \(stage)")
            throw error
        }
    }

    private struct RetrySnapshot: Equatable {
        let metadata: String?
        let status: String
        let queueState: Int
        let attempts: [Int]
        let dates: [Date?]
        let errors: [String?]
        let needsAttention: Bool

        init(job: OfflineJobRecord, queue: OfflineQueuedScan) {
            metadata = job.metadataJSON; status = job.statusRaw; queueState = queue.scanStateRaw
            attempts = [job.attemptCount, queue.queueAttemptCount]
            dates = [job.lastAttemptAt, job.nextRunAt, job.updatedAt,
                     queue.queueLastAttemptAt, queue.queueNextRetryAt, queue.queueUpdatedAt]
            errors = [job.lastErrorCode, job.lastErrorMessage, queue.queueLastErrorCode, queue.queueLastErrorMessage]
            needsAttention = queue.queueNeedsAttention
        }
    }

    @Test func missingSecondSourcePreservesReservationAndColdResumeReadsOnlyMissingMember() async throws {
        let store = try await Store(), owner = try await store.open(), plan = try plan(store)
        try await owner.resumeAppCaptureRoot()
        let context = try SharedMediaCaptureSubmissionContextTests.context(plan), bytes = store.bytes
        let missing = plan.uploads[1].artifact.mediaID
        await #expect(throws: (any Error).self) {
            try await owner.acceptAppCaptureDraft(plan: plan, context: context) { input in
                if input.mediaID == missing { throw SharedMediaStorageFailure.unavailable }
                return bytes
            }
        }
        let read = ModelContext(store.container); read.autosaveEnabled = false
        let saved = try #require(try SharedMediaCaptureSubmissionReceipt.matching(scanID: plan.scanID, generation: plan.generation, in: read))
        #expect(saved.state == .reserved && saved.artifacts.count == 1 && saved.submission.context == context)
        #expect(try read.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try read.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        try await cold.resumeAppCaptureRoot()
        #expect(cold.isReadyForCaptureDraft && !cold.isReadyForCaptureDispatch && !cold.isReadyForAppDispatch)
        await #expect(throws: (any Error).self) { try await cold.inspectApp() }
        var reads: [UUID] = []
        _ = try await cold.acceptAppCaptureDraft(plan: plan, context: context) { input in
            reads.append(input.mediaID); return bytes
        }
        #expect(reads == [missing] && cold.isReadyForCaptureDispatch)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func pendingDraftCannotBeReplacedByAnotherObservation() async throws {
        let store = try await Store(), owner = try await store.open(), plan = try plan(store)
        try await owner.resumeAppCaptureRoot()
        let context = try SharedMediaCaptureSubmissionContextTests.context(plan)
        await #expect(throws: (any Error).self) {
            try await owner.acceptAppCaptureDraft(plan: plan, context: context) { _ in throw SharedMediaStorageFailure.unavailable }
        }
        #expect(owner.requiresCaptureRecovery)
        #expect(try ModelContext(store.container).fetchCount(FetchDescriptor<SharedMediaOrdinaryArtifactRecord>()) == 0)
        let replacement = try CaptureInitialEvidencePlan(ownerID: plan.ownerID, scanID: UUID(), generation: UUID(), items: plan.items)
        let replacementContext = try SharedMediaCaptureSubmissionContextTests.context(replacement)
        await #expect(throws: (any Error).self) {
            try await owner.acceptAppCaptureDraft(plan: replacement, context: replacementContext) { _ in
                Issue.record("Replacement reached a source reader"); throw SharedMediaStorageFailure.closed
            }
        }
        let read = ModelContext(store.container); read.autosaveEnabled = false
        #expect(try read.fetchCount(FetchDescriptor<SharedMediaOrdinarySubmissionRecord>()) == 1)
        #expect(try read.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        // The same retained owner requalifies automatically after both failed
        // handoffs; a successful retry does not require a process restart.
        let bytes = store.bytes
        _ = try await owner.acceptAppCaptureDraft(plan: plan, context: context) { _ in bytes }
        #expect(owner.isReadyForCaptureDispatch)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
}

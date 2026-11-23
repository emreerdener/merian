import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Capture whole observation reservation", .serialized)
@MainActor
struct SharedMediaCaptureSubmissionWriterTests {
    typealias Store = SharedMediaCaptureArtifactWriterTests.Store

    private func plan(_ store: Store, twoItems: Bool = false) throws -> CaptureInitialEvidencePlan {
        let source = ObservationVideoProvenance.Artifact(mediaID: store.input.mediaID, contentType: "audio/wav",
            byteCount: store.bytes.count, sha256: store.input.sha256)
        var items: [CaptureInitialEvidencePlan.Node] = [.audio(.init(source: source, preparedMediaID: UUID()))]
        if twoItems {
            items.append(.audio(.init(source: .init(mediaID: UUID(), contentType: "audio/wav",
                byteCount: store.bytes.count, sha256: store.input.sha256), preparedMediaID: UUID())))
        }
        items.append(.description("Synthetic submission note"))
        return try .init(ownerID: store.base.ownerID, scanID: store.input.scanID,
            generation: store.input.submissionGeneration, items: items)
    }

    @Test func wholeReservationSurvivesColdOpenAndChildrenConsumeItsExactMembership() async throws {
        let store = try await Store(), owner = try await store.open(), plan = try plan(store, twoItems: true)
        let context = try SharedMediaCaptureSubmissionContextTests.context(plan)
        let reserved = try await owner.reserveAppCaptureSubmission(plan, context: context)
        #expect(reserved.artifacts.isEmpty && reserved.state == .reserved)
        #expect(reserved.submission.context == context)
        let firstInput = try reserved.submission.artifact(mediaID: plan.uploads[0].artifact.mediaID)
        let first = try await owner.materializeAppCaptureArtifact(firstInput, bytes: store.bytes)
        #expect(first.request.inventoryRevision > reserved.submission.inventoryRevision)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        let resumed = try await cold.reserveAppCaptureSubmission(plan, context: context)
        #expect(resumed.submission == reserved.submission && resumed.artifacts == [first])
        #expect(resumed.reservedBytes < reserved.reservedBytes)
        let secondInput = try resumed.submission.artifact(mediaID: plan.uploads[1].artifact.mediaID)
        _ = try await cold.materializeAppCaptureArtifact(secondInput, bytes: store.bytes)
        let complete = try await cold.reserveAppCaptureSubmission(plan, context: context)
        #expect(complete.artifacts.count == 2 && complete.artifacts.allSatisfy { $0.phase == .ready })
        #expect(complete.state == .reserved) // Durable files alone do not admit the queue.
        let read = ModelContext(store.container)
        #expect(try read.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 0)
        #expect(try read.fetchCount(FetchDescriptor<OfflineJobRecord>()) == 0)
        #expect(!cold.isReadyForAppDispatch)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: SharedMediaCaptureReservationBoundary.allCases)
    func interruptionNeverCreatesAnUnrecoverableIdentity(_ boundary: SharedMediaCaptureReservationBoundary) async throws {
        let store = try await Store(), owner = try await store.open(), plan = try plan(store)
        let context = try SharedMediaCaptureSubmissionContextTests.context(plan)
        var reached = false
        try owner.configureCaptureSubmissionWritingForTesting { point in
            if point == boundary { reached = true; throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { _ = try await owner.reserveAppCaptureSubmission(plan, context: context) }
        #expect(reached)
        let read = ModelContext(store.container)
        let saved = try read.fetch(FetchDescriptor<SharedMediaOrdinarySubmissionRecord>())
        #expect(saved.count == (boundary == .afterSave ? 1 : 0))
        let bytes = saved.first?.requestData
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        let value = try await cold.reserveAppCaptureSubmission(plan, context: context)
        if let bytes { #expect(try value.submission.encoded() == bytes) }
        #expect(value.artifacts.isEmpty)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func changedContextAndUnlistedChildFailBeforeAnyAdditionalSave() async throws {
        let store = try await Store(), owner = try await store.open(), plan = try plan(store)
        let context = try SharedMediaCaptureSubmissionContextTests.context(plan)
        let saved = try await owner.reserveAppCaptureSubmission(plan, context: context)
        let changed = try SharedMediaCaptureSubmissionContextTests.context(plan, timestamp: context.timestamp.addingTimeInterval(1))
        await #expect(throws: (any Error).self) { _ = try await owner.reserveAppCaptureSubmission(plan, context: changed) }
        let input = try saved.submission.artifact(mediaID: plan.uploads[0].artifact.mediaID)
        let unlisted = SharedMediaCaptureArtifactInput(id: UUID(), scanID: input.scanID,
            submissionGeneration: input.submissionGeneration, mediaID: input.mediaID,
            planSHA256: input.planSHA256, itemIndex: input.itemIndex, role: input.role,
            frameIndex: nil, contentType: input.contentType, byteCount: input.byteCount, sha256: input.sha256)
        await #expect(throws: (any Error).self) { _ = try await owner.materializeAppCaptureArtifact(unlisted, bytes: store.bytes) }
        #expect(try store.rows().isEmpty)
        #expect(try await owner.reserveAppCaptureSubmission(plan, context: context) == saved)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func insufficientCapacityDoesNotSaveAParentOrClaimChildren() async throws {
        let store = try await Store(), owner = try await store.open(), plan = try plan(store)
        let context = try SharedMediaCaptureSubmissionContextTests.context(plan)
        try owner.configureCaptureSubmissionWritingForTesting(availableBytes: SharedMediaStoragePolicy.reserve)
        await #expect(throws: SharedMediaStorageFailure.capacity) { _ = try await owner.reserveAppCaptureSubmission(plan, context: context) }
        let read = ModelContext(store.container)
        #expect(try read.fetchCount(FetchDescriptor<SharedMediaOrdinarySubmissionRecord>()) == 0)
        #expect(try store.rows().isEmpty)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: SharedMediaCaptureReservationBoundary.allCases)
    func queueAcceptanceCommitsAllRowsAndReceiptTogether(_ boundary: SharedMediaCaptureReservationBoundary) async throws {
        let store = try await Store(), owner = try await store.open(), plan = try plan(store, twoItems: true)
        let context = try SharedMediaCaptureSubmissionContextTests.context(plan)
        let saved = try await owner.reserveAppCaptureSubmission(plan, context: context)
        await #expect(throws: (any Error).self) {
            _ = try await owner.acceptAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation)
        }
        for member in saved.submission.members {
            _ = try await owner.materializeAppCaptureArtifact(saved.submission.artifact(mediaID: member.mediaID), bytes: store.bytes)
        }
        try owner.configureCaptureSubmissionWritingForTesting { point in
            if point == boundary { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) {
            _ = try await owner.acceptAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation)
        }
        let read = ModelContext(store.container)
        let count = boundary == .beforeSave ? 0 : 1
        #expect(try read.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == count)
        #expect(try read.fetchCount(FetchDescriptor<OfflineJobRecord>()) == count)
        #expect(try read.fetchCount(FetchDescriptor<OfflineQueueEvent>()) == count)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        let receipt = try await cold.acceptAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation)
        #expect(try await cold.acceptAppCaptureSubmission(scanID: plan.scanID, generation: plan.generation) == receipt)
        let check = ModelContext(store.container)
        let scans = try check.fetch(FetchDescriptor<OfflineQueuedScan>())
        #expect(scans.count == 1 && scans.first?.fieldNotes == context.initialFieldNotes)
        #expect(scans.first?.mediaAuthorityRaw == SharedMediaCaptureAcceptance.mediaAuthority)
        let job = try #require(try check.fetch(FetchDescriptor<OfflineJobRecord>()).first)
        #expect(job.metadataJSON == context.jobMetadataJSON)
        #expect(!cold.isReadyForAppDispatch)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }
}

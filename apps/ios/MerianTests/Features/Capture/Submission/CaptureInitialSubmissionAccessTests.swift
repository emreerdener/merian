import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Initial Capture admission handoff", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct CaptureInitialSubmissionAccessTests {
    @Test func lostAcceptanceWakesRecoveryAndColdRetryReusesFunding() async throws {
        let store = try await SharedMediaCaptureArtifactWriterTests.Store(), owner = try await store.open()
        let session = CaptureInitialDraftSession(identity: .init(ownerID: store.base.ownerID,
            scanID: store.input.scanID, generation: store.input.submissionGeneration), requireCurrent: {}, resolveOwner: { owner })
        let source = try await session.retain(itemID: UUID(), bytes: store.bytes, role: .sourceAudio,
            contentType: "audio/wav", context: .init(origin: .microphone, cameraVerticalCenter: nil))
        let plan = try await session.prepare(items: [.audio(source), .description("Synthetic admission note")])
        let context = try SharedMediaCaptureSubmissionContextTests.context(plan)
        var claims = 0, finishes = 0, wakes = 0, saves = 0
        let access = CaptureInitialSubmissionAccess(begin: { current, retained, makeContext in
            #expect(current == plan)
            if let retained { return retained }
            claims += 1
            return try makeContext(current, context.metadata(plan: plan).funding)
        }, end: { scan in
            #expect(scan == plan.scanID); finishes += 1
        }, acceptanceAttemptFinished: { wakes += 1 })
        try owner.configureCaptureSubmissionWritingForTesting { point in
            if point == .beforeSave { saves += 1 }
            if saves == 2 && point == .afterSave { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) {
            _ = try await session.submit(using: access) { _, _ in context }
        }
        #expect(claims == 1 && finishes == 1 && wakes == 1)
        #expect(session.submissionContext == context)
        let read = ModelContext(store.container); read.autosaveEnabled = false
        let journal = try #require(try SharedMediaCaptureDraftJournalReceipt.matching(scanID: plan.scanID,
            generation: plan.generation, context: read))
        #expect(journal.value.phase == .accepted)
        #expect(try read.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        let reopened = try await CaptureInitialDraftSession.reopen(journal, requireCurrent: {}, resolveOwner: { cold })
        let receipt = try await reopened.submit(using: access) { _, _ in
            Issue.record("Cold retry rebuilt funding or sensor context")
            throw SharedMediaStorageFailure.conflict
        }
        #expect(reopened.submissionContext == context)
        #expect(claims == 1 && finishes == 2 && wakes == 2)
        let duplicate = try await reopened.submit(using: access) { _, _ in
            Issue.record("Duplicate retry rebuilt submission context")
            throw SharedMediaStorageFailure.conflict
        }
        #expect(duplicate == receipt && claims == 1 && wakes == 3)
        let after = ModelContext(store.container); after.autosaveEnabled = false
        #expect(try after.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func queueReplayClaimsOnlyTransientAdmissionAndChecksAccount() async throws {
        let manager = OfflineQueueManager.shared
        let prior = manager.captureLibraryAdmission
        defer { manager.captureLibraryAdmission = prior }
        let store = try await SharedMediaCaptureArtifactWriterTests.Store(), owner = try await store.open()
        let plan = try await SharedMediaCaptureResultWriterTests().prepare(store, owner: owner)
        let context = try SharedMediaCaptureSubmissionContextTests.context(plan)
        let id = plan.scanID.uuidString.lowercased()
        defer { manager.endNativeCaptureAdmission(scanID: plan.scanID) }
        manager.captureLibraryAdmission = { $0 == plan.ownerID }
        let result = try manager.beginNativeCaptureAdmission(plan: plan, retained: context) { _, _ in
            Issue.record("Replay claimed funding")
            throw SharedMediaStorageFailure.conflict
        }
        #expect(result == context && manager.inFlightInitialCaptureIDs.contains(id))
        #expect(throws: (any Error).self) {
            _ = try manager.beginNativeCaptureAdmission(plan: plan, retained: context) { _, _ in context }
        }
        manager.endNativeCaptureAdmission(scanID: plan.scanID)
        manager.captureLibraryAdmission = { _ in false }
        #expect(throws: (any Error).self) {
            _ = try manager.beginNativeCaptureAdmission(plan: plan, retained: context) { _, _ in context }
        }
        #expect(!manager.inFlightInitialCaptureIDs.contains(id))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func cancelledCommittedAcceptanceStillRequestsRecoveryWithoutReturningSuccess() async throws {
        let store = try await SharedMediaCaptureArtifactWriterTests.Store(), owner = try await store.open()
        let session = CaptureInitialDraftSession(identity: .init(ownerID: store.base.ownerID,
            scanID: store.input.scanID, generation: store.input.submissionGeneration), requireCurrent: {}, resolveOwner: { owner })
        let source = try await session.retain(itemID: UUID(), bytes: store.bytes, role: .sourceAudio,
            contentType: "audio/wav", context: .init(origin: .microphone, cameraVerticalCenter: nil))
        let plan = try await session.prepare(items: [.audio(source)])
        let context = try SharedMediaCaptureSubmissionContextTests.context(plan)
        var wakes = 0, finishes = 0, saves = 0
        let access = CaptureInitialSubmissionAccess(begin: { _, _, _ in context }, end: { _ in finishes += 1 },
            acceptanceAttemptFinished: { wakes += 1 })
        try owner.configureCaptureSubmissionWritingForTesting { point in
            if point == .beforeSave { saves += 1 }
            if saves == 2 && point == .afterSave { withUnsafeCurrentTask { $0?.cancel() } }
        }
        let task = Task { @MainActor in try await session.submit(using: access) { _, _ in context } }
        await #expect(throws: (any Error).self) { _ = try await task.value }
        #expect(wakes == 1 && finishes == 1)
        let read = ModelContext(store.container); read.autosaveEnabled = false
        let journal = try #require(try SharedMediaCaptureDraftJournalReceipt.matching(scanID: plan.scanID,
            generation: plan.generation, context: read))
        #expect(journal.value.phase == .accepted)
        #expect(try read.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
}

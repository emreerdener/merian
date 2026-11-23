import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Initial Capture feature handoff", .serialized)
@MainActor
struct CaptureInitialDraftSessionTests {
    typealias Store = SharedMediaCaptureArtifactWriterTests.Store

    @Test func interruptedVideoRetentionKeepsCompanionMembershipBeforeEitherWrite() async throws {
        let store = try await Store(), owner = try await store.open(), session = session(store, owner: owner)
        let item = UUID()
        let inputs: [CaptureInitialDraftSession.Retention] = [
            .init(itemID: item, bytes: Data(repeating: 7, count: 96), role: .sourceVideo,
                contentType: "video/mp4", context: .init(origin: .camera, cameraVerticalCenter: 0.5),
                review: .video(.init(duration: 2, isPro: true, composingCenter: 0.5,
                    scale: 1, offsetX: 0, offsetY: 0, displaySize: nil, quarterTurns: 0))),
            .init(itemID: item, bytes: store.bytes, role: .sourceCompanionAudio,
                contentType: "audio/wav", context: .init(origin: .videoAudio, cameraVerticalCenter: nil), review: nil)
        ]
        try owner.configureCaptureArtifactWritingForTesting { point in
            if point == .afterReadySave { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { try await session.retainSources(inputs) }
        let saved = try #require(session.journal)
        let identities = session.sources.map(\.input)
        #expect(saved.value.sources.count == 2)
        #expect(saved.value.items.first?.sourceIDs.count == 2)
        #expect(identities[0].itemIndex == identities[1].itemIndex)
        await #expect(throws: (any Error).self) { try await session.prepareReview() }
        try owner.configureCaptureArtifactWritingForTesting()
        #expect(try await session.retainSources(inputs) == identities)
        #expect(session.sources.allSatisfy { $0.ready })
        try await session.discard(itemID: item)
        #expect(session.sources.isEmpty)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func failedWriteRetainsExactSourceForRetryAndDiscard() async throws {
        let store = try await Store(), owner = try await store.open()
        let session = session(store, owner: owner), item = UUID()
        try owner.configureCaptureArtifactWritingForTesting { point in
            if point == .afterReadySave { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) {
            try await session.retain(itemID: item, bytes: store.bytes, role: .sourceAudio,
                contentType: "audio/wav", context: .init(origin: .microphone, cameraVerticalCenter: nil))
        }
        let held = try #require(session.sources.first)
        #expect(!held.ready)
        try owner.configureCaptureArtifactWritingForTesting()
        let ready = try await session.retain(itemID: item, bytes: store.bytes, role: .sourceAudio,
            contentType: "audio/wav", context: .init(origin: .microphone, cameraVerticalCenter: nil))
        #expect(ready == held.input && session.sources.count == 1)
        #expect(try await session.read(ready) == store.bytes)
        await #expect(throws: (any Error).self) {
            try await session.retain(itemID: item, bytes: Data(repeating: 1, count: store.bytes.count), role: .sourceAudio,
                contentType: "audio/wav", context: .init(origin: .microphone, cameraVerticalCenter: nil))
        }
        try await session.discard(itemID: item)
        #expect(session.sources.isEmpty)
        #expect(try store.rows().count == 1 && store.rows().first?.phaseRaw == "released")
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func wholeDraftFreezeAndLostAcceptanceRetryKeepOneObservation() async throws {
        let store = try await Store(), owner = try await store.open(), session = session(store, owner: owner)
        let first = try await session.retain(itemID: UUID(), bytes: store.bytes, role: .sourceAudio,
            contentType: "audio/wav", context: .init(origin: .microphone, cameraVerticalCenter: nil))
        let second = try await session.retain(itemID: UUID(), bytes: store.bytes, role: .sourceAudio,
            contentType: "audio/wav", context: .init(origin: .microphone, cameraVerticalCenter: nil))
        let items: [CaptureInitialEvidencePreparation.Item] = [.audio(second), .description("Synthetic note"), .audio(first)]
        let plan = try await session.prepare(items: items)
        #expect(plan.scanID == store.input.scanID && plan.generation == store.input.submissionGeneration)
        #expect(plan.uploads.map(\.artifact.mediaID) == [second.mediaID, first.mediaID])
        #expect(try await session.prepare(items: items) == plan)
        await #expect(throws: (any Error).self) { try await session.prepare(items: Array(items.reversed())) }
        let context = try SharedMediaCaptureSubmissionContextTests.context(plan)
        try owner.configureCaptureSubmissionWritingForTesting { point in
            if point == .afterSave { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { try await session.accept(context: context) }
        #expect(session.frozenPlan == plan)
        try await owner.resumeAppCaptureRoot()
        let reservedJournal = try await owner.readAppCaptureDraftJournal(scanID: plan.scanID, generation: plan.generation)
        #expect(reservedJournal?.value.phase == .submitting)
        #expect(reservedJournal?.value.frozenObservation?.bytes == (try plan.encoded()))
        try owner.configureCaptureSubmissionWritingForTesting()
        let acceptance = try await session.accept(context: context)
        #expect(try await session.accept(context: context) == acceptance)
        let read = ModelContext(store.container); read.autosaveEnabled = false
        #expect(try read.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(try read.fetchCount(FetchDescriptor<SharedMediaOrdinarySubmissionRecord>()) == 1)
        let acceptedJournal = try await owner.readAppCaptureDraftJournal(scanID: plan.scanID, generation: plan.generation)
        #expect(acceptedJournal?.value.phase == .accepted)
        #expect(acceptedJournal?.value.frozenObservation == reservedJournal?.value.frozenObservation)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private func session(_ store: Store, owner: SharedMediaNativeOriginalOwner) -> CaptureInitialDraftSession {
        .init(identity: .init(ownerID: store.base.ownerID, scanID: store.input.scanID,
            generation: store.input.submissionGeneration), requireCurrent: {}, resolveOwner: { owner })
    }

    @Test(arguments: [1, 2], SharedMediaCaptureReservationBoundary.allCases)
    func journalAndParentAdvanceAtomicallyAcrossLostReplies(_ targetSave: Int,
        _ fault: SharedMediaCaptureReservationBoundary) async throws {
        let store = try await Store(), owner = try await store.open(), session = session(store, owner: owner)
        let source = try await session.retain(itemID: UUID(), bytes: store.bytes, role: .sourceAudio,
            contentType: "audio/wav", context: .init(origin: .microphone, cameraVerticalCenter: nil))
        let plan = try await session.prepare(items: [.audio(source), .description("Synthetic handoff")])
        let input = try SharedMediaCaptureSubmissionContextTests.context(plan)
        var save = 0, reached = false
        try owner.configureCaptureSubmissionWritingForTesting { point in
            if point == .beforeSave { save += 1 }
            if save == targetSave && point == fault { reached = true; throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { _ = try await session.accept(context: input) }
        #expect(reached)
        let read = ModelContext(store.container); read.autosaveEnabled = false
        let journal = try SharedMediaCaptureDraftJournalReceipt.matching(scanID: plan.scanID, generation: plan.generation, context: read)
        let savedJournal = try #require(journal)
        let parent = try SharedMediaCaptureSubmissionReceipt.matching(scanID: plan.scanID, generation: plan.generation, in: read)
        try SharedMediaCaptureDraftJournalReceipt.requireGraph(savedJournal, parent: parent, context: read)
        let accepted = targetSave == 2 && fault == .afterSave
        #expect(savedJournal.value.phase == (accepted ? .accepted : targetSave == 1 && fault == .beforeSave ? .preparing : .submitting))
        #expect(try read.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == (accepted ? 1 : 0))
        try owner.configureCaptureSubmissionWritingForTesting()
        let acknowledgement = try await session.accept(context: input)
        #expect(try await session.accept(context: input) == acknowledgement)
        let after = ModelContext(store.container); after.autosaveEnabled = false
        #expect(try after.fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1)
        #expect(try after.fetchCount(FetchDescriptor<SharedMediaOrdinarySubmissionRecord>()) == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
}

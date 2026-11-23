import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Initial Capture cold draft recovery", .serialized)
@MainActor
struct CaptureInitialDraftRecoveryTests {
    typealias Store = SharedMediaCaptureArtifactWriterTests.Store

    @Test(arguments: SharedMediaCaptureDraftJournalBoundary.allCases)
    func recoveryPromotionSurvivesLostAcknowledgement(_ fault: SharedMediaCaptureDraftJournalBoundary) async throws {
        let store = try await Store(), owner = try await store.open()
        let input = CaptureDraftSourceBindingTests().source(store), itemID = UUID()
        let pending = try await owner.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
            replacing: nil, sources: [.init(itemID: itemID, input: input, state: .pending)],
            items: [.audio(id: itemID, source: input.id)])
        _ = try await owner.materializeAppCaptureSource(input, bytes: store.bytes)
        var reached = false
        try owner.configureCaptureDraftJournalForTesting { point in
            if point == fault { reached = true; throw SharedMediaStorageFailure.unavailable }
        }
        do {
            let reply = try await owner.recoverReadyAppCaptureDraft(pending)
            #expect(fault == .afterSave && reply.value.sources.first?.state == .ready)
        } catch { #expect(fault != .afterSave) }
        #expect(reached)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        try await cold.resumeAppCaptureRoot()
        let page = try await cold.captureDraftJournalPage()
        let discovered = try #require(page.drafts.first)
        #expect(discovered.value.sources.first?.state == (fault == .beforeSave ? .pending : .ready))
        let recovered = try await CaptureInitialDraftSession.reopen(discovered, requireCurrent: {}, resolveOwner: { cold })
        #expect(recovered.journal?.value.revision == pending.value.revision + 1)
        #expect(try await recovered.read(input) == store.bytes)
        #expect(try store.rows().count == 1)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func coldReopenAcknowledgesOnlyTheAlreadyCommittedOriginal() async throws {
        let store = try await Store(), owner = try await store.open()
        let input = CaptureDraftSourceBindingTests().source(store), itemID = UUID()
        let pending = try await owner.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
            replacing: nil, sources: [.init(itemID: itemID, input: input, state: .pending)],
            items: [.audio(id: itemID, source: input.id)])
        _ = try await owner.materializeAppCaptureSource(input, bytes: store.bytes)
        // Process death after original commit but before review acknowledgement.
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        try await cold.resumeAppCaptureRoot()
        let recovered = try await CaptureInitialDraftSession.reopen(pending, requireCurrent: {}, resolveOwner: { cold })
        #expect(recovered.sources.first?.input == input && recovered.sources.first?.ready == true)
        #expect(recovered.journal?.value.revision == pending.value.revision + 1)
        #expect(try await recovered.read(input) == store.bytes)
        #expect(try store.rows().count == 1)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func coldDiscoveryRestoresExactItemsAndLastRemovalClearsNotes() async throws {
        let store = try await Store(), owner = try await store.open()
        let input = CaptureDraftSourceBindingTests().source(store), itemID = UUID(), noteID = UUID()
        let items: [SharedMediaCaptureDraftJournal.Item] = [
            .description(id: noteID, text: "Synthetic retained note"), .audio(id: itemID, source: input.id)
        ]
        let pending = try await owner.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
            replacing: nil, sources: [.init(itemID: itemID, input: input, state: .pending)], items: items)
        _ = try await owner.materializeAppCaptureSource(input, bytes: store.bytes)
        let ready = try await owner.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
            replacing: pending, sources: [.init(itemID: itemID, input: input, state: .ready)], items: items)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        try await cold.resumeAppCaptureRoot()
        let page = try await cold.captureDraftJournalPage()
        #expect(page.drafts == [ready] && page.nextCursor == nil)
        let restored = try await CaptureInitialDraftSession.reopen(ready, requireCurrent: {}, resolveOwner: { cold })
        #expect(restored.identity.scanID == input.scanID && restored.identity.generation == input.submissionGeneration)
        #expect(restored.journal == ready && restored.sources.map(\.itemID) == [itemID])
        #expect(try await restored.read(input) == store.bytes)
        try await restored.discard(itemID: itemID)
        #expect(restored.sources.isEmpty && restored.journal?.value.items.isEmpty == true)
        #expect(restored.journal?.value.phase == .released)
        let terminalPage = try await cold.captureDraftJournalPage()
        #expect(terminalPage.drafts.isEmpty)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func staleDiscoveryCannotReopenOrReplaceAChangedDraft() async throws {
        let store = try await Store(), owner = try await store.open()
        let input = CaptureDraftSourceBindingTests().source(store), itemID = UUID()
        let sources: [SharedMediaCaptureDraftJournal.Source] = [.init(itemID: itemID, input: input, state: .pending)]
        let initial = try await owner.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
            replacing: nil, sources: sources, items: [.audio(id: itemID, source: input.id)])
        let changed = try await owner.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
            replacing: initial, sources: sources,
            items: [.audio(id: itemID, source: input.id), .description(id: UUID(), text: "Synthetic later edit")])
        await #expect(throws: (any Error).self) {
            _ = try await CaptureInitialDraftSession.reopen(initial, requireCurrent: {}, resolveOwner: { owner })
        }
        #expect(try await owner.readAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration) == changed)
        let restored = try await CaptureInitialDraftSession.reopen(changed, requireCurrent: {}, resolveOwner: { owner })
        #expect(restored.sources.count == 1 && restored.sources.first?.ready == false)
        await #expect(throws: (any Error).self) { _ = try await restored.read(input) }
        try await restored.discard(itemID: itemID)
        #expect(restored.journal?.value.phase == .released)
        #expect(try store.rows().isEmpty)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func optionalReviewPersistsOrderingAndNotesWithoutConfirmingItems() async throws {
        let store = try await Store(), owner = try await store.open()
        let session = CaptureInitialDraftSession(identity: .init(ownerID: store.base.ownerID,
            scanID: store.input.scanID, generation: store.input.submissionGeneration), requireCurrent: {}, resolveOwner: { owner })
        let firstID = UUID(), secondID = UUID(), noteID = UUID()
        let first = try await session.retain(itemID: firstID, bytes: store.bytes, role: .sourceAudio,
            contentType: "audio/wav", context: .init(origin: .microphone, cameraVerticalCenter: nil))
        let second = try await session.retain(itemID: secondID, bytes: store.bytes, role: .sourceAudio,
            contentType: "audio/wav", context: .init(origin: .microphone, cameraVerticalCenter: nil))
        let ordered: [SharedMediaCaptureDraftJournal.Item] = [.audio(id: secondID, source: second.id),
            .description(id: noteID, text: "Synthetic edited note"), .audio(id: firstID, source: first.id)]
        try await session.updateReview(items: ordered)
        let saved = try #require(session.journal)
        await #expect(throws: (any Error).self) { try await session.updateReview(items: Array(ordered.prefix(2))) }
        #expect(session.journal == saved)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        try await cold.resumeAppCaptureRoot()
        let restored = try await CaptureInitialDraftSession.reopen(saved, requireCurrent: {}, resolveOwner: { cold })
        #expect(restored.journal?.value.items == ordered)
        let plan = try await restored.prepare(items: [.audio(second), .description("Synthetic edited note"), .audio(first)])
        #expect(plan.uploads.map(\.artifact.mediaID) == [second.mediaID, first.mediaID])
        await #expect(throws: (any Error).self) { try await restored.updateReview(items: ordered) }
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }
}

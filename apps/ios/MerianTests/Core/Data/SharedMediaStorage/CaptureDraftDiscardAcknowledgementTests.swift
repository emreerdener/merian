import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Capture draft discard acknowledgement", .serialized)
@MainActor
struct CaptureDraftDiscardAcknowledgementTests {
    @Test(arguments: SharedMediaCaptureDraftJournalBoundary.allCases)
    func terminalSaveUncertaintyReplaysWithoutResurrection(_ fault: SharedMediaCaptureDraftJournalBoundary) async throws {
        let store = try await SharedMediaCaptureArtifactWriterTests.Store(), owner = try await store.open()
        let input = CaptureDraftSourceBindingTests().source(store), item = UUID()
        let items: [SharedMediaCaptureDraftJournal.Item] = [
            .audio(id: item, source: input.id), .description(id: UUID(), text: "Synthetic supplementary notes")
        ]
        let pending = try await owner.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
            replacing: nil, sources: [.init(itemID: item, input: input, state: .pending)], items: items)
        _ = try await owner.materializeAppCaptureSource(input, bytes: store.bytes)
        let intent = try await owner.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
            replacing: pending, sources: [.init(itemID: item, input: input, state: .discarding)], items: items, phase: .discarding)
        var reached = false
        try owner.configureCaptureDraftJournalForTesting { point in
            if point == fault { reached = true; throw SharedMediaStorageFailure.unavailable }
        }
        do {
            let reply = try await owner.discardAppCaptureDraftItem(itemID: item, expected: intent)
            #expect(fault == .afterSave && reply.value.phase == .released)
        } catch { #expect(fault != .afterSave) }
        #expect(reached)
        let read = ModelContext(store.container); read.autosaveEnabled = false
        let saved = try SharedMediaCaptureDraftJournalReceipt.matching(scanID: input.scanID,
            generation: input.submissionGeneration, context: read)
        #expect(saved?.value.phase == (fault == .beforeSave ? .discarding : .released))
        #expect(try store.rows().first?.phaseRaw == "released")
        try owner.configureCaptureDraftJournalForTesting(nil)
        let terminal = try await owner.discardAppCaptureDraftItem(itemID: item, expected: intent)
        #expect(terminal.value.phase == .released && terminal.value.items.isEmpty)
        #expect(terminal.value.revision == intent.value.revision + 1)
        #expect(try await owner.discardAppCaptureDraftItem(itemID: item, expected: intent) == terminal)
        await #expect(throws: (any Error).self) { _ = try await owner.materializeAppCaptureSource(input, bytes: store.bytes) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
}

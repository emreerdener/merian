import Foundation
@testable import Merian
import SwiftData
import Testing

@MainActor
@Suite("Capture durable draft composition", .serialized)
struct SharedMediaCaptureDraftJournalStoreTests {
    typealias Store = SharedMediaCaptureArtifactWriterTests.Store
    typealias Journal = SharedMediaCaptureDraftJournal

    @Test func pendingDraftColdReopensAndReadyCompositionSurvivesWithoutFileAdoption() async throws {
        let store = try await Store(), owner = try await store.open()
        let input = CaptureDraftSourceBindingTests().source(store), item = UUID(), note = UUID()
        let sources: [Journal.Source] = [.init(itemID: item, input: input, state: .pending)]
        let items: [Journal.Item] = [.description(id: note, text: "Synthetic ordered note"), .audio(id: item, source: input.id)]
        let pending = try await owner.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
            replacing: nil, sources: sources, items: items)
        #expect(pending.value.revision == 0 && owner.isReadyForCaptureDraft)
        #expect(try store.rows().isEmpty)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        try await cold.resumeAppCaptureRoot()
        #expect(cold.isReadyForCaptureDraft && !cold.isReadyForCaptureDispatch && !cold.isReadyForAppDispatch)
        #expect(try await cold.readAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration) == pending)
        _ = try await cold.materializeAppCaptureSource(input, bytes: store.bytes)
        // The original exists, but pending composition cannot claim ready reads.
        await #expect(throws: (any Error).self) { _ = try await cold.readAppCaptureSource(input) }
        let ready = try await cold.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
            replacing: pending, sources: [.init(itemID: item, input: input, state: .ready)], items: items)
        #expect(ready.value.revision == 1 && ready.value.items == items)
        #expect(try await cold.readAppCaptureSource(input) == store.bytes)
        await #expect(throws: (any Error).self) {
            _ = try await cold.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
                replacing: pending, sources: sources, items: [.audio(id: item, source: input.id)])
        }
        // Discard needs the durable intent before it can erase an original.
        await #expect(throws: (any Error).self) { try await cold.discardAppCaptureSource(input) }
        let discarding = try await cold.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
            replacing: ready, sources: [.init(itemID: item, input: input, state: .discarding)], items: items, phase: .discarding)
        await #expect(throws: (any Error).self) { _ = try await cold.materializeAppCaptureSource(input, bytes: store.bytes) }
        try await cold.discardAppCaptureSource(input)
        let released = try await cold.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
            replacing: discarding, sources: [.init(itemID: item, input: input, state: .released)], items: [], phase: .released)
        #expect(released.value.phase == .released)
        #expect(try store.rows().first?.phaseRaw == "released")
        await #expect(throws: (any Error).self) {
            _ = try await cold.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
                replacing: released, sources: sources, items: items)
        }
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: SharedMediaCaptureDraftJournalBoundary.allCases)
    func uncertainSaveReplaysExactIdentityWithoutAnotherRevision(_ fault: SharedMediaCaptureDraftJournalBoundary) async throws {
        let store = try await Store(), owner = try await store.open()
        let input = CaptureDraftSourceBindingTests().source(store), item = UUID()
        let sources: [Journal.Source] = [.init(itemID: item, input: input, state: .pending)]
        let items: [Journal.Item] = [.audio(id: item, source: input.id)]
        var reached = false
        try owner.configureCaptureDraftJournalForTesting { point in
            if point == fault { reached = true; throw SharedMediaStorageFailure.unavailable }
        }
        do {
            _ = try await owner.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
                replacing: nil, sources: sources, items: items)
            #expect(fault == .afterSave)
        } catch { #expect(fault != .afterSave) }
        #expect(reached)
        try owner.configureCaptureDraftJournalForTesting(nil)
        let saved = try await owner.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
            replacing: nil, sources: sources, items: items)
        #expect(saved.value.revision == 0)
        let read = ModelContext(store.container); read.autosaveEnabled = false
        #expect(try read.fetchCount(FetchDescriptor<SharedMediaCaptureDraftJournalRecord>()) == 1)
        #expect(try store.rows().isEmpty)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func readyAndReleasedStatesRequireOriginalCustodyProof() async throws {
        let store = try await Store(), owner = try await store.open()
        let input = CaptureDraftSourceBindingTests().source(store), item = UUID()
        let sources: [Journal.Source] = [.init(itemID: item, input: input, state: .pending)]
        let items: [Journal.Item] = [.audio(id: item, source: input.id)]
        let pending = try await owner.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
            replacing: nil, sources: sources, items: items)
        await #expect(throws: (any Error).self) {
            _ = try await owner.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
                replacing: pending, sources: [.init(itemID: item, input: input, state: .ready)], items: items)
        }
        _ = try await owner.materializeAppCaptureSource(input, bytes: store.bytes)
        let discarding = try await owner.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
            replacing: pending, sources: [.init(itemID: item, input: input, state: .discarding)], items: items, phase: .discarding)
        await #expect(throws: (any Error).self) {
            _ = try await owner.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
                replacing: discarding, sources: [.init(itemID: item, input: input, state: .released)], items: [], phase: .released)
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
}

extension SharedMediaCaptureDraftJournalStoreTests {
    @Test(arguments: ["owner", "root", "revision", "body", "inventory"])
    func corruptJournalCannotDisappearFromReverseAudit(_ mutation: String) async throws {
        let store = try await Store(), owner = try await store.open()
        let input = CaptureDraftSourceBindingTests().source(store), item = UUID()
        _ = try await owner.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
            replacing: nil, sources: [.init(itemID: item, input: input, state: .pending)], items: [.audio(id: item, source: input.id)])
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let context = ModelContext(store.container); context.autosaveEnabled = false
        let rows = try context.fetch(FetchDescriptor<SharedMediaCaptureDraftJournalRecord>())
        let row = try #require(rows.first)
        switch mutation {
        case "owner": row.ownerID = UUID()
        case "root": row.rootBindingSHA256 = String(repeating: "0", count: 64)
        case "revision": row.revision += 1
        case "body": row.bodyData = Data("{}".utf8)
        case "inventory": row.inventoryID = UUID()
        default: Issue.record("Unknown mutation")
        }
        try context.save()
        let cold = try await store.open()
        await #expect(throws: (any Error).self) { try await cold.resumeAppCaptureRoot() }
        #expect(!cold.isReadyForCaptureDispatch && !cold.isReadyForAppDispatch)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }
}

extension SharedMediaCaptureDraftJournalStoreTests {
    @Test func neverReservedSourceCannotInventReleaseReceipt() async throws {
        let store = try await Store(), owner = try await store.open()
        let input = CaptureDraftSourceBindingTests().source(store), item = UUID()
        let items: [Journal.Item] = [.audio(id: item, source: input.id)]
        let pending = try await owner.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
            replacing: nil, sources: [.init(itemID: item, input: input, state: .pending)], items: items)
        let discarding = try await owner.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
            replacing: pending, sources: [.init(itemID: item, input: input, state: .discarding)], items: items, phase: .discarding)
        await #expect(throws: (any Error).self) {
            _ = try await owner.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
                replacing: discarding, sources: [.init(itemID: item, input: input, state: .released)], items: [], phase: .released)
        }
        await #expect(throws: (any Error).self) {
            _ = try await owner.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
                replacing: discarding, sources: [.init(itemID: item, input: input, state: .releasedWithoutReservationV1)], items: [], phase: .released)
        }
        let released = try await owner.discardAppCaptureDraftItem(itemID: item, expected: discarding)
        #expect(released.value.sources.first?.state == .releasedWithoutReservationV1)
        #expect(released.value.phase == .released && released.value.items.isEmpty)
        #expect(try await owner.discardAppCaptureDraftItem(itemID: item, expected: discarding) == released)
        await #expect(throws: (any Error).self) { _ = try await owner.materializeAppCaptureSource(input, bytes: store.bytes) }
        #expect(try store.rows().isEmpty)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func frozenJournalWithoutSubmissionParentCannotQualify() async throws {
        let store = try await Store(), owner = try await store.open(), fixture = CaptureDraftSourceBindingTests()
        let input = fixture.source(store), item = UUID()
        let items: [Journal.Item] = [.audio(id: item, source: input.id)]
        let pending = try await owner.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
            replacing: nil, sources: [.init(itemID: item, input: input, state: .pending)], items: items)
        _ = try await owner.materializeAppCaptureSource(input, bytes: store.bytes)
        let ready = try await owner.saveAppCaptureDraftJournal(scanID: input.scanID, generation: input.submissionGeneration,
            replacing: pending, sources: [.init(itemID: item, input: input, state: .ready)], items: items)
        let plan = try fixture.plan(store, sources: [input]), value = ready.value
        let forged = Journal(format: .v1, profile: value.profile, rootBindingSHA256: value.rootBindingSHA256,
            scanID: value.scanID, generation: value.generation, revision: 2, phase: .submitting,
            sources: value.sources, items: value.items, frozenObservation: .init(bytes: try plan.encoded()),
            frozenContext: try SharedMediaCaptureSubmissionContextTests.context(plan))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let context = ModelContext(store.container); context.autosaveEnabled = false
        let rows = try context.fetch(FetchDescriptor<SharedMediaCaptureDraftJournalRecord>())
        let row = try #require(rows.first), bytes = try forged.encoded()
        row.bodyData = bytes; row.bodySHA256 = SharedMediaAcquisitionEncoding.digest(bytes); row.revision = 2
        try context.save()
        let cold = try await store.open()
        await #expect(throws: (any Error).self) { try await cold.resumeAppCaptureRoot() }
        #expect(!cold.isReadyForCaptureDispatch)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }
}

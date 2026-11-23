import Foundation
@testable import Merian
import SwiftData
import Testing

@Suite("Capture source discard recovery", .serialized)
@MainActor
struct CaptureSourceDiscardTests {
    typealias Store = SharedMediaCaptureArtifactWriterTests.Store

    @Test(arguments: SharedMediaCaptureSourceDiscardBoundary.allCases)
    func interruptedDiscardNeverResurrectsSource(_ boundary: SharedMediaCaptureSourceDiscardBoundary) async throws {
        let store = try await Store(), owner = try await store.open()
        let source = CaptureDraftSourceBindingTests().source(store)
        _ = try await owner.materializeAppCaptureSource(source, bytes: store.bytes)
        var reached = false
        try owner.configureCaptureSourceDiscardForTesting { point in
            if point == boundary { reached = true; throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { try await owner.discardAppCaptureSource(source) }
        #expect(reached)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        if boundary != .beforeIntentSave {
            let page = try await cold.captureDraftSourcePage()
            #expect(page.sources.isEmpty)
            #expect(page.retirements == (boundary == .afterReleaseSave ? [] : [source]))
            await #expect(throws: (any Error).self) { _ = try await cold.readAppCaptureSource(source) }
            await #expect(throws: (any Error).self) { _ = try await cold.materializeAppCaptureSource(source, bytes: store.bytes) }
        }
        try await cold.discardAppCaptureSource(source)
        try await cold.discardAppCaptureSource(source)
        let row = try #require(try store.rows().first)
        let receipt = try SharedMediaCaptureArtifactLedger.auditReceipt(row)
        #expect(receipt.retirement?.releasedRevision != nil)
        #expect(!FileManager.default.fileExists(atPath: store.directory.appendingPathComponent(receipt.request.finalName).path))
        #expect(try await cold.captureDraftSourcePage().sources.isEmpty)
        await #expect(throws: (any Error).self) { _ = try await cold.materializeAppCaptureSource(source, bytes: store.bytes) }
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaCaptureArtifactWriteBoundary.afterReservationSave, .afterPartialCreation,
                      .afterPartialSave, .afterBytes, .afterRename])
    func incompleteSourcesCanOnlyDiscardTheirOwnFiles(_ boundary: SharedMediaCaptureArtifactWriteBoundary) async throws {
        let store = try await Store(), owner = try await store.open()
        let source = CaptureDraftSourceBindingTests().source(store)
        try owner.configureCaptureArtifactWritingForTesting { point in
            if point == boundary { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { _ = try await owner.materializeAppCaptureSource(source, bytes: store.bytes) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        try await cold.discardAppCaptureSource(source)
        #expect(try store.rows().first?.phaseRaw == "released")
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path).isEmpty)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func discardAndFinalBindingHavePermanentMutuallyExclusiveOutcomes() async throws {
        let store = try await Store(), owner = try await store.open(), fixture = CaptureDraftSourceBindingTests()
        let removed = fixture.source(store), retained = fixture.source(store, ordinal: 1)
        _ = try await owner.materializeAppCaptureSource(removed, bytes: store.bytes)
        _ = try await owner.materializeAppCaptureSource(retained, bytes: store.bytes)
        try await owner.discardAppCaptureSource(removed)
        let invalid = try fixture.plan(store, sources: [removed, retained])
        await #expect(throws: (any Error).self) {
            _ = try await owner.acceptAppCaptureDraft(plan: invalid, context: SharedMediaCaptureSubmissionContextTests.context(invalid)) { _ in store.bytes }
        }
        let valid = try fixture.plan(store, sources: [retained])
        _ = try await owner.acceptAppCaptureDraft(plan: valid, context: SharedMediaCaptureSubmissionContextTests.context(valid)) { _ in
            Issue.record("Already held original must not be reread")
            throw SharedMediaStorageFailure.conflict
        }
        await #expect(throws: (any Error).self) { try await owner.discardAppCaptureSource(retained) }
        #expect(try await owner.readAppCaptureSource(retained) == store.bytes)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await store.open()
        try await cold.resumeAppCaptureRoot()
        #expect(cold.isReadyForCaptureDispatch)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func discardWaitsForCancellationIgnoringWriterToExit() async throws {
        let store = try await Store(byteCount: 131_072), owner = try await store.open(), gate = Gate()
        let source = CaptureDraftSourceBindingTests().source(store)
        try owner.configureCaptureArtifactWritingForTesting(pause: { _ in await gate.pause() })
        let write = Task { @MainActor in
            do {
                _ = try await owner.materializeAppCaptureSource(source, bytes: store.bytes)
                await gate.finish()
            } catch { await gate.finish(); throw error }
        }
        guard await gate.entered() else { try await write.value; Issue.record("Writer did not pause"); return }
        var requested = false, discarded = false
        let discard = Task { @MainActor in
            requested = true
            try await owner.discardAppCaptureSource(source)
            discarded = true
        }
        while !requested { await Task.yield() }
        write.cancel()
        await Task.yield()
        #expect(!discarded)
        #expect(try store.rows().first?.phaseRaw == "writing")
        await gate.release()
        await #expect(throws: (any Error).self) { try await write.value }
        try await discard.value
        let row = try #require(try store.rows().first)
        let receipt = try SharedMediaCaptureArtifactLedger.auditReceipt(row)
        #expect(receipt.retirement?.releasedRevision != nil && receipt.metadataBytes > 0)
        let context = ModelContext(store.container); context.autosaveEnabled = false
        let allocations = try context.fetch(FetchDescriptor<SharedMediaAllocationRecord>())
        let allocation = try #require(allocations.first { $0.id == receipt.request.allocationID })
        #expect(allocation.materializedBytes == 0 && allocation.reservedBytes == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path).isEmpty)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private actor Gate {
        var arrived = false, finished = false, released = false
        var arrival: CheckedContinuation<Bool, Never>?, waiting: CheckedContinuation<Void, Never>?
        func pause() async {
            guard !released else { return }
            arrived = true; arrival?.resume(returning: true); arrival = nil
            await withCheckedContinuation { waiting = $0 }
        }
        func entered() async -> Bool {
            if arrived { return true }; if finished { return false }
            return await withCheckedContinuation { arrival = $0 }
        }
        func finish() { finished = true; arrival?.resume(returning: arrived); arrival = nil }
        func release() { released = true; waiting?.resume(); waiting = nil }
    }

    @Test func failureBeforeReservationCanDiscardOnlyAfterRootAbsenceProof() async throws {
        let store = try await Store(), owner = try await store.open()
        let source = CaptureDraftSourceBindingTests().source(store)
        try owner.configureCaptureArtifactWritingForTesting { point in
            if point == .beforeReservationSave { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { _ = try await owner.materializeAppCaptureSource(source, bytes: store.bytes) }
        try await owner.discardAppCaptureSource(source)
        #expect(try store.rows().isEmpty)
        try store.bytes.write(to: store.directory.appendingPathComponent(source.id.uuidString.lowercased()))
        await #expect(throws: (any Error).self) { try await owner.discardAppCaptureSource(source) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func replacedFileCannotUseSavedRetirementIntent() async throws {
        let store = try await Store(), owner = try await store.open()
        let source = CaptureDraftSourceBindingTests().source(store)
        let original = try await owner.materializeAppCaptureSource(source, bytes: store.bytes)
        try owner.configureCaptureSourceDiscardForTesting { point in
            if point == .afterIntentSave { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { try await owner.discardAppCaptureSource(source) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let url = store.directory.appendingPathComponent(original.request.finalName)
        let replacement = store.directory.appendingPathComponent("replacement")
        try store.bytes.write(to: replacement)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: replacement, to: url)
        let cold = try await store.open()
        await #expect(throws: (any Error).self) { try await cold.discardAppCaptureSource(source) }
        #expect(try Data(contentsOf: url) == store.bytes)
        #expect(try store.rows().first?.phaseRaw == "retiring")
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }
}

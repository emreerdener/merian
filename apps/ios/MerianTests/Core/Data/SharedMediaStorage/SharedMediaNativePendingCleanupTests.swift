import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native explicit pending abandonment", .serialized)
@MainActor
struct SharedMediaNativePendingCleanupTests {
    @Test(arguments: ["absent", "zero", "partial", "final"], [true, false])
    func rawColdRecoveryPreservesFilesAndReservation(_ kind: String, _ reserved: Bool) async throws {
        let h = try NativePendingCleanupHarness(), owner = try await h.open()
        let request = try await h.held(owner)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        try h.seedFile(request, kind: kind)
        if reserved { try h.makeReserved(request) }
        let reopened = try await h.open(), before = try h.receipt(request).requestData
        try await reopened.recoverPendingAbandonments()
        #expect(try await reopened.snapshot().requiresRecovery)
        #expect(try h.work(request).terminalProof == nil)
        #expect(try h.receipt(request).requestData == before)
        #expect(try h.allocation(request).reservedBytes == request.maximumBytes)
        if kind != "absent" { #expect(try Data(contentsOf: h.file(request, partial: kind != "final")) == (kind == "zero" ? Data() : h.bytes)) }
        try await reopened.abandonPendingAcquisition(request)
        #expect(try h.rows(SharedMediaAllocationRecord.self) == 0)
        #expect(try h.receipt(request).phaseRaw == "terminal")
        #expect(try h.package().phaseRaw == "draftOwned")
        #expect(!FileManager.default.fileExists(atPath: h.file(request).path))
        #expect(!FileManager.default.fileExists(atPath: h.file(request, partial: true).path))
        await #expect(throws: (any Error).self) { try await reopened.acquireOriginal(request) { Issue.record("Terminal request replayed loader"); return Data() } }
        #expect(await reopened.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaPhotoReleaseBoundary.beforeUnlink, .afterUnlink, .beforeSync, .afterSync])
    func interruptedDisposalKeepsProofAndChargeAcrossEpochs(_ point: SharedMediaPhotoReleaseBoundary) async throws {
        let h = try NativePendingCleanupHarness(), owner = try await h.open(), request = try await h.held(owner, final: true)
        try await owner.setReleaseFault { if $0 == point { throw NativePendingCleanupFault.injected } }
        await #expect(throws: NativePendingCleanupFault.self) { try await owner.abandonPendingAcquisition(request) }
        let proof = try #require(h.work(request).terminalProof)
        #expect(try h.allocation(request).reservedBytes == request.maximumBytes)
        #expect(try h.receipt(request).phaseRaw == "held")
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let reopened = try await h.open()
        #expect(try h.work(request).terminalProof == proof)
        try await reopened.recoverPendingAbandonments()
        #expect(try h.rows(SharedMediaAllocationRecord.self) == 0)
        #expect(try h.package().phaseRaw == "draftOwned")
        #expect(!(try await reopened.snapshot().requiresRecovery))
        #expect(await reopened.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaNativeLifecycleBoundary.beforeSave, .afterSave, .beforeReleaseSave, .afterReleaseSave])
    func saveFailuresUseExactIntentOrRelease(_ point: SharedMediaNativeLifecycleBoundary) async throws {
        let h = try NativePendingCleanupHarness(), owner = try await h.open(), request = try await h.held(owner)
        try owner.setLifecycleFault { if $0 == point { throw NativePendingCleanupFault.injected } }
        if point == .beforeSave || point == .beforeReleaseSave {
            await #expect(throws: NativePendingCleanupFault.self) { try await owner.abandonPendingAcquisition(request) }
            #expect(try h.allocation(request).reservedBytes == request.maximumBytes)
            #expect((try h.work(request).terminalProof == nil) == (point == .beforeSave))
        } else { try await owner.abandonPendingAcquisition(request) }
        try owner.setLifecycleFault(nil)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let reopened = try await h.open()
        if point == .beforeSave {
            try await reopened.recoverPendingAbandonments()
            #expect(try h.work(request).terminalProof == nil)
            try await reopened.abandonPendingAcquisition(request)
        } else { try await reopened.recoverPendingAbandonments() }
        #expect(try h.receipt(request).phaseRaw == "terminal")
        #expect(await reopened.invalidateAndAwaitForAccountTransition())
    }

    @Test func cancellationAfterUnlinkKeepsDurableAuthority() async throws {
        let h = try NativePendingCleanupHarness(), owner = try await h.open(), request = try await h.held(owner, final: true)
        try await owner.setReleaseFault { if $0 == .afterUnlink { withUnsafeCurrentTask { $0?.cancel() } } }
        let task = Task { try await owner.abandonPendingAcquisition(request) }
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(try h.work(request).terminalProof != nil)
        #expect(try h.allocation(request).reservedBytes == request.maximumBytes)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let reopened = try await h.open(); try await reopened.recoverPendingAbandonments()
        #expect(try h.rows(SharedMediaAllocationRecord.self) == 0)
        #expect(await reopened.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["replace", "symlink", "hardlink", "both", "parent"])
    func changedSavedObjectsNeverGainFreshCleanupAuthority(_ kind: String) async throws {
        let h = try NativePendingCleanupHarness(), owner = try await h.open(), request = try await h.held(owner, final: true)
        try owner.setLifecycleFault { if $0 == .beforeReleaseSave { throw NativePendingCleanupFault.injected } }
        // Stop before unlink so the immutable proof describes the original object.
        try await owner.setReleaseFault { if $0 == .beforeUnlink { throw NativePendingCleanupFault.injected } }
        await #expect(throws: (any Error).self) { try await owner.abandonPendingAcquisition(request) }
        let proof = try h.work(request).terminalProof, file = h.file(request)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        switch kind {
        case "replace": try h.bytes.write(to: file, options: .atomic)
        case "symlink":
            let saved = file.appendingPathExtension("saved"); try FileManager.default.moveItem(at: file, to: saved)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: saved)
        case "hardlink": try FileManager.default.linkItem(at: file, to: file.appendingPathExtension("extra"))
        case "both": try h.bytes.write(to: h.file(request, partial: true))
        default:
            let parent = file.deletingLastPathComponent(), moved = parent.appendingPathExtension("saved")
            try FileManager.default.moveItem(at: parent, to: moved)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        await #expect(throws: (any Error).self) { _ = try await h.open() }
        #expect(try h.work(request).terminalProof == proof)
        #expect(try h.allocation(request).reservedBytes == request.maximumBytes)
    }

    @Test(arguments: ["work", "lease", "allocation", "proof"])
    func partialCleanupTuplesAreRejected(_ field: String) async throws {
        let h = try NativePendingCleanupHarness(), owner = try await h.open(), request = try await h.held(owner)
        try owner.setLifecycleFault { if $0 == .beforeReleaseSave { throw NativePendingCleanupFault.injected } }
        await #expect(throws: (any Error).self) { try await owner.abandonPendingAcquisition(request) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        try h.corrupt(request, field: field)
        await #expect(throws: (any Error).self) { _ = try await h.open() }
        #expect(try h.allocation(request).reservedBytes == request.maximumBytes)
    }

    @Test(arguments: [true, false])
    func oneAbandonmentPreservesOtherPendingWorkAndDerivedPhase(_ held: Bool) async throws {
        let h = try NativePendingCleanupHarness(), owner = try await h.open(), first = try await h.held(owner)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let second = try h.seedSecond(first, held: held), reopened = try await h.open()
        try await reopened.abandonPendingAcquisition(first)
        #expect(try h.receipt(first).phaseRaw == "terminal")
        #expect(try h.allocation(second).reservedBytes == second.maximumBytes)
        #expect(try h.package().phaseRaw == (held ? "needsAttention" : "acquiring"))
        #expect(try await reopened.snapshot().requiresRecovery)
        try await reopened.abandonPendingAcquisition(second)
        #expect(try h.package().phaseRaw == "draftOwned")
        #expect(!(try await reopened.snapshot().requiresRecovery))
        try h.audit()
        #expect(await reopened.invalidateAndAwaitForAccountTransition())
    }

    @Test func recoveryDrainsOnlySavedIntentsOneAtATime() async throws {
        let h = try NativePendingCleanupHarness(), owner = try await h.open(), first = try await h.held(owner)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let second = try h.seedSecond(first, held: true), reopened = try await h.open()
        try reopened.setLifecycleFault { if $0 == .beforeReleaseSave { throw NativePendingCleanupFault.injected } }
        await #expect(throws: (any Error).self) { try await reopened.abandonPendingAcquisition(first) }
        await #expect(throws: (any Error).self) { try await reopened.abandonPendingAcquisition(second) }
        #expect(try h.work(first).terminalProof != nil && h.work(second).terminalProof != nil)
        #expect(await reopened.invalidateAndAwaitForAccountTransition())
        let final = try await h.open(); try await final.recoverPendingAbandonments()
        #expect(try h.rows(SharedMediaAllocationRecord.self) == 0)
        #expect(try h.rows(PhotoPreparationRecord.self) == 1)
        #expect(await final.invalidateAndAwaitForAccountTransition())
    }

    @Test func activeLoaderRetainsFencesAndCannotBeAbandoned() async throws {
        let h = try NativePendingCleanupHarness(), owner = try await h.open(), request = try await h.request(owner), gate = NativePendingLoaderGate()
        let task = Task { () throws -> SharedMediaAcquisitionResult in
            do { let result = try await owner.acquireOriginal(request) { await gate.enter(); return Data() }; await gate.finish(); return result }
            catch { await gate.finish(); throw error }
        }
        for _ in 0..<1000 {
            let status = await gate.status(); if status.0 || status.1 { break }; try await Task.sleep(for: .milliseconds(10))
        }
        let status = await gate.status()
        guard status.0 else { task.cancel(); await gate.release(); _ = await task.result; _ = await owner.invalidateAndAwaitForAccountTransition(); Issue.record("Loader failed before test gate"); return }
        await #expect(throws: (any Error).self) { try await owner.abandonPendingAcquisition(request) }
        await #expect(throws: (any Error).self) { _ = try await h.open() }
        #expect(try h.work(request).terminalProof == nil)
        task.cancel(); await gate.release(); _ = await task.result
        // The cancelled task cannot complete the paged graph audit required by
        // held settlement. Keep admission closed until uncancelled drain settles
        // the receipt and actually releases the file fences.
        await #expect(throws: SharedMediaStorageFailure.closed) { try await owner.abandonPendingAcquisition(request) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        #expect(try h.receipt(request).phaseRaw == "held")
        let reopened = try await h.open()
        try await reopened.abandonPendingAcquisition(request)
        #expect(await reopened.invalidateAndAwaitForAccountTransition())
    }

    @Test func exactMetadataCeilingPreservesOtherOriginalAndDraftOnAbandonment() async throws {
        let h = try NativePendingCleanupHarness(), owner = try await h.open(), first = try await h.request(owner)
        let bytes = h.bytes
        _ = try await owner.acquireOriginal(first) { bytes }
        let pending = try await h.held(owner, ordinal: 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let envelope = try h.fillMetadata(referenceID: first.referenceID)
        #expect(try h.metadataCharge() == PhotoPreparationPolicy.metadata)
        let reopened = try await h.open()
        try reopened.setLifecycleFault { if $0 == .beforeReleaseSave { throw NativePendingCleanupFault.injected } }
        await #expect(throws: NativePendingCleanupFault.self) { try await reopened.abandonPendingAcquisition(pending) }
        #expect(try h.metadataCharge() == PhotoPreparationPolicy.metadata)
        #expect(try h.work(pending).terminalProof != nil)
        #expect(try h.package().supportingContextData == envelope)
        #expect(try Data(contentsOf: h.file(first)) == bytes)
        #expect(await reopened.invalidateAndAwaitForAccountTransition())
        let final = try await h.open(); try await final.recoverPendingAbandonments()
        #expect(try h.rows(PhotoPreparationAsset.self) == 1)
        #expect(try h.rows(SharedMediaAllocationRecord.self) == 1)
        #expect(try h.package().supportingContextData == envelope)
        #expect(try h.package().allocatedByteCount == Int64(bytes.count))
        #expect(try Data(contentsOf: h.file(first)) == bytes)
        #expect(!(try await final.snapshot().requiresRecovery))
        #expect(await final.invalidateAndAwaitForAccountTransition())
    }

    @Test func changedRequestCannotAuthorizeAbandonment() async throws {
        let h = try NativePendingCleanupHarness(), owner = try await h.open(), request = try await h.held(owner)
        var object = try #require(JSONSerialization.jsonObject(with: request.encoded()) as? [String: Any])
        object["writerEpoch"] = UUID().uuidString
        let changed = try JSONDecoder().decode(SharedMediaAcquisitionIntent.self, from: JSONSerialization.data(withJSONObject: object))
        await #expect(throws: (any Error).self) { try await owner.abandonPendingAcquisition(changed) }
        #expect(try h.work(request).terminalProof == nil)
        #expect(try h.allocation(request).reservedBytes == request.maximumBytes)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [SharedMediaNativeLifecycleBoundary.afterSave, .afterReleaseSave])
    func laterValidMutationCannotMasqueradeAsExactAcknowledgement(_ boundary: SharedMediaNativeLifecycleBoundary) async throws {
        let h = try NativePendingCleanupHarness(), owner = try await h.open(), request = try await h.held(owner)
        try owner.setLifecycleFault { if $0 == boundary { try h.advancePackage(); throw NativePendingCleanupFault.injected } }
        await #expect(throws: NativePendingCleanupFault.self) { try await owner.abandonPendingAcquisition(request) }
        if boundary == .afterSave { #expect(try h.work(request).terminalProof != nil) }
        else { #expect(try h.receipt(request).phaseRaw == "terminal") }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let reopened = try await h.open(); try await reopened.recoverPendingAbandonments()
        #expect(try h.receipt(request).phaseRaw == "terminal")
        #expect(await reopened.invalidateAndAwaitForAccountTransition())
    }

    @Test func strictCodecFitsWorstNumericShapeAndRejectsWrongRequest() async throws {
        let h = try NativePendingCleanupHarness(), owner = try await h.open(), request = try await h.request(owner)
        let directory = "9223372036854775807:18446744073709551615"
        let descriptor = "9223372036854775807:18446744073709551615:\(request.maximumBytes):-9223372036854775808:999999999:-9223372036854775808:999999999"
        let proof = SharedMediaNativePendingClosure(version: 1, fingerprint: try request.fingerprint(), parent: directory,
            namespace: directory, kind: .partial, file: descriptor)
        let encoded = try proof.encoded(request: request)
        #expect(encoded.utf8.count <= 512)
        #expect(try SharedMediaNativePendingClosure.decode(encoded, request: request) == proof)
        #expect(throws: (any Error).self) { try SharedMediaNativePendingClosure.decode(encoded + " ", request: request) }
        let wrong = try await h.request(owner)
        #expect(throws: (any Error).self) { try SharedMediaNativePendingClosure.decode(encoded, request: wrong) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
}

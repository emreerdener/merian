import Foundation
import os
import SwiftData
import Testing
@testable import Merian

@Suite("Inactive held physical original removal", .serialized)
@MainActor
struct SharedMediaNativeOriginalRemovalOwnerTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Rows = SharedMediaNativeAppOriginalRows
    let prior = SharedMediaNativeOriginalDispositionOwnerTests()

    @Test(arguments: [1, 2])
    func removesFirstOriginalAndRecoversExactTerminalReceipt(_ count: Int) async throws {
        let (h, owner, before) = try await fixture(count: count)
        let target = before.plan.targets[0], original = try prior.accounting(h, target.original.assetID)
        let old = try prior.prior.snapshot(h), file = path(h, original.fileToken)
        let rows = try Rows(h.context(), profile: before.plan.profile, source: target.original)
        let fingerprint = rows.receipt.requestFingerprint
        var saves = 0
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        let after = try await owner.removeAppReleaseOriginal(before)
        #expect(after.targets.first?.stage == .removed && after.targets.first?.original == before.targets.first?.original)
        #expect(after.targets.dropFirst() == before.targets.dropFirst() && after.plan == before.plan)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        let saved = try prior.prior.snapshot(h)
        #expect(saved.release.state.package.allocated == old.release.state.package.allocated - original.byteCount)
        #expect(saved.release.state.package.envelope == old.release.state.package.envelope)
        let c = h.context(), id = target.acquisitionID, assetID = target.original.assetID
        let receipt = try Rows.one(c, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }))
        guard case .released(let terminal) = try SharedMediaAcquisitionReceipt.read(receipt) else { Issue.record("Missing terminal receipt"); return }
        #expect(terminal.requestFingerprint == fingerprint && receipt.revision == 2)
        #expect(receipt.requestData == nil && receipt.resultData == nil && receipt.assetID == nil && receipt.packageID == nil)
        #expect(try c.fetchCount(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID })) == 0)
        #expect(try SharedMediaNativeOriginalLiability.read(context: c, inventoryID: h.inventoryID).entries[assetID] == nil)
        #expect(try await owner.removeAppReleaseOriginal(before) == after && saves == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        #expect(try await cold.removeAppReleaseOriginal(before) == after)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["beforeSave", "afterSave", "beforeReadback"])
    func uncertainMetadataNeverRepeatsPhysicalOrSaveWork(_ fault: String) async throws {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let (h, owner, before) = try await fixture(fault: { if $0 == .beforeUnlink { calls.withLock { $0 += 1 } } })
        var saves = 0
        try owner.setMetadataFault {
            if $0 == .beforeSave { saves += 1 }
            if (fault == "beforeSave" && $0 == .beforeSave) || (fault == "afterSave" && $0 == .afterSave) ||
                (fault == "beforeReadback" && $0 == .beforeReadback) { throw SharedMediaStorageFailure.unavailable }
        }
        if fault == "afterSave" { _ = try await owner.removeAppReleaseOriginal(before) }
        else { await #expect(throws: (any Error).self) { _ = try await owner.removeAppReleaseOriginal(before) } }
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        if fault == "beforeSave" {
            await #expect(throws: (any Error).self) { _ = try await owner.removeAppReleaseOriginal(before) }
            #expect(try prior.prior.snapshot(h).release.progress == before)
        } else { #expect(try await owner.removeAppReleaseOriginal(before) == prior.prior.snapshot(h).release.progress) }
        #expect(saves == 1 && calls.withLock { $0 } == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        _ = try await cold.removeAppReleaseOriginal(before)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["missing", "beforeUnlink", "afterUnlink", "beforeSync", "afterSync"])
    func absenceAndInterruptedUnlinkKeepTheSameRetirement(_ fault: String) async throws {
        let (h, owner, before) = try await fixture(fault: { point in
            if (fault == "beforeUnlink" && point == .beforeUnlink) || (fault == "afterUnlink" && point == .afterUnlink) ||
                (fault == "beforeSync" && point == .beforeSync) || (fault == "afterSync" && point == .afterSync) {
                throw SharedMediaStorageFailure.unavailable
            }
        })
        let original = try prior.accounting(h, before.plan.targets[0].original.assetID)
        if fault == "missing" {
            try FileManager.default.removeItem(at: path(h, original.fileToken))
            _ = try await owner.removeAppReleaseOriginal(before)
        } else {
            await #expect(throws: (any Error).self) { _ = try await owner.removeAppReleaseOriginal(before) }
            #expect(try prior.accounting(h, original.assetID) == original)
            #expect(try prior.prior.snapshot(h).release.progress == before)
            await #expect(throws: (any Error).self) { _ = try await owner.removeAppReleaseOriginal(before) }
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        let after = try await cold.removeAppReleaseOriginal(before)
        #expect(after.targets[0].original == before.targets[0].original)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func lateReappearanceKeepsChargesAndBlocksClosure() async throws {
        let (h, owner, before) = try await fixture()
        let original = try prior.accounting(h, before.plan.targets[0].original.assetID), file = path(h, original.fileToken)
        let bytes = try Data(contentsOf: file), old = try prior.prior.snapshot(h)
        try owner.setMetadataFault { if $0 == .beforeSave { try bytes.write(to: file) } }
        await #expect(throws: (any Error).self) { _ = try await owner.removeAppReleaseOriginal(before) }
        #expect(try prior.prior.snapshot(h).release.state.package.allocated == old.release.state.package.allocated)
        #expect(try prior.prior.snapshot(h).release.progress == before)
        #expect(!(await owner.invalidateAndAwaitForAccountTransition()))
        try FileManager.default.removeItem(at: file)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        _ = try await cold.removeAppReleaseOriginal(before)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [false, true])
    func inspectionAbsenceSurvivesVerificationFailure(_ initiallyPresent: Bool) async throws {
        let (h, owner, before) = try await fixture()
        let original = try prior.accounting(h, before.plan.targets[0].original.assetID)
        let file = path(h, original.fileToken), bytes = try Data(contentsOf: file)
        if !initiallyPresent { try FileManager.default.removeItem(at: file) }
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal()
        let ended = ImageFocusEngineTests.Signal()
        try await owner.setAcquisitionEntryPause { point in
            guard point == .inspectOriginal else { return }
            await entered.open(); await release.wait()
        }
        let operation = Task {
            do { let value = try await owner.removeAppReleaseOriginal(before); await ended.open(); await entered.open(); return value }
            catch { await ended.open(); await entered.open(); throw error }
        }
        await entered.wait()
        let didPause = !(await ended.isOpen)
        #expect(didPause)
        if didPause {
            if initiallyPresent { try FileManager.default.removeItem(at: file) }
            else { try bytes.write(to: file) }
        }
        await release.open()
        await #expect(throws: (any Error).self) { _ = try await operation.value }
        #expect(owner.observedHeldOriginalAbsenceForTesting)
        #expect(try prior.accounting(h, original.assetID) == original)
        #expect(try prior.prior.snapshot(h).release.progress == before)
        // Reappearance cannot erase absence from either the first inspection or
        // the synchronous verification that discovered a changed presence.
        if initiallyPresent { try bytes.write(to: file) }
        #expect(!(await owner.invalidateAndAwaitForAccountTransition()))
        try FileManager.default.removeItem(at: file)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func absentObservationArrivingAfterRevocationIsStillRetained() async throws {
        let (h, owner, before) = try await fixture()
        let original = try prior.accounting(h, before.plan.targets[0].original.assetID)
        try FileManager.default.removeItem(at: path(h, original.fileToken))
        let first = ImageFocusEngineTests.Signal(), releaseFirst = ImageFocusEngineTests.Signal()
        let second = ImageFocusEngineTests.Signal(), releaseSecond = ImageFocusEngineTests.Signal()
        let ended = ImageFocusEngineTests.Signal(), drained = ImageFocusEngineTests.Signal()
        let calls = OSAllocatedUnfairLock(initialState: 0)
        try await owner.setAcquisitionEntryPause { point in
            guard point == .inspectOriginal else { return }
            let number = calls.withLock { $0 += 1; return $0 }
            if number == 1 { await first.open(); await releaseFirst.wait() }
            if number == 2 { await second.open(); await releaseSecond.wait() }
        }
        let operation = Task {
            do { let value = try await owner.removeAppReleaseOriginal(before); await ended.open(); await first.open(); return value }
            catch { await ended.open(); await first.open(); throw error }
        }
        await first.wait()
        let didPause = !(await ended.isOpen)
        #expect(didPause)
        guard didPause else {
            await releaseFirst.open(); await releaseSecond.open()
            _ = try? await operation.value
            #expect(await owner.invalidateAndAwaitForAccountTransition())
            return
        }
        let drain = Task {
            let result = await owner.invalidateAndAwaitForAccountTransition()
            await drained.open(); await second.open(); return result
        }
        // Assert actual revoked owner state before returning the first proof.
        await Task.yield()
        #expect(owner.heldOriginalAdmissionClosedForTesting)
        await releaseFirst.open()
        await #expect(throws: (any Error).self) { _ = try await operation.value }
        await second.wait()
        #expect(!(await drained.isOpen))
        // Settlement's second proof is still paused: only the first, revoked
        // operation's observation can have set this monotonic evidence bit.
        #expect(owner.observedHeldOriginalAbsenceForTesting)
        #expect(try prior.prior.snapshot(h).release.progress == before)
        await releaseSecond.open()
        #expect(await drain.value)
    }

    @Test func pausedDisposerCannotSurviveAccountClosure() async throws {
        let (h, owner, before) = try await fixture()
        let original = try prior.accounting(h, before.plan.targets[0].original.assetID)
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal(), ended = ImageFocusEngineTests.Signal()
        try await owner.setAcquisitionEntryPause { point in
            guard point == .releaseOriginal else { return }; await entered.open(); await release.wait()
        }
        let task = Task {
            do { let value = try await owner.removeAppReleaseOriginal(before); await ended.open(); await entered.open(); return value }
            catch { await ended.open(); await entered.open(); throw error }
        }
        await entered.wait(); #expect(!(await ended.isOpen))
        let drain = Task { await owner.invalidateAndAwaitForAccountTransition() }
        await Task.yield()
        await #expect(throws: (any Error).self) { _ = try await SharedMediaNativeReceivingStagingTests().reopen(h) }
        await release.open()
        await #expect(throws: (any Error).self) { _ = try await task.value }
        #expect(await drain.value)
        #expect(FileManager.default.fileExists(atPath: path(h, original.fileToken).path))
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        _ = try await cold.removeAppReleaseOriginal(before)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func shutdownJoinsAnEnteredSynchronousUnlinkBeforeReleasingRoots() async throws {
        let entered = ImageFocusEngineTests.Signal(), release = DispatchSemaphore(value: 0)
        let draining = DispatchSemaphore(value: 0)
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let waitTimedOut = OSAllocatedUnfairLock(initialState: false)
        let (h, owner, before) = try await fixture(fault: { point in
            guard point == .afterUnlink else { return }
            calls.withLock { $0 += 1 }
            Task.detached(priority: .userInitiated) { await entered.open() }
            guard release.wait(timeout: .now() + 5) == .success else {
                waitTimedOut.withLock { $0 = true }
                throw SharedMediaStorageFailure.unavailable
            }
        })
        let operation = Task {
            do {
                let value = try await owner.removeAppReleaseOriginal(before)
                await entered.open()
                return value
            } catch {
                await entered.open()
                throw error
            }
        }
        // Wait for entry or operation completion, not a timing guess about the
        // audited predecessor. A failed admission must also release this wait.
        await entered.wait()
        let didEnter = calls.withLock { $0 } == 1
        #expect(didEnter)
        guard didEnter else {
            _ = try? await operation.value
            #expect(await owner.invalidateAndAwaitForAccountTransition())
            return
        }
        // This thread cannot call MainActor or the permit. It releases the
        // descriptor section even when shutdown is synchronously waiting on it.
        let unblock = Task.detached(priority: .userInitiated) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    let didStart = draining.wait(timeout: .now() + 5) == .success
                    _ = DispatchSemaphore(value: 0).wait(timeout: .now() + 0.1)
                    release.signal()
                    continuation.resume(returning: didStart)
                }
            }
        }
        let drain = Task { draining.signal(); return await owner.invalidateAndAwaitForAccountTransition() }
        await #expect(throws: (any Error).self) { _ = try await operation.value }
        #expect(await unblock.value)
        #expect(await drain.value)
        #expect(calls.withLock { $0 } == 1)
        #expect(!waitTimedOut.withLock { $0 })
        #expect(try prior.prior.snapshot(h).release.progress == before)
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        _ = try await cold.removeAppReleaseOriginal(before)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [false, true])
    func sharedDispositionNeverAuthorizesPhysicalRemoval(_ foreign: Bool) async throws {
        let (h, owner, before) = try await SharedMediaNativeOriginalDispositionSharingTests().fixture(foreign: foreign)
        let bytes = try prior.originalBytes(h, before)
        let after = try await owner.disposeAppReleaseOriginal(before)
        #expect(after.targets.first?.original?.disposition == .shared)
        await #expect(throws: (any Error).self) { _ = try await owner.removeAppReleaseOriginal(after) }
        #expect(try prior.originalBytes(h, before) == bytes)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func replacementIdentityNeverReleasesAccounting() async throws {
        let (h, owner, before) = try await fixture()
        let original = try prior.accounting(h, before.plan.targets[0].original.assetID)
        let file = path(h, original.fileToken), retained = file.appendingPathExtension("retained")
        try FileManager.default.moveItem(at: file, to: retained)
        try Data([1, 2, 3]).write(to: file)
        await #expect(throws: (any Error).self) { _ = try await owner.removeAppReleaseOriginal(before) }
        #expect(try prior.accounting(h, original.assetID) == original)
        #expect(!(await owner.invalidateAndAwaitForAccountTransition()))
        try FileManager.default.removeItem(at: file)
        try FileManager.default.removeItem(at: retained)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func rawSealRejectsReceiptDriftAndReplacedCounter() async throws {
        let (h, owner, before) = try await fixture()
        let c = h.context(), header = try prior.currentHeader(h, before)
        // The raw seal has no filesystem authority and can be checked separately.
        let original = try prior.accounting(h, before.plan.targets[0].original.assetID)
        let snapshot = try SharedMediaNativeOriginalRemovalRecovery.snapshot(before, context: c, header: header)
        let after = try SharedMediaNativeOriginalRemovalRecovery.successor(before)
        let expected = try SharedMediaNativeReceivingReleaseState.expected(after,
            prepared: snapshot.release.origin.prepared, received: snapshot.release.origin.received)
        let seal = try SharedMediaNativeOriginalRemovalPoststate(before: before, after: after,
            successor: expected, original: original, context: c)
        let rows = try Rows(c, profile: before.plan.profile, source: before.plan.targets[0].original)
        // Persist corruption in a mutable field; identity/fingerprint setters
        // remain private. A fresh context must reject the changed raw receipt.
        let savedResult = rows.receipt.resultData
        rows.receipt.resultData = Data([0]); try c.save()
        #expect(throws: (any Error).self) { try seal.requirePredecessor(h.context()) }
        rows.receipt.resultData = savedResult; try c.save()
        try seal.requirePredecessor(h.context())
        let other = h.context(), id = original.assetID
        let old = try Rows.one(other, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == id }))
        let replacement = SharedMediaAssetReferenceCountRecord(assetID: old.id, assetGeneration: old.assetGeneration,
            inventoryID: old.inventoryID, inventoryGeneration: old.inventoryGeneration, ownerID: old.ownerID, liveCount: old.liveCount)
        replacement.revision = old.revision; replacement.retirementID = old.retirementID
        other.delete(old); try other.save(); other.insert(replacement); try other.save()
        #expect(throws: (any Error).self) { try seal.requirePredecessor(h.context()) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["count", "identity", "reference"])
    func corruptRetirementNeverAuthorizesUnlink(_ fault: String) async throws {
        let (h, owner, before) = try await fixture()
        let c = h.context(), source = before.plan.targets[0].original
        let rows = try Rows(c, profile: before.plan.profile, source: source)
        let (ref, _) = try Rows.reference(c, source: source, live: false)
        let oldCount = rows.count.liveCount, oldIdentity = rows.allocation.physicalIdentity, oldRole = ref.roleRaw
        switch fault {
        case "count": rows.count.liveCount = 1
        case "identity": rows.allocation.physicalIdentity = "invalid"
        default: ref.roleRaw = "display"
        }
        try c.save()
        await #expect(throws: (any Error).self) { _ = try await owner.removeAppReleaseOriginal(before) }
        #expect(FileManager.default.fileExists(atPath: path(h, rows.asset.fileToken).path))
        rows.count.liveCount = oldCount; rows.allocation.physicalIdentity = oldIdentity; ref.roleRaw = oldRole; try c.save()
        #expect(try prior.prior.snapshot(h).release.progress == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    func fixture(count: Int = 1, fault: (@Sendable (SharedMediaPhotoReleaseBoundary) throws -> Void)? = nil)
        async throws -> (Store, SharedMediaNativeOriginalOwner, Values.Progress) {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(count: count,
            temporaryStore: true, fenceBootstrap: true)
        if let fault { try await owner.setAppOriginalReleaseFault(fault) }
        let prepared = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft,
            pairIDs: SharedMediaNativeReceivingStagingTests().pairIDs(request))
        _ = try await owner.receiveAppPrepared(prepared)
        let admission = try await owner.appReleaseStageRequest(prepared, releaseID: UUID())
        _ = try await owner.stageAppRelease(admission)
        let started = try await owner.startAppRelease(admission.request)
        let retired = try await owner.retireAppReleasePair(started)
        let gone = try await owner.removeAppReleasePair(retired)
        return (h, owner, try await owner.disposeAppReleaseOriginal(gone))
    }
    func path(_ h: Store, _ token: String) -> URL { h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(token) }
}

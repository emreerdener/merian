import Foundation
import SwiftData
import Testing
import os
@testable import Merian

@Suite("Inactive held pair removal", .serialized)
@MainActor
struct SharedMediaNativeReleasePairRemovalOwnerTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    typealias Values = SharedMediaNativeReceivingReleaseValues
    let retirement = SharedMediaNativeReleasePairOwnerTests()

    @Test(arguments: [false, true], [1, 2])
    func removesOnlySelectedDerivativesAndRecoversCold(_ shared: Bool, _ count: Int) async throws {
        let (h, owner, before) = try await fixture(shared: shared, count: count)
        let snapshot = try retirement.snapshot(h), state = try #require(snapshot.pairs.first)
        let intent = try state.intent(), oldBytes = snapshot.release.state.package.allocated
        let originals = try originalBytes(h, before), envelope = try h.package().supportingContextData
        let retainedFiles = try snapshot.pairs.dropFirst().flatMap { pair in
            try pair.work.map { work in try path(h, pair.file(work.id).token) }
        }
        let retainedBytes = try retainedFiles.map { try Data(contentsOf: $0) }
        var saves = 0
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        let after = try await owner.removeAppReleasePair(before), result = try retirement.snapshot(h)
        #expect(after == (try SharedMediaNativeReleasePairRemovalRecovery.successor(before)))
        #expect(result.release.progress == after && result.pairs.count == count - 1)
        #expect(result.release.state.package.allocated == oldBytes - intent.ai.byteCount - intent.display.byteCount)
        #expect(result.ownedOriginals == snapshot.ownedOriginals && result.targetOrigins == snapshot.targetOrigins)
        #expect(try originalBytes(h, before) == originals)
        #expect(try retainedFiles.map { try Data(contentsOf: $0) } == retainedBytes)
        #expect(try h.package().supportingContextData == envelope)
        for work in state.work { #expect(!FileManager.default.fileExists(atPath: path(h, try state.file(work.id).token).path)) }
        #expect(try await owner.removeAppReleasePair(before) == after)
        #expect(saves == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        #expect(try await cold.removeAppReleasePair(before) == after)
        #expect(try originalBytes(h, before) == originals)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [0, 1, 2])
    func alreadyAbsentOutputsReleaseChargesOnlyOnSave(_ missing: Int) async throws {
        let (h, owner, before) = try await fixture()
        let snapshot = try retirement.snapshot(h), state = try #require(snapshot.pairs.first)
        for work in state.work.prefix(missing) { try FileManager.default.removeItem(at: path(h, state.file(work.id).token)) }
        #expect(try retirement.snapshot(h).release.state.package.allocated == snapshot.release.state.package.allocated)
        let after = try await owner.removeAppReleasePair(before)
        #expect(try retirement.snapshot(h).release.progress == after)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: ["beforeSave", "afterSave", "beforeReadback"])
    func uncertaintyRetainsTheSameOperation(_ fault: String) async throws {
        let (h, owner, before) = try await fixture()
        let snapshot = try retirement.snapshot(h), originals = try originalBytes(h, before)
        var saves = 0
        try owner.setMetadataFault {
            if $0 == .beforeSave { saves += 1 }
            if (fault == "beforeSave" && $0 == .beforeSave) || (fault == "afterSave" && $0 == .afterSave) ||
                (fault == "beforeReadback" && $0 == .beforeReadback) { throw SharedMediaStorageFailure.unavailable }
        }
        if fault == "afterSave" { _ = try await owner.removeAppReleasePair(before) }
        else { await #expect(throws: (any Error).self) { _ = try await owner.removeAppReleasePair(before) } }
        if fault == "beforeSave" {
            #expect(try retirement.snapshot(h).release.progress == before)
            #expect(try retirement.snapshot(h).release.state.package.allocated == snapshot.release.state.package.allocated)
        }
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        let after = try await owner.removeAppReleasePair(before)
        #expect(after.plan == before.plan && after.targets.first?.pair == before.targets.first?.pair)
        #expect(saves == (fault == "beforeSave" ? 2 : 1))
        #expect(try originalBytes(h, before) == originals)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func interruptedUnlinkHandsBackDurableRetirementAndReopens() async throws {
        let (h, owner, before) = try await fixture(pairFault: {
            if $0 == .afterUnlink { throw SharedMediaStorageFailure.unavailable }
        })
        let snapshot = try retirement.snapshot(h)
        await #expect(throws: (any Error).self) { _ = try await owner.removeAppReleasePair(before) }
        #expect(try retirement.snapshot(h).release.progress == before)
        #expect(try retirement.snapshot(h).release.state.package.allocated == snapshot.release.state.package.allocated)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        let after = try await cold.removeAppReleasePair(before)
        #expect(after.plan == before.plan && after.targets.first?.pair == before.targets.first?.pair)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func replacementStaysUnresolvedAndKeepsCharges() async throws {
        let (h, owner, before) = try await fixture()
        let snapshot = try retirement.snapshot(h), state = try #require(snapshot.pairs.first), work = try #require(state.work.first)
        let file = try path(h, state.file(work.id).token), bytes = try Data(contentsOf: file)
        let retained = file.appendingPathExtension("fixture-retained")
        try FileManager.default.moveItem(at: file, to: retained); try bytes.write(to: file)
        await #expect(throws: (any Error).self) { _ = try await owner.removeAppReleasePair(before) }
        #expect(try Data(contentsOf: file) == bytes)
        #expect(try retirement.snapshot(h).release.progress == before)
        #expect(try retirement.snapshot(h).release.state.package.allocated == snapshot.release.state.package.allocated)
        #expect(!(await owner.invalidateAndAwaitForAccountTransition()))
        try FileManager.default.removeItem(at: file); try FileManager.default.moveItem(at: retained, to: file)
        // Rename changes ctime: the same inode is not the saved exact identity.
        #expect(!(await owner.invalidateAndAwaitForAccountTransition()))
        try FileManager.default.removeItem(at: file)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func revokedPausedDisposerCannotOverlapNewOwner() async throws {
        let (h, owner, before) = try await fixture()
        let snapshot = try retirement.snapshot(h), state = try #require(snapshot.pairs.first)
        let entered = ImageFocusEngineTests.Signal(), release = ImageFocusEngineTests.Signal(), ended = ImageFocusEngineTests.Signal()
        try await owner.setAcquisitionEntryPause { point in
            guard point == .releasePair else { return }; await entered.open(); await release.wait()
        }
        let operation = Task {
            do { let value = try await owner.removeAppReleasePair(before); await ended.open(); await entered.open(); return value }
            catch { await ended.open(); await entered.open(); throw error }
        }
        await entered.wait(); #expect(!(await ended.isOpen))
        let drain = Task { await owner.invalidateAndAwaitForAccountTransition() }
        await Task.yield()
        await #expect(throws: (any Error).self) { _ = try await SharedMediaNativeReceivingStagingTests().reopen(h) }
        await release.open()
        await #expect(throws: (any Error).self) { _ = try await operation.value }
        #expect(await drain.value)
        #expect(try retirement.snapshot(h).release.progress == before)
        for work in state.work { #expect(FileManager.default.fileExists(atPath: path(h, try state.file(work.id).token).path)) }
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        _ = try await cold.removeAppReleasePair(before)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func shutdownJoinsAnEnteredSynchronousUnlinkBeforeReleasingRoots() async throws {
        let entered = ImageFocusEngineTests.Signal(), release = DispatchSemaphore(value: 0)
        let draining = DispatchSemaphore(value: 0)
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let waitTimedOut = OSAllocatedUnfairLock(initialState: false)
        let (h, owner, before) = try await fixture(pairFault: { point in
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
                let value = try await owner.removeAppReleasePair(before)
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
            await withCheckedContinuation { continuation in
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
        #expect(try retirement.snapshot(h).release.progress == before)
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        _ = try await cold.removeAppReleasePair(before)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func lateOutputReappearanceCannotReleaseCharges() async throws {
        let (h, owner, before) = try await fixture()
        let snapshot = try retirement.snapshot(h), state = try #require(snapshot.pairs.first)
        let work = try #require(state.work.first), file = try path(h, state.file(work.id).token)
        let bytes = try Data(contentsOf: file)
        try owner.setMetadataFault { if $0 == .beforeSave { try bytes.write(to: file) } }
        await #expect(throws: (any Error).self) { _ = try await owner.removeAppReleasePair(before) }
        #expect(try retirement.snapshot(h).release.progress == before)
        #expect(try retirement.snapshot(h).release.state.package.allocated == snapshot.release.state.package.allocated)
        #expect(!(await owner.invalidateAndAwaitForAccountTransition()))
        try FileManager.default.removeItem(at: file)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await SharedMediaNativeReceivingStagingTests().reopen(h)
        _ = try await cold.removeAppReleasePair(before)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }

    @Test func removedRoleIDsRemainUnavailableToFreshAdmissions() async throws {
        let (h, owner, before) = try await fixture()
        _ = try await owner.removeAppReleasePair(before)
        let c = h.context()
        let ids = [before.plan.package.id] + before.plan.targets.flatMap(\.identities)
        for id in ids {
            #expect(throws: (any Error).self) {
                try SharedMediaNativeReleaseStageIdentity.requireFresh([id], inventoryID: h.inventoryID, context: c)
            }
        }
        try SharedMediaNativeReleaseStageIdentity.requireFresh([UUID(), UUID()], inventoryID: h.inventoryID, context: c)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func acquisitionIdentityAuditRejectsEveryRetainedOutputRole() async throws {
        let (h, owner, before) = try await fixture()
        _ = try await owner.removeAppReleasePair(before)
        let target = try #require(before.plan.targets.first)
        let ids = [target.pairID] + target.ai.identities + target.display.identities
        func request(_ id: UUID, _ role: Int) -> SharedMediaAcquisitionIntent {
            .init(operationID: role == 0 ? id : UUID(), inventoryID: h.inventoryID,
                inventoryGeneration: before.plan.profile.generation, ownerID: h.ownerID,
                expectedInventoryRevision: 0, packageID: role == 3 ? id : UUID(),
                draftGeneration: UUID(), packageExpectation: .absent,
                assetID: role == 1 ? id : UUID(), assetGeneration: UUID(),
                referenceID: role == 2 ? id : UUID(), ordinal: 0, kind: .picker,
                writerEpoch: UUID(), maximumBytes: PhotoPreparationPolicy.original)
        }
        for id in ids {
            for role in 0..<4 {
                let candidate = request(id, role)
                #expect(throws: (any Error).self) {
                    try SharedMediaNativeAppAcquisitionIdentity.direct(candidate, context: h.context())
                }
                await #expect(throws: (any Error).self) {
                    try await SharedMediaNativeAppAcquisitionIdentity.audit(candidate, container: h.container, check: {})
                }
            }
        }
        try await SharedMediaNativeAppAcquisitionIdentity.audit(request(UUID(), 0), container: h.container, check: {})
        // The public preparation route still rejects this held-release graph.
        // The direct adapter above qualifies identity denial, not coexistence.
        await #expect(throws: (any Error).self) {
            _ = try await owner.prepareAppOriginal(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, kind: .picker)
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    func fixture(shared: Bool = false, count: Int = 1,
                 pairFault: (@Sendable (SharedMediaInboxHandoffBoundary) throws -> Void)? = nil) async throws
        -> (Store, SharedMediaNativeOriginalOwner, Values.Progress) {
        let mixed = shared && count == 2
        let (h, owner, initial) = try await SharedMediaNativeAppReceivingTests().fixture(count: mixed ? 1 : count,
            foreignOriginal: shared, temporaryStore: true, fenceBootstrap: true)
        let receiving: SharedMediaNativeAppReceivingRequest
        if mixed {
            // Existing sharing creates an absent destination. Add an owned
            // second original through the normal draft path before any freeze.
            let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 1, kind: .picker)
            let bytes = PhotoPreparationTestHarness.image()
            let acquired = try await owner.acquireAppOriginal(request) { bytes }
            let original = PhotoOriginalReference(ownerID: h.ownerID, packageID: h.packageID, referenceID: request.referenceID,
                assetID: request.assetID, assetGeneration: request.assetGeneration, draftGeneration: h.draft,
                referenceRevision: acquired.referenceRevision)
            let ready = try await owner.prepareAndDeliverAppPhoto(original: original,
                recipe: .init(format: .stillImage, isPro: false, cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0))
            let ids = try SharedMediaNativeReceivingStagingTests().pairIDs(initial) + [ready.intent().pairID]
            receiving = try await owner.appReceivingRequest(packageID: h.packageID, pairIDs: ids, operationID: UUID(),
                queueID: UUID(), observationID: UUID(), bindingID: UUID(), generation: UUID(), eventID: UUID(),
                timestamp: Date(timeIntervalSince1970: 1_700_000_000))
        } else { receiving = initial }
        // This DEBUG seam belongs to ordinary preparation: configure it before
        // the held release closes that path. The same I/O actor retains it.
        if let pairFault { try await owner.setAppPairFileFault(pairFault) }
        let prepared = try await owner.stageAppReceiving(packageID: h.packageID, draftGeneration: h.draft,
            pairIDs: SharedMediaNativeReceivingStagingTests().pairIDs(receiving))
        _ = try await owner.receiveAppPrepared(prepared)
        let admission = try await owner.appReleaseStageRequest(prepared, releaseID: UUID())
        _ = try await owner.stageAppRelease(admission)
        let progress = try await owner.startAppRelease(admission.request)
        return (h, owner, try await owner.retireAppReleasePair(progress))
    }
    private func path(_ h: Store, _ token: String) -> URL { h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(token) }
    private func originalBytes(_ h: Store, _ progress: Values.Progress) throws -> [Data] {
        try progress.plan.targets.map { target in
            let id = target.original.assetID
            let asset = try #require(try h.context().fetch(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == id })).first)
            return try Data(contentsOf: path(h, asset.fileToken))
        }
    }
}

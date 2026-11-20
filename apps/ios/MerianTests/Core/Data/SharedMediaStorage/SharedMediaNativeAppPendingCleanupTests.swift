import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native app pending original cleanup", .serialized)
@MainActor
struct SharedMediaNativeAppPendingCleanupTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store

    @Test(arguments: ["absent", "zero", "partial", "final"], [false, true])
    func explicitAbandonmentAndColdRecoveryPreserveExactReceipt(_ kind: String, _ reserved: Bool) async throws {
        let h = try Store(), owner = try await h.open(), request = try await held(h, owner, final: kind == "final")
        if reserved {
            let c = h.context(), rows = try SharedMediaNativeAppPendingRows(c, request: request)
            rows.receipt.phaseRaw = "reserved"; rows.receipt.revision = 0
            rows.allocation.stateRaw = "p1Reserved"; rows.lease.stateRaw = "open"; rows.work.writerStateRaw = "open"
            rows.package.phaseRaw = "acquiring"
            try c.save()
        }
        if kind == "zero" || kind == "partial" { try seed(h, request, partial: true, empty: kind == "zero") }
        let before = try allocation(h, request).reservedBytes
        try await owner.recoverAppPendingAbandonments()
        #expect(try allocation(h, request).reservedBytes == before)
        #expect(try work(h, request).terminalProof == nil)
        try await owner.abandonAppOriginal(request)
        let encoded = try #require(work(h, request).terminalProof)
        #expect(try allocation(h, request).reservedBytes == request.maximumBytes)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await reopen(h)
        #expect(try work(h, request).terminalProof == encoded)
        try await cold.recoverAppPendingAbandonments()
        try released(h, request)
        try await cold.abandonAppOriginal(request)
        try await cold.recoverAppPendingAbandonments()
        await #expect(throws: (any Error).self) { _ = try await cold.acquireAppOriginal(request) { Issue.record("Repeated terminal loader"); return Data() } }
        #expect(try h.package(h.ordinaryID).supportingContextData == Data("ordinary-draft".utf8))
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }
    @Test(arguments: [SharedMediaPhotoReleaseBoundary.beforeUnlink, .afterUnlink, .beforeSync, .afterSync])
    func disposalInterruptionRetainsReservationAndRecovers(_ point: SharedMediaPhotoReleaseBoundary) async throws {
        let h = try Store(), owner = try await h.open(), request = try await held(h, owner, final: true)
        try await owner.abandonAppOriginal(request)
        try await owner.setAppPendingReleaseFault { if $0 == point { throw SharedMediaStorageFailure.unavailable } }
        await #expect(throws: (any Error).self) { try await owner.recoverAppPendingAbandonments() }
        #expect(try allocation(h, request).reservedBytes == request.maximumBytes)
        let closure = try work(h, request).terminalProof
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await reopen(h)
        #expect(try work(h, request).terminalProof == closure)
        try await cold.recoverAppPendingAbandonments(); try released(h, request)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }
    @Test(arguments: [SharedMediaNativeLifecycleBoundary.beforeSave, .afterSave, .beforeReleaseSave, .afterReleaseSave])
    func exactSaveRecovery(_ point: SharedMediaNativeLifecycleBoundary) async throws {
        let h = try Store(), owner = try await h.open(), request = try await held(h, owner)
        try owner.setLifecycleFault { if $0 == point { throw SharedMediaStorageFailure.unavailable } }
        if point == .beforeSave {
            await #expect(throws: (any Error).self) { try await owner.abandonAppOriginal(request) }
            #expect(try work(h, request).terminalProof == nil)
            try owner.setLifecycleFault(nil); try await owner.abandonAppOriginal(request)
        } else { try await owner.abandonAppOriginal(request) }
        if point == .beforeReleaseSave {
            await #expect(throws: (any Error).self) { try await owner.recoverAppPendingAbandonments() }
            #expect(try allocation(h, request).reservedBytes == request.maximumBytes)
        } else { try await owner.recoverAppPendingAbandonments() }
        try owner.setLifecycleFault(nil); try await owner.recoverAppPendingAbandonments()
        try released(h, request)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    @Test(arguments: [false, true])
    func acknowledgementLossPermitsOnlySavedRecovery(_ release: Bool) async throws {
        let h = try Store(), owner = try await h.open(), request = try await held(h, owner, final: true)
        if release { try await owner.abandonAppOriginal(request) }
        var lost = false
        try owner.setLifecycleFault { point in
            if point == (release ? .afterReleaseSave : .afterSave) { lost = true }
            if lost && point == .beforeReadback { throw SharedMediaStorageFailure.unavailable }
        }
        if release { await #expect(throws: (any Error).self) { try await owner.recoverAppPendingAbandonments() } }
        else { await #expect(throws: (any Error).self) { try await owner.abandonAppOriginal(request) } }
        #expect(lost)
        try owner.setLifecycleFault(nil)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await reopen(h)
        try await cold.recoverAppPendingAbandonments(); try await cold.abandonAppOriginal(request)
        try released(h, request)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }
    @Test(arguments: ["replace", "late", "lateBeforeSave"])
    func changedFileCannotReleaseCapacity(_ kind: String) async throws {
        let h = try Store(), owner = try await h.open(), request = try await held(h, owner, final: kind == "replace")
        try await owner.abandonAppOriginal(request)
        let closure = try work(h, request).terminalProof
        if kind == "replace" { try PhotoPreparationTestHarness.image().write(to: file(h, request), options: .atomic) }
        else if kind == "late" { try seed(h, request, partial: false) }
        else {
            try owner.setLifecycleFault { point in
                if point == .beforeReleaseSave { try seed(h, request, partial: false) }
            }
        }
        await #expect(throws: (any Error).self) { try await owner.recoverAppPendingAbandonments() }
        #expect(try work(h, request).terminalProof == closure)
        #expect(try allocation(h, request).reservedBytes == request.maximumBytes)
        #expect(FileManager.default.fileExists(atPath: file(h, request).path))
        try owner.setLifecycleFault(nil)
        // The exact recorded closure is never silently replaced.
        await #expect(throws: (any Error).self) { try await owner.recoverAppPendingAbandonments() }
        _ = await owner.invalidateAndAwaitForAccountTransition()
    }
    @Test func terminalReplayAfterUnrelatedProgressNeverTouchesNewFile() async throws {
        let h = try Store(), owner = try await h.open(), request = try await held(h, owner)
        try await owner.abandonAppOriginal(request); try await owner.recoverAppPendingAbandonments()
        let next = try await owner.prepareAppOriginal(packageID: UUID(), draftGeneration: UUID(), ordinal: 0, kind: .picker)
        let bytes = PhotoPreparationTestHarness.image()
        _ = try await owner.acquireAppOriginal(next) { bytes }
        try await owner.abandonAppOriginal(request)
        try released(h, request)
        #expect(try Data(contentsOf: file(h, next)) == bytes)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    @Test func readyOriginalAndReceivingConsumerSurviveCleanup() async throws {
        let h = try Store(receiving: true), (owner, consumerID) = try await h.openWithReceivingConsumer()
        let before = SharedMediaNativeAppMetadataFacts.Consumer(try #require(try SharedMediaConsumerLookup.one(h.context(), id: consumerID)))
        let original = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        let bytes = PhotoPreparationTestHarness.image()
        _ = try await owner.acquireAppOriginal(original) { bytes }
        let request = try await held(h, owner, ordinal: 1)
        try await owner.abandonAppOriginal(request); try await owner.recoverAppPendingAbandonments()
        try released(h, request)
        #expect(try Data(contentsOf: file(h, original)) == bytes)
        #expect(before == SharedMediaNativeAppMetadataFacts.Consumer(try #require(try SharedMediaConsumerLookup.one(h.context(), id: consumerID))))
        #expect(try await owner.inspectApp().consumers == 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    @Test(arguments: ["work", "lease", "allocation", "membership", "receipt"])
    func tupleDriftBlocksBeforeDisposal(_ field: String) async throws {
        let h = try Store(), owner = try await h.open(), request = try await held(h, owner, final: true)
        try await owner.abandonAppOriginal(request)
        let c = h.context(), rows = try SharedMediaNativeAppPendingRows(c, request: request)
        switch field {
        case "work": rows.work.processEpoch = UUID()
        case "lease": rows.lease.stateRaw = "open"
        case "allocation": rows.allocation.reservedBytes -= 1
        case "membership": rows.member.membersData = try SharedMediaMembership(groups: []).encoded()
        default: rows.receipt.requestData = Data("changed-request".utf8)
        }
        try c.save()
        await #expect(throws: (any Error).self) { try await owner.recoverAppPendingAbandonments() }
        #expect(FileManager.default.fileExists(atPath: file(h, request).path))
        _ = await owner.invalidateAndAwaitForAccountTransition()
    }
    @Test func freshDriftAtSaveBoundaryBlocksClosure() async throws {
        let h = try Store(), owner = try await h.open(), request = try await held(h, owner, final: true)
        try owner.setLifecycleFault { point in
            guard point == .beforeSave else { return }
            let c = h.context(), rows = try SharedMediaNativeAppPendingRows(c, request: request)
            rows.member.revision += 1; try c.save()
        }
        await #expect(throws: (any Error).self) { try await owner.abandonAppOriginal(request) }
        #expect(try work(h, request).terminalProof == nil)
        #expect(FileManager.default.fileExists(atPath: file(h, request).path))
        _ = await owner.invalidateAndAwaitForAccountTransition()
    }
    @Test func cancellationBeforeUnlinkRetainsExactFile() async throws {
        let h = try Store(), owner = try await h.open(), request = try await held(h, owner, final: true)
        try await owner.abandonAppOriginal(request)
        try await owner.setAppPendingReleaseFault { if $0 == .beforeUnlink { withUnsafeCurrentTask { $0?.cancel() } } }
        let task = Task { try await owner.recoverAppPendingAbandonments() }
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(FileManager.default.fileExists(atPath: file(h, request).path))
        #expect(try allocation(h, request).reservedBytes == request.maximumBytes)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await reopen(h); try await cold.recoverAppPendingAbandonments(); try released(h, request)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }
    @Test func readyDerivativePairSurvivesOtherOriginalCleanup() async throws {
        let h = try Store(), owner = try await h.open()
        let original = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        let bytes = PhotoPreparationTestHarness.image(), result = try await owner.acquireAppOriginal(original) { bytes }
        let reference = PhotoOriginalReference(ownerID: h.ownerID, packageID: h.packageID, referenceID: original.referenceID,
            assetID: original.assetID, assetGeneration: original.assetGeneration, draftGeneration: h.draft, referenceRevision: result.referenceRevision)
        let pair = try await owner.prepareAndDeliverAppPhoto(original: reference, recipe: .init(format: .stillImage, isPro: false,
            cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0))
        let intent = try pair.intent(), retained = try [pair.file(intent.ai.id), pair.file(intent.display.id)]
        let data = try retained.map { try Data(contentsOf: h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent($0.token)) }
        let request = try await held(h, owner, ordinal: 1)
        try await owner.abandonAppOriginal(request); try await owner.recoverAppPendingAbandonments(); try released(h, request)
        #expect(try retained.map { try Data(contentsOf: h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent($0.token)) } == data)
        #expect(try Data(contentsOf: file(h, original)) == bytes)
        #expect(try h.package().phaseRaw == "draftOwned")
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    @Test(arguments: [false, true])
    func sharedOriginalDriftAtBoundaryBlocksCleanup(_ release: Bool) async throws {
        let h = try Store(), owner = try await h.open()
        let original = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        let bytes = PhotoPreparationTestHarness.image()
        _ = try await owner.acquireAppOriginal(original) { bytes }
        let request = try await held(h, owner, final: true, ordinal: 1)
        if release { try await owner.abandonAppOriginal(request) }
        try owner.setLifecycleFault { point in
            guard point == (release ? .beforeReleaseSave : .beforeSave) else { return }
            let c = h.context(), id = original.assetID
            let counter = try SharedMediaNativeAppPendingRows.one(c, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == id }))
            counter.liveCount += 1; try c.save()
        }
        if release { await #expect(throws: (any Error).self) { try await owner.recoverAppPendingAbandonments() } }
        else { await #expect(throws: (any Error).self) { try await owner.abandonAppOriginal(request) } }
        #expect(try allocation(h, request).reservedBytes == request.maximumBytes)
        #expect(try Data(contentsOf: file(h, original)) == bytes)
        _ = await owner.invalidateAndAwaitForAccountTransition()
    }
    @Test func activeLoaderMustExitBeforeAbandonment() async throws {
        let h = try Store(), owner = try await h.open(), gate = Gate()
        let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        let task = Task {
            do { return try await owner.acquireAppOriginal(request) { await gate.hold(); throw SharedMediaStorageFailure.unavailable } }
            catch { await gate.fail(); throw error }
        }
        guard await gate.wait() else { _ = await task.result; _ = await owner.invalidateAndAwaitForAccountTransition(); throw SharedMediaStorageFailure.unavailable }
        await #expect(throws: (any Error).self) { try await owner.abandonAppOriginal(request) }
        #expect(try work(h, request).terminalProof == nil)
        await gate.release(); _ = await task.result
        try await owner.abandonAppOriginal(request); try await owner.recoverAppPendingAbandonments(); try released(h, request)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    private actor Gate {
        private var waiter: CheckedContinuation<Void, Never>?, entry: CheckedContinuation<Bool, Never>?
        private var entered = false, failed = false
        func hold() async { await withCheckedContinuation { waiter = $0; entered = true; entry?.resume(returning: true); entry = nil } }
        func wait() async -> Bool { if entered { return true }; if failed { return false }; return await withCheckedContinuation { entry = $0 } }
        func fail() { failed = true; entry?.resume(returning: false); entry = nil }
        func release() { waiter?.resume(); waiter = nil }
    }
    private func held(_ h: Store, _ owner: SharedMediaNativeOriginalOwner, final: Bool = false, ordinal: Int64 = 0) async throws -> SharedMediaAcquisitionIntent {
        let r = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: ordinal, kind: .picker)
        if final { try owner.setAcquisitionFault { if $0 == .beforeCompletionSave { throw SharedMediaStorageFailure.unavailable } } }
        let bytes = PhotoPreparationTestHarness.image()
        await #expect(throws: (any Error).self) { _ = try await owner.acquireAppOriginal(r) { if !final { throw SharedMediaStorageFailure.unavailable }; return bytes } }
        try owner.setAcquisitionFault(nil)
        #expect(try SharedMediaAcquisitionReceipt.read(receipt(h, r), expected: r) == .held(r))
        return r
    }
    private func reopen(_ h: Store) async throws -> SharedMediaNativeOriginalOwner {
        let owner = try SharedMediaNativeOriginalOwner.appDispatch(account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: h.ownerID, runtime: h.runtime), drain: .init())
        _ = try await owner.openApp(container: h.container, parent: h.parent, inventoryID: h.inventoryID); return owner
    }
    private func file(_ h: Store, _ r: SharedMediaAcquisitionIntent, partial: Bool = false) -> URL {
        h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(partial ? r.partialToken : r.finalToken)
    }
    private func seed(_ h: Store, _ r: SharedMediaAcquisitionIntent, partial: Bool, empty: Bool = false) throws {
        let url = file(h, r, partial: partial)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (empty ? Data() : PhotoPreparationTestHarness.image()).write(to: url)
    }
    private func receipt(_ h: Store, _ r: SharedMediaAcquisitionIntent) throws -> SharedMediaAcquisitionReceiptRecord {
        let id = r.operationID
        return try SharedMediaNativeAppPendingRows.one(h.context(), FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }))
    }
    private func work(_ h: Store, _ r: SharedMediaAcquisitionIntent) throws -> PhotoPreparationLease {
        let id = r.operationID
        return try SharedMediaNativeAppPendingRows.one(h.context(), FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == id }))
    }
    private func allocation(_ h: Store, _ r: SharedMediaAcquisitionIntent) throws -> SharedMediaAllocationRecord {
        let id = r.assetID
        return try SharedMediaNativeAppPendingRows.one(h.context(), FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == id }))
    }
    private func released(_ h: Store, _ r: SharedMediaAcquisitionIntent) throws {
        guard case .released = try SharedMediaAcquisitionReceipt.read(receipt(h, r), expected: r) else { Issue.record("Missing terminal receipt"); return }
        let c = h.context(), id = r.operationID, asset = r.assetID
        #expect(try c.fetchCount(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == asset })) == 0)
        #expect(try c.fetchCount(FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == id })) == 0)
        #expect(try c.fetchCount(FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == id })) == 0)
        #expect(!FileManager.default.fileExists(atPath: file(h, r).path))
        #expect(!FileManager.default.fileExists(atPath: file(h, r, partial: true).path))
    }
}

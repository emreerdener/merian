import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native app original acquisition", .serialized)
@MainActor
struct SharedMediaNativeAppAcquisitionTests {
    typealias Store = SharedMediaNativeAppMetadataTests.Store
    @Test(arguments: [false, true])
    func firstAndExistingPackageRetainExactBytesAndReplayAfterRestart(_ existing: Bool) async throws {
        let h = try Store(), owner = try await h.open(), loader = Loader()
        let packageID = existing ? h.packageID : UUID(), bytes = PhotoPreparationTestHarness.image()
        let before = try await owner.inspectApp()
        let first = try await owner.prepareAppOriginal(packageID: packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        let result = try await owner.acquireAppOriginal(first) { await loader.load(bytes) }
        #expect(try Data(contentsOf: file(h, first)) == bytes)
        let second = try await owner.prepareAppOriginal(packageID: packageID, draftGeneration: h.draft, ordinal: 1, kind: .camera)
        _ = try await owner.acquireAppOriginal(second) { await loader.load(bytes) }
        #expect(try Data(contentsOf: file(h, second)) == bytes)
        #expect(try await owner.inspectApp().inventory.revision == before.inventory.revision + 4)
        #expect(try h.package(h.ordinaryID).supportingContextData == Data("ordinary-draft".utf8))
        #expect(try await owner.acquireAppOriginal(first) { await loader.load(Data()) } == result)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await reopen(h)
        #expect(try await cold.acquireAppOriginal(first) { await loader.load(Data()) } == result)
        #expect(await loader.calls == 2)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }
    @Test(arguments: ["beforeReservationSave", "afterReservationSave", "beforeCompletionSave", "afterCompletionSave"])
    func exactSaveRecoveryNeverRepeatsLoader(_ fault: String) async throws {
        let h = try Store(), owner = try await h.open(), loader = Loader(), bytes = PhotoPreparationTestHarness.image()
        let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        var fired = false
        try owner.setAcquisitionFault { point in
            if !fired && String(describing: point) == fault { fired = true; throw SharedMediaStorageFailure.unavailable }
        }
        if fault.hasPrefix("after") {
            let result = try await owner.acquireAppOriginal(request) { await loader.load(bytes) }
            #expect(try await owner.acquireAppOriginal(request) { await loader.load(Data()) } == result)
        } else {
            await #expect(throws: (any Error).self) { _ = try await owner.acquireAppOriginal(request) { await loader.load(bytes) } }
            if fault == "beforeCompletionSave" {
                #expect(try receipt(h, request) == .held(request))
                #expect(try Data(contentsOf: file(h, request)) == bytes)
                await #expect(throws: (any Error).self) { _ = try await owner.acquireAppOriginal(request) { await loader.load(bytes) } }
            } else { #expect(try receipt(h, request) == nil) }
        }
        let calls = await loader.calls
        #expect(fired && calls == (fault == "beforeReservationSave" ? 0 : 1))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    @Test(arguments: ["inventory", "package"])
    func staleRequestBlocksBeforeLoading(_ change: String) async throws {
        let h = try Store(), owner = try await h.open(), loader = Loader()
        let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        let context = h.context()
        switch change {
        case "bootstrap": try #require(try context.fetch(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()).first).revision += 1
        case "inventory": try #require(try context.fetch(FetchDescriptor<SharedMediaInventoryRecord>()).first).revision += 1
        case "member": try #require(try context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first).revision += 1
        default: try h.package(in: context).revision += 1
        }
        try context.save()
        await #expect(throws: (any Error).self) { _ = try await owner.acquireAppOriginal(request) { await loader.load(Data()) } }
        #expect(await loader.calls == 0)
        #expect(try receipt(h, request) == nil)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    @Test(arguments: ["bootstrap", "member", "consumer"])
    func freshPreSaveChecksRejectIndependentHeaderAndConsumerDrift(_ change: String) async throws {
        let h = try Store(receiving: change == "consumer")
        let owner: SharedMediaNativeOriginalOwner
        let consumerID: UUID?
        if change == "consumer" { (owner, consumerID) = try await h.openWithReceivingConsumer() }
        else { owner = try await h.open(); consumerID = nil }
        let loader = Loader()
        let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        try owner.setAcquisitionFault { point in
            guard point == .beforeReservationSave else { return }
            let context = h.context()
            if change == "bootstrap" { try #require(try context.fetch(FetchDescriptor<SharedMediaMembershipBootstrapRecord>()).first).revision += 1 }
            else if let consumerID { try #require(try SharedMediaConsumerLookup.one(context, id: consumerID)).revision += 1 }
            else { try #require(try context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>()).first(where: { $0.id == h.packageID })).revision += 1 }
            try context.save()
        }
        await #expect(throws: (any Error).self) { _ = try await owner.acquireAppOriginal(request) { await loader.load(Data()) } }
        #expect(await loader.calls == 0)
        #expect(try receipt(h, request) == nil)
        // External drift prevents proving a fresh-operation settlement; retain
        // its fences rather than treating the failed save as permission to reset.
        #expect(!(await owner.invalidateAndAwaitForAccountTransition()))
    }
    @Test func actualPendingConsumerAndOrdinaryDraftSurviveAcquisition() async throws {
        let h = try Store(receiving: true), (owner, consumerID) = try await h.openWithReceivingConsumer()
        let before = SharedMediaNativeAppMetadataFacts.Consumer(try #require(try SharedMediaConsumerLookup.one(h.context(), id: consumerID)))
        let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        let bytes = PhotoPreparationTestHarness.image()
        _ = try await owner.acquireAppOriginal(request) { bytes }
        let after = SharedMediaNativeAppMetadataFacts.Consumer(try #require(try SharedMediaConsumerLookup.one(h.context(), id: consumerID)))
        #expect(before == after)
        #expect(try await owner.inspectApp().consumers == 1)
        #expect(try h.package(h.ordinaryID).revision == 0)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    @Test func unknownReadbackRetainsFencesUntilExactSettlementThenColdReplay() async throws {
        let h = try Store(), owner = try await h.open(), loader = Loader(), bytes = PhotoPreparationTestHarness.image()
        let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        var unavailable = false
        try owner.setAcquisitionFault { point in
            if point == .afterCompletionSave { unavailable = true }
            if point == .beforeReadback && unavailable { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { _ = try await owner.acquireAppOriginal(request) { await loader.load(bytes) } }
        #expect(!(await owner.invalidateAndAwaitForAccountTransition()))
        await #expect(throws: (any Error).self) { _ = try await reopen(h) }
        try owner.setAcquisitionFault(nil)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let cold = try await reopen(h)
        _ = try await cold.acquireAppOriginal(request) { await loader.load(Data()) }
        #expect(await loader.calls == 1)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }
    @Test func accountDrainAwaitsRealLoaderAndColdReservationNeverReplaysIt() async throws {
        let h = try Store(), owner = try await h.open(), gate = Gate(), loader = Loader(), bytes = PhotoPreparationTestHarness.image()
        let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        let task = Task {
            do { return try await owner.acquireAppOriginal(request) { await gate.hold(); return await loader.load(bytes) } }
            catch { await gate.fail(); throw error }
        }
        guard await gate.wait() else { _ = await task.result; _ = await owner.invalidateAndAwaitForAccountTransition(); throw SharedMediaStorageFailure.unavailable }
        var closed = false
        let drain = Task { let result = await owner.invalidateAndAwaitForAccountTransition(); closed = true; return result }
        await Task.yield(); #expect(!closed)
        await gate.release()
        await #expect(throws: (any Error).self) { _ = try await task.value }
        #expect(await drain.value)
        #expect(try receipt(h, request) == .held(request))
        #expect(!FileManager.default.fileExists(atPath: file(h, request).path))
        let cold = try await reopen(h)
        await #expect(throws: (any Error).self) { _ = try await cold.acquireAppOriginal(request) { await loader.load(bytes) } }
        #expect(await loader.calls == 1)
        #expect(await cold.invalidateAndAwaitForAccountTransition())
    }
    @Test func missingReceiptAfterCopyCannotReleaseFencesOrStartAnotherLoader() async throws {
        let h = try Store(), owner = try await h.open(), loader = Loader(), bytes = PhotoPreparationTestHarness.image()
        let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        try owner.setAcquisitionFault { point in
            guard point == .afterOriginalWrite else { return }
            let context = h.context(), id = request.operationID
            let row = try #require(try context.fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id })).first)
            context.delete(row); try context.save()
        }
        await #expect(throws: (any Error).self) { _ = try await owner.acquireAppOriginal(request) { await loader.load(bytes) } }
        #expect(!(await owner.invalidateAndAwaitForAccountTransition()))
        #expect(try Data(contentsOf: file(h, request)) == bytes)
        #expect(await loader.calls == 1)
    }
    @Test func changedDestinationCannotBecomeCompletedOriginal() async throws {
        let h = try Store(), owner = try await h.open(), bytes = PhotoPreparationTestHarness.image()
        let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        try owner.setAcquisitionFault { point in
            guard point == .afterOriginalWrite else { return }
            let handle = try FileHandle(forWritingTo: file(h, request)); defer { try? handle.close() }
            try handle.seekToEnd(); try handle.write(contentsOf: Data([0]))
        }
        await #expect(throws: (any Error).self) { _ = try await owner.acquireAppOriginal(request) { bytes } }
        #expect(try receipt(h, request) == .held(request))
        let allocation = try #require(try h.context().fetch(FetchDescriptor<SharedMediaAllocationRecord>()).first)
        #expect(allocation.reservedBytes == request.maximumBytes && allocation.stateRaw == "p1Held")
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    @Test func reservationReadbackLossNeverInvokesLoaderAndCanSettleLater() async throws {
        let h = try Store(), owner = try await h.open(), loader = Loader()
        let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        var unavailable = false
        try owner.setAcquisitionFault { point in
            if point == .afterReservationSave { unavailable = true }
            if point == .beforeReadback && unavailable { throw SharedMediaStorageFailure.unavailable }
        }
        await #expect(throws: (any Error).self) { _ = try await owner.acquireAppOriginal(request) { await loader.load(Data()) } }
        #expect(await loader.calls == 0)
        #expect(!(await owner.invalidateAndAwaitForAccountTransition()))
        try owner.setAcquisitionFault(nil)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        #expect(try receipt(h, request) == .held(request))
    }
    @Test(arguments: ["reservation", "completion", "envelopeDrift"])
    func freshPackageSettlementRetainsExactReservationEnvelope(_ edge: String) async throws {
        let h = try Store(), owner = try await h.open(), loader = Loader()
        let request = try await owner.prepareAppOriginal(packageID: UUID(), draftGeneration: h.draft, ordinal: 0, kind: .picker)
        var savedEnvelope: Data?, unavailable = false
        try owner.setAcquisitionFault { point in
            if point == .afterReservationSave {
                savedEnvelope = try h.package(request.packageID).supportingContextData
                if edge == "reservation" { unavailable = true }
            }
            if edge != "reservation" && point == .beforeCompletionSave { unavailable = true }
            if unavailable && (point == .beforeReadback || point == .beforeCompletionSave) {
                throw SharedMediaStorageFailure.unavailable
            }
        }
        let bytes = PhotoPreparationTestHarness.image()
        await #expect(throws: (any Error).self) { _ = try await owner.acquireAppOriginal(request) { await loader.load(bytes) } }
        let exact = try #require(savedEnvelope)
        #expect(!(await owner.invalidateAndAwaitForAccountTransition()))
        #expect(try receipt(h, request) == .reserved(request))
        try owner.setAcquisitionFault(nil)
        if edge == "envelopeDrift" {
            // Semantically identical JSON must still fail the exact byte fence.
            let changed = Data([0x20]) + exact
            _ = try PhotoPreparationPolicy.decodeDraft(changed)
            let context = h.context()
            try h.package(request.packageID, in: context).supportingContextData = changed
            try context.save()
            #expect(!(await owner.invalidateAndAwaitForAccountTransition()))
            let restore = h.context()
            try h.package(request.packageID, in: restore).supportingContextData = exact
            try restore.save()
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        #expect(try receipt(h, request) == .held(request))
        #expect(try h.package(request.packageID).supportingContextData == exact)
        #expect(await loader.calls == (edge == "reservation" ? 0 : 1))
    }
    @Test(arguments: [SharedMediaNativeOriginalIOEntry.load, .write])
    func cancellationAtActualIOEntryStartsNoNewWork(_ entry: SharedMediaNativeOriginalIOEntry) async throws {
        let h = try Store(), owner = try await h.open(), gate = Gate(), loader = Loader(), bytes = PhotoPreparationTestHarness.image()
        let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        try await owner.setAcquisitionEntryPause { point in if point == entry { await gate.hold() } }
        let task = Task {
            do { return try await owner.acquireAppOriginal(request) { await loader.load(bytes) } }
            catch { await gate.fail(); throw error }
        }
        guard await gate.wait() else { _ = await task.result; _ = await owner.invalidateAndAwaitForAccountTransition(); throw SharedMediaStorageFailure.unavailable }
        task.cancel(); await gate.release()
        await #expect(throws: (any Error).self) { _ = try await task.value }
        #expect(await loader.calls == (entry == .load ? 0 : 1))
        #expect(try receipt(h, request) == .held(request))
        #expect(!FileManager.default.fileExists(atPath: file(h, request).path))
        #expect(!FileManager.default.fileExists(atPath: file(h, request).appendingPathExtension("partial").path))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    @Test(arguments: ["package", "member", "heldPackage", "heldMember"])
    func settlementCannotAcknowledgeTargetDrift(_ change: String) async throws {
        let h = try Store(), owner = try await h.open(), loader = Loader(), bytes = PhotoPreparationTestHarness.image()
        let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        let held = change.hasPrefix("held")
        try owner.setAcquisitionFault { point in
            guard point == (held ? .afterHeldSave : .afterCompletionSave) else { return }
            let context = h.context()
            if change.lowercased().contains("member") {
                let id = request.packageID
                try #require(try context.fetch(FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id })).first).revision += 1
            } else { try h.package(in: context).supportingContextData = PhotoPreparationPolicy.encodeDraft(contexts: [.init(freeText: "unexpected drift")]) }
            try context.save()
        }
        await #expect(throws: (any Error).self) {
            _ = try await owner.acquireAppOriginal(request) { await loader.load(held ? Data() : bytes) }
        }
        #expect(!(await owner.invalidateAndAwaitForAccountTransition()))
        #expect(await loader.calls == 1)
    }
    @Test(arguments: [false, true])
    func freshAnchoredWorkDriftBlocksReservationWithoutTouchingOrdinaryRows(_ unmemberedPair: Bool) async throws {
        let h = try Store(receiving: true), (owner, consumerID) = try await h.openWithReceivingConsumer(), loader = Loader()
        let consumer = try #require(try SharedMediaConsumerLookup.one(h.context(), id: consumerID))
        let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        try owner.setAcquisitionFault { point in
            guard point == .beforeReservationSave else { return }
            let context = h.context(), packageID = consumer.packageID
            let pair = try #require(try context.fetch(FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.packageID == packageID })).first)
            let pairID = pair.id
            let work = try #require(try context.fetch(FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.pairID == pairID })).first)
            if unmemberedPair {
                context.insert(SharedMediaDerivativePairRecord(id: UUID(), nonce: UUID(), inventoryID: pair.inventoryID,
                    inventoryGeneration: pair.inventoryGeneration, expectedInventoryRevision: pair.expectedInventoryRevision,
                    ownerID: pair.ownerID, packageID: UUID(), draftGeneration: UUID(), originalReferenceID: UUID(),
                    originalReferenceRevision: 0, originalAssetID: UUID(), originalAssetGeneration: UUID(), ordinal: 0,
                    expectedPackageRevision: 0, aiWorkID: UUID(), displayWorkID: UUID()))
            } else { work.phaseRaw = "reserved" }
            try context.save()
        }
        await #expect(throws: (any Error).self) { _ = try await owner.acquireAppOriginal(request) { await loader.load(Data()) } }
        #expect(await loader.calls == 0)
        #expect(try receipt(h, request) == nil)
        #expect(try h.package(h.ordinaryID).revision == 0)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    @Test func proposedIdentityCollisionsAndHeaderDriftFailReadOnlyAudit() async throws {
        let h = try Store(), owner = try await h.open()
        let request = try await owner.prepareAppOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .picker)
        let context = h.context()
        context.insert(PhotoPreparationAsset(id: request.referenceID, ownerID: h.ownerID, generation: UUID(), fileToken: "test-only",
            contentType: "image/jpeg", byteCount: 1, sha256: String(repeating: "a", count: 64), acquisitionKindRaw: "picker", cleanupStateRaw: "ready"))
        try context.save()
        await #expect(throws: (any Error).self) { try await SharedMediaNativeAppAcquisitionIdentity.audit(request, container: h.container, check: {}) }
        await #expect(throws: (any Error).self) { try await SharedMediaNativeAppAcquisitionIdentity.audit(request, container: h.container, check: { throw SharedMediaStorageFailure.stale }) }
        #expect(try receipt(h, request) == nil)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
    private func reopen(_ h: Store) async throws -> SharedMediaNativeOriginalOwner {
        let owner = try SharedMediaNativeOriginalOwner.appDispatch(account: PhotoOriginalPreparationOwner.syntheticAccount(ownerID: h.ownerID, runtime: h.runtime), drain: .init())
        _ = try await owner.openApp(container: h.container, parent: h.parent, inventoryID: h.inventoryID); return owner
    }
    private func file(_ h: Store, _ request: SharedMediaAcquisitionIntent) -> URL {
        h.parent.appendingPathComponent("photo/PhotoPreparation").appendingPathComponent(request.finalToken)
    }
    private func receipt(_ h: Store, _ request: SharedMediaAcquisitionIntent) throws -> SharedMediaAcquisitionReceipt? {
        let id = request.operationID
        return try h.context().fetch(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id })).first.map { try SharedMediaAcquisitionReceipt.read($0, expected: request) }
    }
    private actor Loader {
        private(set) var calls = 0
        func load(_ bytes: Data) -> Data { calls += 1; return bytes }
    }
    private actor Gate {
        private var waiter: CheckedContinuation<Void, Never>?, entry: CheckedContinuation<Bool, Never>?
        private var entered = false, failed = false
        func hold() async { await withCheckedContinuation { waiter = $0; entered = true; entry?.resume(returning: true); entry = nil } }
        func wait() async -> Bool { if entered { return true }; if failed { return false }; return await withCheckedContinuation { entry = $0 } }
        func fail() { failed = true; entry?.resume(returning: false); entry = nil }
        func release() { waiter?.resume(); waiter = nil }
    }
}

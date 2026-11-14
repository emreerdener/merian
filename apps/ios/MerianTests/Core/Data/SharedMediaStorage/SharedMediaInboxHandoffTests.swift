import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Joint inbox photo handoff", .serialized)
@MainActor
struct SharedMediaInboxHandoffTests {
    enum Fault: Error { case injected }

    @Test func exactCopyReplayAndSourceReleasePreserveDestination() async throws {
        let h = try Harness(), owner = try h.owner(), data = PhotoPreparationTestHarness.image()
        let source = try await owner.stage { data }, request = try h.request(owner, source)
        let handle = try await owner.handoff(request, account: h.account)
        #expect(try await owner.handoff(request, account: h.account) == handle)
        #expect(try await owner.originalData(source) == data)
        #expect(try await owner.destinationOriginalData(handle, account: h.account) == data)
        let allocations = try h.context().fetch(FetchDescriptor<SharedMediaAllocationRecord>())
        #expect(allocations.count == 2 && allocations.allSatisfy { $0.materializedBytes == data.count && $0.reservedBytes == 0 })
        await #expect(throws: (any Error).self) { try await owner.discard(source) }
        try await owner.retireHandoffSource(request, account: h.account)
        #expect(try owner.catalog().isEmpty)
        #expect(try await owner.destinationOriginalData(handle, account: h.account) == data)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaInboxHandoffRecord>()) == 0)
        #expect(try h.context().fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 1)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaLeaseRecord>()) == 1)
        await #expect(throws: (any Error).self) { _ = try await owner.handoff(request, account: h.account) }
    }

    @Test(arguments: [SharedMediaInboxHandoffBoundary.afterReservationSave, .afterIdentitySave, .afterCompletionSave])
    func lostAcknowledgementsUseExactReadback(_ point: SharedMediaInboxHandoffBoundary) async throws {
        let h = try Harness(), owner = try h.owner(), bytes = PhotoPreparationTestHarness.image()
        let source = try await owner.stage { bytes }, request = try h.request(owner, source)
        owner.setHandoffFault { if $0 == point { throw Fault.injected } }
        let result = try await owner.handoff(request, account: h.account)
        #expect(try await owner.destinationOriginalData(result, account: h.account) == bytes)
        #expect(try h.context().fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 1)
    }

    @Test func failedReservationCreatesNoDestinationOrHold() async throws {
        let h = try Harness(), owner = try h.owner(), bytes = PhotoPreparationTestHarness.image()
        let source = try await owner.stage { bytes }, request = try h.request(owner, source)
        owner.setHandoffFault { if $0 == .beforeReservationSave { throw Fault.injected } }
        await #expect(throws: (any Error).self) { _ = try await owner.handoff(request, account: h.account) }
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaInboxHandoffRecord>()) == 0)
        #expect(try h.context().fetchCount(FetchDescriptor<PhotoPreparationRecord>()) == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.photo.appendingPathComponent("PhotoPreparation").path).isEmpty)
        #expect(try await owner.originalData(source) == bytes)
    }

    @Test(arguments: [SharedMediaInboxHandoffBoundary.afterRename, .beforeCompletionSave])
    func originalWriteRecoversAfterReopen(_ point: SharedMediaInboxHandoffBoundary) async throws {
        let h = try Harness(), bytes = PhotoPreparationTestHarness.image()
        var owner: SharedMediaInboxOwner? = try h.owner()
        let source = try await owner!.stage { bytes }, request = try h.request(owner!, source)
        if point == .afterRename { await owner!.setHandoffFileFault { if $0 == point { throw Fault.injected } } }
        else { owner!.setHandoffFault { if $0 == point { throw Fault.injected } } }
        await #expect(throws: (any Error).self) { _ = try await owner!.handoff(request, account: h.account) }
        owner = nil
        let reopened = try h.owner()
        #expect(try await reopened.recoverHandoffs(account: h.account) == [.completed(request, request.handle)])
        #expect(try await reopened.destinationOriginalData(request.handle, account: h.account) == bytes)
        #expect(try await reopened.originalData(source) == bytes)
    }

    @Test func incompleteAbandonmentRetainsSourceAndOriginalAccountDraft() async throws {
        let h = try Harness(), bytes = padded(131_072), other = h.otherAccount
        var owner: SharedMediaInboxOwner? = try h.owner()
        let source = try await owner!.stage { bytes }, request = try h.request(owner!, source)
        await owner!.setHandoffFileFault { if $0 == .duringWrite { throw Fault.injected } }
        await #expect(throws: (any Error).self) { _ = try await owner!.handoff(request, account: h.account) }
        owner = nil
        let reopened = try h.owner()
        #expect(try await reopened.recoverHandoffs(account: other).isEmpty)
        #expect(try await reopened.recoverHandoffs(account: h.account) == [.incomplete(request)])
        let before = try #require(h.context().fetch(FetchDescriptor<PhotoPreparationRecord>()).first)
        let phase = before.phaseRaw, revision = before.revision
        reopened.setHandoffAvailableBytes(0)
        try await reopened.abandonHandoff(request)
        let after = try #require(h.context().fetch(FetchDescriptor<PhotoPreparationRecord>()).first)
        #expect(after.phaseRaw == phase && after.revision == revision)
        #expect(try await reopened.originalData(source) == bytes)
        let lease = try #require(h.context().fetch(FetchDescriptor<PhotoPreparationLease>()).first)
        #expect(lease.writerStateRaw == "closedNeedsAttention" && lease.allocatedByteCount == 0 && lease.sourceIdentity == nil)
        let allocation = try #require(h.context().fetch(FetchDescriptor<SharedMediaAllocationRecord>()).first { $0.id == request.assetID })
        #expect(allocation.materializedBytes == 65_536 && allocation.reservedBytes == Int64(bytes.count) - 65_536)
        await #expect(throws: PhotoPreparationFailure.accountChanged) { try await reopened.discardDetachedHandoff(request, account: other) }
        try await reopened.discard(source)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaInboxSourceRecord>()) == 0)
        // Detached provenance must remain valid after its source is reclaimed.
        try await reopened.discardDetachedHandoff(request, account: h.account)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaInboxHandoffRecord>()) == 0)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.photo.appendingPathComponent("PhotoPreparation").path).isEmpty)
    }

    @Test func completedAbandonmentKeepsBothCopiesAndTheirOwners() async throws {
        let h = try Harness(), owner = try h.owner(), bytes = PhotoPreparationTestHarness.image()
        let source = try await owner.stage { bytes }, request = try h.request(owner, source)
        let destination = try await owner.handoff(request, account: h.account)
        owner.setHandoffAvailableBytes(0)
        try await owner.abandonHandoff(request)
        let blocked = try h.request(owner, source)
        await #expect(throws: SharedMediaStorageFailure.capacity) { _ = try await owner.handoff(blocked, account: h.account) }
        owner.setHandoffAvailableBytes(nil)
        #expect(try await owner.originalData(source) == bytes)
        #expect(try await owner.destinationOriginalData(destination, account: h.account) == bytes)
        #expect(try h.context().fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaLeaseRecord>()) == 2)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaInboxHandoffRecord>()) == 0)
        await #expect(throws: (any Error).self) { _ = try await owner.handoff(request, account: h.account) }
        let fresh = try h.request(owner, source, account: h.otherAccount)
        let other = try await owner.handoff(fresh, account: h.otherAccount)
        #expect(try await owner.destinationOriginalData(other, account: h.otherAccount) == bytes)
        await #expect(throws: PhotoPreparationFailure.accountChanged) { _ = try await owner.destinationOriginalData(destination, account: h.otherAccount) }
    }

    @Test func alteredReplayCannotSubstituteIdentities() async throws {
        let h = try Harness(), owner = try h.owner(), bytes = PhotoPreparationTestHarness.image()
        let source = try await owner.stage { bytes }, request = try h.request(owner, source)
        _ = try await owner.handoff(request, account: h.account)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        for key in ["nonce", "packageID", "assetID", "leaseID", "sourceHoldID"] {
            var changed = json; changed[key] = UUID().uuidString
            let altered = try JSONDecoder().decode(SharedMediaInboxHandoffRequest.self, from: JSONSerialization.data(withJSONObject: changed))
            await #expect(throws: (any Error).self) { _ = try await owner.handoff(altered, account: h.account) }
        }
        json["byteCount"] = bytes.count + 1
        let altered = try JSONDecoder().decode(SharedMediaInboxHandoffRequest.self, from: JSONSerialization.data(withJSONObject: json))
        await #expect(throws: (any Error).self) { _ = try await owner.handoff(altered, account: h.account) }
        #expect(try h.context().fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 1)
    }

    @Test func unidentifiedPartialCannotBeAdoptedOrDiscarded() async throws {
        let h = try Harness(), owner = try h.owner(), bytes = PhotoPreparationTestHarness.image()
        let source = try await owner.stage { bytes }, request = try h.request(owner, source)
        owner.setHandoffFault { if $0 == .beforeIdentitySave { throw Fault.injected } }
        await #expect(throws: (any Error).self) { _ = try await owner.handoff(request, account: h.account) }
        owner.setHandoffFault(nil)
        #expect(try await owner.recoverHandoffs(account: h.account) == [.conflict(request)])
        await #expect(throws: (any Error).self) { try await owner.abandonHandoff(request) }
        #expect(try await owner.originalData(source) == bytes)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaInboxHandoffRecord>()) == 1)
    }

    @Test func sourceReleaseFaultKeepsDestinationPinnedAcrossReopen() async throws {
        let h = try Harness(), bytes = PhotoPreparationTestHarness.image()
        var owner: SharedMediaInboxOwner? = try h.owner()
        let source = try await owner!.stage { bytes }, request = try h.request(owner!, source)
        _ = try await owner!.handoff(request, account: h.account)
        await owner!.setFileFault { if $0 == .afterFinalUnlink { throw Fault.injected } }
        await #expect(throws: (any Error).self) { try await owner!.retireHandoffSource(request, account: h.account) }
        await #expect(throws: (any Error).self) { try await owner!.abandonHandoff(request) }
        owner = nil
        let reopened = try h.owner()
        #expect(try await reopened.recover().isEmpty)
        #expect(try await reopened.destinationOriginalData(request.handle, account: h.account) == bytes)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaInboxHandoffRecord>()) == 0)
    }

    @Test func repeatedAbandonmentCannotExceedAcquisitionBudget() async throws {
        let h = try Harness(), owner = try h.owner(), bytes = padded(32 * 1_024 * 1_024)
        let source = try await owner.stage { bytes }
        await owner.setHandoffFileFault { if $0 == .duringWrite { throw Fault.injected } }
        let first = try h.request(owner, source)
        await #expect(throws: (any Error).self) { _ = try await owner.handoff(first, account: h.account) }
        try await owner.abandonHandoff(first)
        let second = try h.request(owner, source)
        await #expect(throws: (any Error).self) { _ = try await owner.handoff(second, account: h.account) }
        await #expect(throws: SharedMediaStorageFailure.capacity) { try await owner.abandonHandoff(second) }
        #expect(try h.context().fetch(FetchDescriptor<SharedMediaReferenceRecord>()).filter { $0.roleRaw == SharedMediaInboxHandoffLedger.holdRole }.count == 1)
        await owner.setHandoffFileFault(nil)
        try await owner.discardDetachedHandoff(first, account: h.account)
        try await owner.abandonHandoff(second)
        try await owner.discardDetachedHandoff(second, account: h.account)
        try await owner.discard(source)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 0)
    }

    @Test func cancellationDrainsDestinationBeforeReturningItsSource() async throws {
        let h = try Harness(), bytes = PhotoPreparationTestHarness.image(), gate = Gate()
        var owner: SharedMediaInboxOwner? = try h.owner()
        let source = try await owner!.stage { bytes }, request = try h.request(owner!, source)
        await owner!.setHandoffPause { await gate.wait() }
        let work = Task { try await owner!.handoff(request, account: h.account) }
        await gate.started()
        let drain = Task { await owner!.suspendAndDrain() }
        await Task.yield()
        #expect(throws: (any Error).self) { try h.owner() }
        await #expect(throws: SharedMediaStorageFailure.busy) { try await owner!.abandonHandoff(request) }
        await gate.release(); _ = await work.result; await drain.value
        owner = nil
        let reopened = try h.owner()
        try await reopened.abandonHandoff(request)
        #expect(try await reopened.originalData(source) == bytes)
        try await reopened.discardDetachedHandoff(request, account: h.account)
    }

    @Test func accountChangeAfterCommitDoesNotRollBackOrReleaseSource() async throws {
        let h = try Harness(), owner = try h.owner(), bytes = PhotoPreparationTestHarness.image()
        var current = true
        let base = h.account
        let access = PhotoOriginalPreparationOwner.AccountAccess(ownerID: base.ownerID, begin: base.begin,
            isCurrent: { current && base.isCurrent($0) }, finish: base.finish)
        let source = try await owner.stage { bytes }, request = try h.request(owner, source, account: access)
        owner.setHandoffFault { if $0 == .afterCompletionSave { current = false; throw Fault.injected } }
        await #expect(throws: PhotoPreparationFailure.accountChanged) { _ = try await owner.handoff(request, account: access) }
        #expect(try h.context().fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 1)
        #expect(try await owner.originalData(source) == bytes)
        owner.setHandoffFault(nil)
        #expect(try await owner.recoverHandoffs(account: h.account) == [.completed(request, request.handle)])
    }

    @Test(arguments: [SharedMediaInboxHandoffBoundary.afterUnlink, .beforeReleaseSave, .afterReleaseSave])
    func detachedDeletionRetainsIntentUntilAbsenceAcknowledgement(_ point: SharedMediaInboxHandoffBoundary) async throws {
        let h = try Harness(), bytes = padded(131_072)
        var owner: SharedMediaInboxOwner? = try h.owner()
        let source = try await owner!.stage { bytes }, request = try h.request(owner!, source)
        await owner!.setHandoffFileFault { if $0 == .duringWrite { throw Fault.injected } }
        await #expect(throws: (any Error).self) { _ = try await owner!.handoff(request, account: h.account) }
        try await owner!.abandonHandoff(request)
        await owner!.setHandoffFileFault { if $0 == point { throw Fault.injected } }
        owner!.setHandoffFault { if $0 == point { throw Fault.injected } }
        if point == .afterReleaseSave { try await owner!.discardDetachedHandoff(request, account: h.account) }
        else { await #expect(throws: (any Error).self) { try await owner!.discardDetachedHandoff(request, account: h.account) } }
        owner = nil
        let reopened = try h.owner()
        if point != .afterReleaseSave { try await reopened.discardDetachedHandoff(request, account: h.account) }
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaInboxHandoffRecord>()) == 0)
        #expect(try await reopened.originalData(source) == bytes)
    }

    private func padded(_ size: Int) -> Data {
        var result = PhotoPreparationTestHarness.image()
        result.append(Data(repeating: 0, count: size - result.count)); return result
    }

    private actor Gate {
        var began = false
        var continuation: CheckedContinuation<Void, Never>?
        func wait() async { began = true; await withCheckedContinuation { continuation = $0 } }
        func started() async { while !began { await Task.yield() } }
        func release() { continuation?.resume(); continuation = nil }
    }

    @MainActor private struct Harness {
        let base: URL, authority: URL, inbox: URL, photo: URL
        let container: ModelContainer
        let inventory = UUID(), accountID = UUID(), otherID = UUID(), runtime = AuthRuntimeState()
        var account: PhotoOriginalPreparationOwner.AccountAccess { PhotoOriginalPreparationOwner.syntheticAccount(ownerID: accountID, runtime: runtime) }
        var otherAccount: PhotoOriginalPreparationOwner.AccountAccess { PhotoOriginalPreparationOwner.syntheticAccount(ownerID: otherID, runtime: runtime) }
        init() throws {
            base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("shared-handoff-" + UUID().uuidString)
            authority = base.appendingPathComponent("authority"); inbox = base.appendingPathComponent("inbox"); photo = base.appendingPathComponent("photo")
            let db = base.appendingPathComponent("database")
            for root in [authority, inbox, photo, db] { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
            let schema = Schema(versionedSchema: CurrentSchema.self)
            container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: db.appendingPathComponent("ledger.store"), cloudKitDatabase: .none)])
        }
        func owner() throws -> SharedMediaInboxOwner { try .init(container: container, authorityRoot: authority, inboxRoot: inbox, photoRoot: photo, inventoryID: inventory) }
        func context() -> ModelContext { ModelContext(container) }
        func request(_ owner: SharedMediaInboxOwner, _ source: SharedMediaInboxHandle,
                     account: PhotoOriginalPreparationOwner.AccountAccess? = nil) throws -> SharedMediaInboxHandoffRequest {
            try owner.prepareHandoff(source, account: account ?? self.account, packageID: UUID(), draftGeneration: UUID())
        }
    }
}

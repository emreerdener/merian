import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Joint photo derivative lifecycle", .serialized)
@MainActor
struct SharedMediaDerivativeTests {
    enum Fault: Error { case injected }

    @Test func pairPublicationReplayReplacementAndDiscardPreserveOriginal() async throws {
        let h = try Harness(), owner = try h.owner(), data = PhotoPreparationTestHarness.image()
        let original = try await original(h, owner, data)
        let request = try await owner.prepareDerivatives(original, ai: data, display: data, account: h.account)
        let receipt = try await owner.replaceDerivatives(request, ai: data, display: data, account: h.account)
        #expect(receipt.ai.assetID != receipt.display.assetID && receipt.original.assetID != receipt.ai.assetID)
        #expect(try await owner.replaceDerivatives(request, ai: Data(), display: Data(), account: h.account) == receipt)
        #expect(try h.context().fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0)
        let next = try await owner.prepareDerivatives(original, ai: data, display: data, account: h.account)
        let updated = try await owner.replaceDerivatives(next, ai: data, display: data, account: h.account)
        #expect(updated.publishedRevision == receipt.publishedRevision + 2)
        #expect(try h.context().fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 3)
        await #expect(throws: (any Error).self) { _ = try await owner.replaceDerivatives(request, ai: data, display: data, account: h.account) }
        owner.setHandoffAvailableBytes(0)
        try await owner.discardDerivatives(next, account: h.account)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>()) == 0)
        #expect(try h.context().fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 1)
        #expect(try await owner.destinationOriginalData(original, account: h.account) == data)
        await #expect(throws: (any Error).self) { _ = try await owner.replaceDerivatives(next, ai: data, display: data, account: h.account) }
    }

    @Test(arguments: [SharedMediaInboxHandoffBoundary.afterPairPlanSave, .afterReservationSave, .afterIdentitySave, .afterCompletionSave, .afterPairPublishSave])
    func lostSaveAcknowledgementsReconcileExactPair(_ point: SharedMediaInboxHandoffBoundary) async throws {
        let h = try Harness(), owner = try h.owner(), data = PhotoPreparationTestHarness.image()
        let original = try await original(h, owner, data)
        let request = try await owner.prepareDerivatives(original, ai: data, display: data, account: h.account)
        owner.setHandoffFault { if $0 == point { throw Fault.injected } }
        let receipt = try await owner.replaceDerivatives(request, ai: data, display: data, account: h.account)
        #expect(try await owner.readyDerivatives(request, account: h.account) == receipt)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 3)
    }

    @Test(arguments: [0, 1, 2])
    func incompletePairIsNeverPublishedAndWholePairCanBeDiscarded(_ completed: Int) async throws {
        let h = try Harness(), data = PhotoPreparationTestHarness.image()
        var owner: SharedMediaInboxOwner? = try h.owner()
        let handle = try await original(h, owner!, data)
        let request = try await owner!.prepareDerivatives(handle, ai: data, display: data, account: h.account)
        var completions = 0
        owner!.setHandoffFault { point in
            if point == .beforeCompletionSave { if completions == completed { throw Fault.injected }; completions += 1 }
            if point == .beforePairPublishSave && completed == 2 { throw Fault.injected }
        }
        await #expect(throws: (any Error).self) { _ = try await owner!.replaceDerivatives(request, ai: data, display: data, account: h.account) }
        await #expect(throws: (any Error).self) { _ = try await owner!.readyDerivatives(request, account: h.account) }
        #expect(try h.context().fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 1 + completed)
        owner = nil
        let reopened = try h.owner()
        reopened.setHandoffAvailableBytes(0)
        try await reopened.discardDerivatives(request, account: h.account)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaDerivativeWorkRecord>()) == 0)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 1)
        #expect(try await reopened.destinationOriginalData(handle, account: h.account) == data)
    }

    @Test func restartRecoversOnlyCompleteFilesWithoutAnotherPreparation() async throws {
        let h = try Harness(), data = PhotoPreparationTestHarness.image()
        var owner: SharedMediaInboxOwner? = try h.owner()
        let handle = try await original(h, owner!, data)
        let request = try await owner!.prepareDerivatives(handle, ai: data, display: data, account: h.account)
        var completed = 0
        owner!.setHandoffFault { point in
            if point == .beforeCompletionSave { completed += 1; if completed == 2 { throw Fault.injected } }
        }
        await #expect(throws: (any Error).self) { _ = try await owner!.replaceDerivatives(request, ai: data, display: data, account: h.account) }
        owner = nil
        let reopened = try h.owner()
        let result = try await reopened.recoverDerivatives(account: h.account)
        guard case .ready(let receipt) = try #require(result.first) else { Issue.record("Complete pair did not recover"); return }
        #expect(receipt.pairID == request.id)
        #expect(try await reopened.readyDerivatives(request, account: h.account) == receipt)
    }

    @Test func shortWriteRemainsHeldAndCannotBeResubmitted() async throws {
        let h = try Harness(), data = padded(131_072), owner = try h.owner()
        let handle = try await original(h, owner, data)
        let request = try await owner.prepareDerivatives(handle, ai: data, display: data, account: h.account)
        await owner.setHandoffFileFault { if $0 == .duringWrite { throw Fault.injected } }
        await #expect(throws: (any Error).self) { _ = try await owner.replaceDerivatives(request, ai: data, display: data, account: h.account) }
        await owner.setHandoffFileFault(nil)
        #expect(try await owner.recoverDerivatives(account: h.account) == [.incomplete(request)])
        await #expect(throws: (any Error).self) { _ = try await owner.replaceDerivatives(request, ai: data, display: data, account: h.account) }
        let allocations = try h.context().fetch(FetchDescriptor<SharedMediaAllocationRecord>()).filter { $0.stateRaw.hasPrefix("p1Derivative") }
        #expect(allocations.count == 2 && allocations.reduce(Int64(0)) { $0 + $1.reservedBytes + $1.materializedBytes } == 2 * data.count)
        try await owner.discardDerivatives(request, account: h.account)
    }

    @Test(arguments: [SharedMediaInboxHandoffBoundary.afterPartialCreate, .beforeIdentitySave])
    func unidentifiedPartialStaysChargedAndCannotBeAdopted(_ point: SharedMediaInboxHandoffBoundary) async throws {
        let h = try Harness(), owner = try h.owner(), data = PhotoPreparationTestHarness.image()
        let handle = try await original(h, owner, data)
        let request = try await owner.prepareDerivatives(handle, ai: data, display: data, account: h.account)
        owner.setHandoffFault { if $0 == point { throw Fault.injected } }
        await owner.setHandoffFileFault { if $0 == point { throw Fault.injected } }
        await #expect(throws: (any Error).self) { _ = try await owner.replaceDerivatives(request, ai: data, display: data, account: h.account) }
        owner.setHandoffFault(nil); await owner.setHandoffFileFault(nil)
        #expect(try await owner.recoverDerivatives(account: h.account) == [.conflict(request)])
        await #expect(throws: (any Error).self) { try await owner.discardDerivatives(request, account: h.account) }
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 3)
    }

    @Test func plannedReplacementReopensForDiscardAndNeverRestartsEncoding() async throws {
        let h = try Harness(), data = PhotoPreparationTestHarness.image()
        var owner: SharedMediaInboxOwner? = try h.owner()
        let handle = try await original(h, owner!, data)
        let first = try await owner!.prepareDerivatives(handle, ai: data, display: data, account: h.account)
        _ = try await owner!.replaceDerivatives(first, ai: data, display: data, account: h.account)
        let next = try await owner!.prepareDerivatives(handle, ai: data, display: data, account: h.account)
        owner!.setHandoffFault { if $0 == .beforeReservationSave { throw Fault.injected } }
        await #expect(throws: (any Error).self) { _ = try await owner!.replaceDerivatives(next, ai: data, display: data, account: h.account) }
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 1)
        owner = nil
        let reopened = try h.owner()
        #expect(try await reopened.recoverDerivatives(account: h.account) == [.incomplete(next)])
        await #expect(throws: (any Error).self) { _ = try await reopened.replaceDerivatives(next, ai: data, display: data, account: h.account) }
        try await reopened.discardDerivatives(next, account: h.account)
        #expect(try await reopened.destinationOriginalData(handle, account: h.account) == data)
    }

    @Test(arguments: [SharedMediaInboxHandoffBoundary.afterUnlink, .beforeReleaseSave, .afterReleaseSave])
    func deletionAcknowledgementRequiresBothFilesAbsent(_ point: SharedMediaInboxHandoffBoundary) async throws {
        let h = try Harness(), data = PhotoPreparationTestHarness.image()
        var owner: SharedMediaInboxOwner? = try h.owner()
        let handle = try await original(h, owner!, data)
        let request = try await owner!.prepareDerivatives(handle, ai: data, display: data, account: h.account)
        _ = try await owner!.replaceDerivatives(request, ai: data, display: data, account: h.account)
        owner!.setHandoffFault { if $0 == point { throw Fault.injected } }
        await owner!.setHandoffFileFault { if $0 == point { throw Fault.injected } }
        if point == .afterReleaseSave { try await owner!.discardDerivatives(request, account: h.account) }
        else { await #expect(throws: (any Error).self) { try await owner!.discardDerivatives(request, account: h.account) } }
        owner = nil
        let reopened = try h.owner()
        if point != .afterReleaseSave { try await reopened.discardDerivatives(request, account: h.account) }
        #expect(try h.context().fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 1)
        #expect(try await reopened.destinationOriginalData(handle, account: h.account) == data)
    }

    @Test func invalidPayloadOrWrongAccountCannotRetireCurrentPair() async throws {
        let h = try Harness(), owner = try h.owner(), data = PhotoPreparationTestHarness.image()
        let handle = try await original(h, owner, data)
        let first = try await owner.prepareDerivatives(handle, ai: data, display: data, account: h.account)
        let receipt = try await owner.replaceDerivatives(first, ai: data, display: data, account: h.account)
        let next = try await owner.prepareDerivatives(handle, ai: data, display: data, account: h.account)
        await #expect(throws: (any Error).self) { _ = try await owner.replaceDerivatives(next, ai: data, display: Data(), account: h.account) }
        await #expect(throws: PhotoPreparationFailure.accountChanged) { try await owner.discardDerivatives(first, account: h.otherAccount) }
        #expect(try await owner.readyDerivatives(first, account: h.account) == receipt)
    }

    @Test func capacityFailureSavesNoHalfReservationAndAllowsLowDiskDiscard() async throws {
        let h = try Harness(), owner = try h.owner(), data = PhotoPreparationTestHarness.image()
        let handle = try await original(h, owner, data)
        let request = try await owner.prepareDerivatives(handle, ai: data, display: data, account: h.account)
        owner.setHandoffAvailableBytes(0)
        await #expect(throws: SharedMediaStorageFailure.capacity) { _ = try await owner.replaceDerivatives(request, ai: data, display: data, account: h.account) }
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 1)
        #expect(try h.context().fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0)
        try await owner.discardDerivatives(request, account: h.account)
        #expect(try await owner.destinationOriginalData(handle, account: h.account) == data)
    }

    @Test func cancellationRetainsFencesUntilActualWriterDrain() async throws {
        let h = try Harness(), data = PhotoPreparationTestHarness.image(), gate = Gate()
        var owner: SharedMediaInboxOwner? = try h.owner()
        let handle = try await original(h, owner!, data)
        let request = try await owner!.prepareDerivatives(handle, ai: data, display: data, account: h.account)
        await owner!.setHandoffPause { await gate.wait() }
        let task = Task { try await owner!.replaceDerivatives(request, ai: data, display: data, account: h.account) }
        await gate.started()
        let drain = Task { await owner!.suspendAndDrain() }
        await Task.yield()
        #expect(throws: (any Error).self) { try h.owner() }
        await #expect(throws: SharedMediaStorageFailure.busy) { try await owner!.discardDerivatives(request, account: h.account) }
        await gate.release(); _ = await task.result; await drain.value
        owner = nil
        let reopened = try h.owner()
        try await reopened.discardDerivatives(request, account: h.account)
        #expect(try await reopened.destinationOriginalData(handle, account: h.account) == data)
    }

    @Test func accountLossAfterFirstCompletionCannotPublishOrDelete() async throws {
        let h = try Harness(), owner = try h.owner(), data = PhotoPreparationTestHarness.image()
        let handle = try await original(h, owner, data)
        let base = h.account
        var current = true
        let account = PhotoOriginalPreparationOwner.AccountAccess(ownerID: base.ownerID, begin: base.begin,
            isCurrent: { current && base.isCurrent($0) }, finish: base.finish)
        let request = try await owner.prepareDerivatives(handle, ai: data, display: data, account: account)
        owner.setHandoffFault { if $0 == .afterCompletionSave { current = false; throw Fault.injected } }
        await #expect(throws: PhotoPreparationFailure.accountChanged) { _ = try await owner.replaceDerivatives(request, ai: data, display: data, account: account) }
        #expect(try h.context().fetchCount(FetchDescriptor<PhotoPreparationAsset>()) == 2)
        let token = handle.ownerID.uuidString.lowercased() + "/" + handle.packageID.uuidString.lowercased() + "/" + request.display.assetID.uuidString.lowercased()
        #expect(!FileManager.default.fileExists(atPath: h.photo.appendingPathComponent("PhotoPreparation").appendingPathComponent(token + ".partial").path))
        owner.setHandoffFault(nil)
        await #expect(throws: PhotoPreparationFailure.accountChanged) { try await owner.discardDerivatives(request, account: account) }
        try await owner.discardDerivatives(request, account: h.account)
    }

    @Test func missingDerivativeBlocksReadyButExplicitDiscardPreservesOriginal() async throws {
        let h = try Harness(), owner = try h.owner(), data = PhotoPreparationTestHarness.image()
        let handle = try await original(h, owner, data)
        let request = try await owner.prepareDerivatives(handle, ai: data, display: data, account: h.account)
        let receipt = try await owner.replaceDerivatives(request, ai: data, display: data, account: h.account)
        try FileManager.default.removeItem(at: h.photo.appendingPathComponent("PhotoPreparation").appendingPathComponent(receipt.ai.token))
        await #expect(throws: (any Error).self) { _ = try await owner.readyDerivatives(request, account: h.account) }
        try await owner.discardDerivatives(request, account: h.account)
        #expect(try await owner.destinationOriginalData(handle, account: h.account) == data)
    }

    @Test func twoOriginalsShareRoleCohortCeilingsAndRejectOverflowAtomically() async throws {
        let h = try Harness(), owner = try h.owner(), data = PhotoPreparationTestHarness.image()
        let package = UUID(), generation = UUID()
        var handles: [PhotoOriginalReference] = []
        for ordinal in Int64(0)..<Int64(2) {
            let source = try await owner.stage { data }
            let handoff = try owner.prepareHandoff(source, account: h.account, packageID: package, draftGeneration: generation, ordinal: ordinal)
            handles.append(try await owner.handoff(handoff, account: h.account))
            try await owner.retireHandoffSource(handoff, account: h.account)
        }
        let ai = padded(3 * 1_024 * 1_024), display = padded(4 * 1_024 * 1_024)
        let first = try await owner.prepareDerivatives(handles[0], ai: ai, display: display, account: h.account)
        _ = try await owner.replaceDerivatives(first, ai: ai, display: display, account: h.account)
        let excessive = try await owner.prepareDerivatives(handles[1], ai: ai, display: display, account: h.account)
        await #expect(throws: SharedMediaStorageFailure.capacity) { _ = try await owner.replaceDerivatives(excessive, ai: ai, display: display, account: h.account) }
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaDerivativePairRecord>()) == 1)
        #expect(try h.context().fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0)
        let smaller = padded(2 * 1_024 * 1_024)
        let second = try await owner.prepareDerivatives(handles[1], ai: smaller, display: display, account: h.account)
        _ = try await owner.replaceDerivatives(second, ai: smaller, display: display, account: h.account)
        let refs = try h.context().fetch(FetchDescriptor<PhotoPreparationReference>())
        #expect(refs.count == 6 && Set(refs.map { $0.roleRaw + ":" + String($0.ordinal) }).count == 6)
        try await owner.discardDerivatives(first, account: h.account)
        _ = try await owner.readyDerivatives(second, account: h.account)
        for handle in handles { #expect(try await owner.destinationOriginalData(handle, account: h.account) == data) }
    }

    @Test(arguments: ["substitution", "symlink", "hardlink"])
    func foreignDerivativeFileCannotBeReadOrDeleted(_ kind: String) async throws {
        let h = try Harness(), owner = try h.owner(), data = PhotoPreparationTestHarness.image()
        let handle = try await original(h, owner, data)
        let request = try await owner.prepareDerivatives(handle, ai: data, display: data, account: h.account)
        let receipt = try await owner.replaceDerivatives(request, ai: data, display: data, account: h.account)
        let path = h.photo.appendingPathComponent("PhotoPreparation").appendingPathComponent(receipt.ai.token)
        let foreign = h.base.appendingPathComponent("foreign-image")
        try data.write(to: foreign)
        try FileManager.default.removeItem(at: path)
        switch kind {
        case "symlink": try FileManager.default.createSymbolicLink(at: path, withDestinationURL: foreign)
        case "hardlink": try FileManager.default.linkItem(at: foreign, to: path)
        default: try data.write(to: path)
        }
        await #expect(throws: (any Error).self) { _ = try await owner.readyDerivatives(request, account: h.account) }
        await #expect(throws: (any Error).self) { try await owner.discardDerivatives(request, account: h.account) }
        #expect(FileManager.default.fileExists(atPath: path.path))
        #expect(try Data(contentsOf: foreign) == data)
        #expect(try h.context().fetchCount(FetchDescriptor<SharedMediaAllocationRecord>()) == 3)
    }

    @Test func unexpectedSurvivingReferencePreventsFileRetirement() async throws {
        let h = try Harness(), owner = try h.owner(), data = PhotoPreparationTestHarness.image()
        let handle = try await original(h, owner, data)
        let request = try await owner.prepareDerivatives(handle, ai: data, display: data, account: h.account)
        let receipt = try await owner.replaceDerivatives(request, ai: data, display: data, account: h.account)
        let context = h.context(), id = UUID()
        let edge = PhotoPreparationReference(id: id, packageID: handle.packageID, assetID: receipt.ai.assetID,
            ownerID: handle.ownerID, roleRaw: "aiInput", ordinal: 1, revision: 0, isLive: true)
        let shared = SharedMediaReferenceRecord(id: id, allocationID: receipt.ai.assetID, accountID: handle.ownerID,
            ownerID: id.uuidString.lowercased(), roleRaw: SharedMediaPhotoLedger.namespace, stateRaw: "live", revision: 0)
        context.insert(edge); context.insert(shared); try context.save()
        await #expect(throws: (any Error).self) { try await owner.discardDerivatives(request, account: h.account) }
        #expect(FileManager.default.fileExists(atPath: h.photo.appendingPathComponent("PhotoPreparation").appendingPathComponent(receipt.ai.token).path))
        context.delete(edge); context.delete(shared); try context.save()
        try await owner.discardDerivatives(request, account: h.account)
    }

    private actor Gate {
        var began = false
        var continuation: CheckedContinuation<Void, Never>?
        func wait() async { began = true; await withCheckedContinuation { continuation = $0 } }
        func started() async { while !began { await Task.yield() } }
        func release() { continuation?.resume(); continuation = nil }
    }

    private func original(_ h: Harness, _ owner: SharedMediaInboxOwner, _ data: Data) async throws -> PhotoOriginalReference {
        let source = try await owner.stage { data }, request = try h.request(owner, source)
        let handle = try await owner.handoff(request, account: h.account)
        try await owner.retireHandoffSource(request, account: h.account)
        return handle
    }
    private func padded(_ count: Int) -> Data {
        var data = PhotoPreparationTestHarness.image(); data.append(Data(repeating: 0, count: count - data.count)); return data
    }

    @MainActor private struct Harness {
        let base: URL, authority: URL, inbox: URL, photo: URL
        let container: ModelContainer
        let inventory = UUID(), accountID = UUID(), otherID = UUID(), runtime = AuthRuntimeState()
        var account: PhotoOriginalPreparationOwner.AccountAccess { PhotoOriginalPreparationOwner.syntheticAccount(ownerID: accountID, runtime: runtime) }
        var otherAccount: PhotoOriginalPreparationOwner.AccountAccess { PhotoOriginalPreparationOwner.syntheticAccount(ownerID: otherID, runtime: runtime) }
        init() throws {
            base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("shared-derivative-" + UUID().uuidString)
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

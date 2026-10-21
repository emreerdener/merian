import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Asset-owned original identity liability", .serialized)
@MainActor
struct SharedMediaNativeOriginalLiabilityTests {
    typealias Fixture = SharedMediaNativeReleaseLiveFixture
    typealias Reader = SharedMediaNativeOriginalLiability

    @Test(arguments: ["one", "two", "foreign"])
    func measuresOriginalsOnceAcrossPendingAndHeldRelease(_ scenario: String) async throws {
        let count = scenario == "two" ? 2 : 1
        let f = try await Fixture.make(count: count, foreignOriginal: scenario == "foreign")
        let initial = try read(f)
        #expect(initial.entries.count == count && initial.retainedTargets.isEmpty)
        #expect(try initial.currentBytes + initial.reservedBytes == Int64(count * 512))
        let metadata = try SharedMediaNativeReleaseMetadataSnapshot.read(packageID: f.store.packageID,
            inventoryID: f.store.inventoryID, context: f.store.context())
        if scenario == "foreign" {
            #expect(metadata.ownedOriginals.isEmpty)
            #expect(initial.entries.values.allSatisfy { $0.physicalOriginID != f.store.packageID })
            return // The foreign origin remains shared; never simulate last-reference retirement.
        }
        #expect(Set(metadata.ownedOriginals.map(\.assetID)) == Set(initial.entries.keys))
        try f.retirePair(0); try f.removePair(0); try f.retireOriginal(0)
        let retiring = try read(f), id = f.progress.plan.targets[0].original.assetID
        #expect(retiring.entries[id]?.retiring == true)
        #expect(try retiring.currentBytes + retiring.reservedBytes == Int64(count * 512))
        #expect(try #require(retiring.entries[id]).currentBytes > #require(initial.entries[id]).currentBytes)
        try f.removeOriginal(0)
        let removed = try read(f)
        #expect(removed.entries[id] == nil && removed.entries.count == count - 1)
        #expect(try removed.currentBytes + removed.reservedBytes == Int64((count - 1) * 512))
    }

    @Test func genericPendingOriginalsAreMeasuredWithoutOpeningReceiving() async throws {
        let (store, owner, _) = try await SharedMediaNativeAppReceivingTests().fixture(count: 1)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let c = store.context()
        let result = try Reader.read(context: c, inventoryID: store.inventoryID)
        #expect(result.entries.count == 1 && result.retainedTargets.isEmpty)
        #expect(try result.currentBytes + result.reservedBytes == 512)
        #expect(try c.fetchCount(FetchDescriptor<SharedMediaReceivingIntentRecord>()) == 0)
        #expect(!c.hasChanges)
    }

    @Test func missingIdentityReceiptAndDirtyContextFailClosed() async throws {
        let f = try await Fixture.make(count: 1), id = f.progress.plan.targets[0].original.assetID
        _ = try read(f)
        let dirty = f.store.context(), package = try f.store.package(in: dirty)
        package.revision += 1
        #expect(throws: (any Error).self) { _ = try Reader.read(context: dirty, inventoryID: f.store.inventoryID) }
        dirty.rollback()
        #expect(throws: CancellationError.self) {
            _ = try Reader.read(context: f.store.context(), inventoryID: f.store.inventoryID, checkpoint: { throw CancellationError() })
        }
        let c = f.store.context()
        let allocation = try Fixture.one(c, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == id }))
        let original = allocation.physicalIdentity
        allocation.physicalIdentity = nil; try c.save()
        #expect(throws: (any Error).self) { _ = try read(f) }
        allocation.physicalIdentity = original; try c.save(); _ = try read(f)
        let receipt = try Fixture.one(c, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == id }))
        c.delete(receipt); try c.save()
        #expect(throws: (any Error).self) { _ = try read(f) }
    }

    @Test func nativeMutationProjectionsMatchCleanReadback() async throws {
        let store = try SharedMediaNativeAppMetadataTests.Store(), owner = try await store.open()
        let request = try await owner.prepareAppOriginal(packageID: store.packageID,
            draftGeneration: store.draft, ordinal: 0, kind: .picker)
        let bytes = PhotoPreparationTestHarness.image()
        let acquired = try await owner.acquireAppOriginal(request) { bytes }
        let source = PhotoOriginalReference(ownerID: request.ownerID, packageID: request.packageID,
            referenceID: request.referenceID, assetID: request.assetID, assetGeneration: request.assetGeneration,
            draftGeneration: request.draftGeneration, referenceRevision: acquired.referenceRevision)
        func measure(_ count: Int) throws {
            let context = store.context(), inventory = try Fixture.one(context,
                FetchDescriptor<SharedMediaInventoryRecord>())
            let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: context,
                inventory: inventory, ownerID: store.ownerID, format: .appV2)
            let snapshot = try #require(budget.originalIdentity)
            #expect(try snapshot == Reader.read(context: context, inventoryID: store.inventoryID))
            #expect(snapshot.entries.count == count)
            #expect(try snapshot.currentBytes + snapshot.reservedBytes == Int64(count * 512))
        }
        try measure(1)
        let edit = try await owner.prepareAppMetadata(packageID: store.packageID, draftGeneration: store.draft,
            contexts: [.init(freeText: "Keep original bytes")], presentation: [])
        _ = try await owner.saveAppMetadata(edit); try measure(1)
        let share = try await owner.prepareAppOriginalShare(source, packageID: UUID(), draftGeneration: UUID())
        let destination = try await owner.shareAppOriginal(share); try measure(1)
        let removeFirst = try await owner.prepareAppOriginalRemoval(source)
        try await owner.removeAppOriginal(removeFirst); try measure(1)
        let removeLast = try await owner.prepareAppOriginalRemoval(destination)
        try await owner.removeAppOriginal(removeLast); try measure(1)
        try await owner.recoverAppOriginalRetirements(); try measure(0)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private func read(_ f: Fixture) throws -> Reader.Snapshot {
        let c = f.store.context(), result = try Reader.read(context: c, inventoryID: f.store.inventoryID)
        #expect(!c.hasChanges)
        for entry in result.entries.values {
            let id = entry.assetID
            let allocation = try Fixture.one(c, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == id }))
            #expect(entry.currentBytes == Int64(try #require(allocation.physicalIdentity).utf8.count))
            #expect(entry.currentBytes > 0 && entry.reservedBytes >= 0)
            #expect(entry.currentBytes + entry.reservedBytes == 512)
        }
        return result
    }
}

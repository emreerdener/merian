import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Clean held-release serialized metadata inputs", .serialized)
@MainActor
struct SharedMediaNativeReleaseMetadataSnapshotTests {
    typealias Fixture = SharedMediaNativeReleaseLiveFixture
    typealias Reader = SharedMediaNativeReleaseMetadataSnapshot

    @Test(arguments: [1, 2])
    func measuresOnlySurvivingPayloadsFromSavedRows(_ count: Int) async throws {
        let f = try await Fixture.make(count: count)
        let initial = try read(f)
        #expect(initial.pairs.count == count)
        #expect(initial.ownedOriginals.count == count)
        #expect(initial.ownedOriginals.allSatisfy { $0.physicalOriginID == f.store.packageID && !$0.retiring })
        #expect(initial.pairs.allSatisfy { $0.work.allSatisfy { $0.closure == nil } })
        #expect(try initial.currentSerializedBytes > initial.packagePayloadBytes)

        try f.retirePair(0)
        let retiring = try read(f)
        let pair = try #require(retiring.pairs.first { $0.phase == "retiring" })
        let proof = try #require(pair.work.first?.closure)
        let closure = try SharedMediaNativePairClosure.decode(proof)
        #expect(closure.pairID == f.progress.plan.targets[0].pairID)
        #expect(pair.work.last?.closure == (try closure.siblingMarker()))
        #expect(try retiring.pairBytes > initial.pairBytes)
        let savedMembership = closure.previous.membership

        if count == 2 {
            try f.retirePair(1); try f.removePair(1)
            try f.retireOriginal(1); try f.removeOriginal(1)
            let survivor = try read(f)
            #expect(survivor.pairs.count == 1)
            #expect(survivor.ownedOriginals.count == 1)
            #expect(try SharedMediaNativePairClosure.decode(#require(survivor.pairs[0].work[0].closure)).previous.membership == savedMembership)
            #expect(survivor.pairs[0].plan.membership != savedMembership)
        }

        try f.removePair(0)
        let original = try read(f)
        #expect(original.pairs.isEmpty)
        #expect(try original.pairBytes == 0)
        try f.retireOriginal(0)
        let last = try read(f)
        #expect(last.ownedOriginals.count == 1)
        #expect(last.ownedOriginals[0].retiring)
        let assetID = f.progress.plan.targets[0].original.assetID, context = f.store.context()
        let allocation = try Fixture.one(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID }))
        #expect(last.ownedOriginals[0].identityBytes == Int64(try #require(allocation.physicalIdentity).utf8.count))
        try f.removeOriginal(0)
        let removed = try read(f)
        #expect(removed.pairs.isEmpty && removed.ownedOriginals.isEmpty)
        #expect(try removed.originReceiptBytes == 0 && removed.originIdentityBytes == 0)
        #expect(removed.release.state.package.allocated == 0)
        #expect(try removed.currentSerializedBytes > 0) // Held execution and slot still exist.
        #expect(try removed.currentSerializedBytes == removed.packagePayloadBytes)

        let dirty = f.store.context(), package = try f.store.package(in: dirty)
        package.revision += 1
        #expect(throws: (any Error).self) {
            _ = try Reader.read(packageID: f.store.packageID, inventoryID: f.store.inventoryID, context: dirty)
        }
        dirty.rollback()
        let cancelled = f.store.context()
        #expect(throws: CancellationError.self) {
            _ = try Reader.read(packageID: f.store.packageID, inventoryID: f.store.inventoryID,
                context: cancelled, checkpoint: { throw CancellationError() })
        }
        #expect(!cancelled.hasChanges)
    }

    private func read(_ f: Fixture) throws -> Reader.Snapshot {
        let c = f.store.context()
        let result = try Reader.read(packageID: f.store.packageID, inventoryID: f.store.inventoryID, context: c)
        #expect(!c.hasChanges && result.release.progress == f.progress)
        let package = try f.store.package(in: c), packageID = f.store.packageID
        let member = try Fixture.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        let slot = try Fixture.one(c, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == packageID }))
        let rows = try SharedMediaNativeReleaseOrigin.read(f.progress.plan, in: c).rows
        #expect(result.envelopeBytes == Int64(package.supportingContextData.count))
        #expect(result.membershipBytes == Int64(member.membersData.count))
        #expect(result.slotBytes == Int64(try #require(slot.resultData).count))
        #expect(result.consumerBytes == Int64(rows.consumer.cohortData.count))
        #expect(result.executionBytes == Int64(try #require(rows.job.metadataJSON).utf8.count + #require(rows.event.metadataJSON).utf8.count))
        // A measurement must not open generic runtime slot dispatch.
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeReceivingSlot.decode(.init(slot), profile: f.prepared.profile)
        }
        return result
    }
}

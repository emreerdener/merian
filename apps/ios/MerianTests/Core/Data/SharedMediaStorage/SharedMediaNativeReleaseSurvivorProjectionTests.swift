import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Held-release survivor metadata bounds", .serialized)
@MainActor
struct SharedMediaNativeReleaseSurvivorProjectionTests {
    typealias Fixture = SharedMediaNativeReleaseLiveFixture
    typealias Reader = SharedMediaNativeReleaseMetadataSnapshot
    typealias Projection = SharedMediaNativeReleaseSurvivorProjection

    @Test(arguments: [1, 2])
    func boundsEveryPersistedPhysicalStageWithoutReconstructingDeletedPairs(_ count: Int) async throws {
        let f = try await Fixture.make(count: count)
        var previous: [Projection.Projection] = []
        func check() throws -> Reader.Snapshot {
            let c = f.store.context()
            let snapshot = try Reader.read(packageID: f.store.packageID, inventoryID: f.store.inventoryID, context: c)
            let result = try Projection.maximum(snapshot)
            #expect(!c.hasChanges)
            #expect(result.currentBytes == (try snapshot.currentSerializedBytes))
            #expect(result.maximumBytes >= result.currentBytes && result.futureGrowthBytes >= 0)
            try result.requireMetadataCapacity()
            #expect(result.maximumPackagePayloadBytes <= PhotoPreparationPolicy.metadata)
            for old in previous { #expect(old.maximumBytes >= result.currentBytes) }
            for charge in result.charges { #expect(try charge.total <= result.maximumBytes) }
            previous.append(result)
            return snapshot
        }
        let initial = try check(), initialResult = try Projection.maximum(initial)
        #expect(initialResult.charges.filter { !$0.terminal }.count == (count == 1 ? 6 : 36))
        #expect(initialResult.charges.filter(\.terminal).count == (count == 1 ? 2 : 4))
        let slot = try SharedMediaNativeReceivingReleaseValues.slotBound(plan: f.progress.plan, prepared: f.prepared,
            received: f.received, acquisitionIDs: f.progress.plan.targets.map(\.acquisitionID))
        let physical = try #require(initialResult.charges.first { $0.terminal && $0.stages.allSatisfy { $0 == 4 } })
        #expect(physical.packageBytes == slot.maximumReleasedBytes && physical.originBytes == 0)
        let shared = try #require(initialResult.charges.first { $0.terminal && $0.stages.allSatisfy { $0 == 5 } })
        #expect(shared.originBytes == (try initial.originReceiptBytes + Int64(count) * 512))
        // At the all-originals-retiring stage there are no pair charges. The
        // old slot and old identity are replaced, not retained beside bounds.
        let retiring = try #require(initialResult.charges.first { !$0.terminal && $0.stages.allSatisfy { $0 == 3 } })
        #expect(retiring.originBytes == shared.originBytes)

        try f.retirePair(0); _ = try check()
        if count == 2 {
            try f.retirePair(1); _ = try check()
            try f.removePair(1); _ = try check()
            try f.retireOriginal(1); _ = try check()
            try f.removeOriginal(1); _ = try check()
        }
        try f.removePair(0); _ = try check()
        try f.retireOriginal(0)
        let last = try check(), lastResult = try Projection.maximum(last)
        let same = try #require(lastResult.charges.first { !$0.terminal && $0.stages[0] == 3 })
        let immutable = try PhotoPreparationPolicy.add([last.envelopeBytes, last.consumerBytes, last.executionBytes])
        #expect(same.packageBytes == immutable + last.membershipBytes + slot.charged)
        #expect(same.originBytes == (try last.originReceiptBytes + 512))
        try f.removeOriginal(0)
        let done = try check(), doneResult = try Projection.maximum(done)
        #expect(done.pairs.isEmpty && done.ownedOriginals.isEmpty)
        #expect(doneResult.charges.count == 2)
        #expect(doneResult.charges.allSatisfy { $0.originBytes == 0 })
    }

    @Test func foreignTargetIsClassifiedWithoutChargingItsOriginLocally() async throws {
        let f = try await Fixture.make(count: 1, foreignOriginal: true)
        let c = f.store.context(), target = f.progress.plan.targets[0]
        let snapshot = try Reader.read(packageID: f.store.packageID, inventoryID: f.store.inventoryID, context: c)
        let origin = try #require(snapshot.targetOrigins.first)
        guard case .present(let packageID) = origin.location else { Issue.record("Missing physical origin"); return }
        #expect(packageID != f.store.packageID && origin.assetID == target.original.assetID)
        #expect(origin.acquisitionID == target.acquisitionID && snapshot.ownedOriginals.isEmpty)
        let receiptID = target.acquisitionID
        let receipt = try Fixture.one(c, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == receiptID }))
        #expect(receipt.packageID == packageID && receipt.resultData != nil)
        #expect(try Projection.maximum(snapshot).charges.allSatisfy { $0.originBytes == 0 })
        #expect(!c.hasChanges)
        // A foreign classification cannot conceal a missing local origin, or
        // be charged once here and again by the physical owner's budget pass.
        let fakeLocal = Reader.TargetOrigin(assetID: origin.assetID, acquisitionID: origin.acquisitionID,
            location: .present(packageID: f.store.packageID))
        #expect(throws: (any Error).self) { _ = try Projection.maximum(copy(snapshot, origins: [fakeLocal])) }
    }

    @Test func rejectsAmbiguousOriginsAndInvalidArithmetic() async throws {
        let f = try await Fixture.make(count: 2)
        let s = try Reader.read(packageID: f.store.packageID, inventoryID: f.store.inventoryID, context: f.store.context())
        let first = try #require(s.ownedOriginals.first)
        #expect(throws: (any Error).self) { _ = try Projection.maximum(copy(s, originals: [])) }
        #expect(throws: (any Error).self) { _ = try Projection.maximum(copy(s, originals: s.ownedOriginals + [first])) }
        #expect(throws: (any Error).self) { _ = try Projection.maximum(copy(s, origins: [])) }
        #expect(throws: (any Error).self) { _ = try Projection.maximum(copy(s, pairs: [])) }
        #expect(throws: (any Error).self) { _ = try Projection.maximum(copy(s, execution: -1)) }
        #expect(throws: (any Error).self) { _ = try Projection.maximum(copy(s, execution: Int64.max)) }
        for invalid in [Int64(0), 513] {
            let wrong = Reader.Original(assetID: first.assetID, physicalOriginID: first.physicalOriginID,
                receiptBytes: first.receiptBytes, identityBytes: invalid, retiring: first.retiring)
            #expect(throws: (any Error).self) {
                _ = try Projection.maximum(copy(s, originals: [wrong] + s.ownedOriginals.dropFirst()))
            }
        }
        let extra = Reader.Original(assetID: UUID(), physicalOriginID: f.store.packageID,
            receiptBytes: 100, identityBytes: 40, retiring: false)
        let ordinary = try Projection.maximum(s), withExtra = try Projection.maximum(copy(s, originals: s.ownedOriginals + [extra]))
        #expect(withExtra.currentBytes == ordinary.currentBytes + 140)
        for (left, right) in zip(ordinary.charges, withExtra.charges) {
            #expect(left.packageBytes == right.packageBytes)
            #expect(right.originBytes == left.originBytes + 612)
        }
        // Preserve the existing cap categories: live package payload and its
        // owned receipts count toward 1 MiB; allocation identities are global.
        // These synthetic arithmetic boundaries do not authorize admission.
        let offset = PhotoPreparationPolicy.metadata - ordinary.maximumLivePackageMetadataBytes
        #expect(offset >= 0)
        let exact = try Projection.maximum(copy(s, execution: s.executionBytes + offset))
        #expect(exact.maximumLivePackageMetadataBytes == PhotoPreparationPolicy.metadata)
        #expect(exact.maximumBytes > PhotoPreparationPolicy.metadata)
        try exact.requireMetadataCapacity()
        let over = try Projection.maximum(copy(s, execution: s.executionBytes + offset + 1))
        #expect(over.maximumLivePackageMetadataBytes == PhotoPreparationPolicy.metadata + 1)
        #expect(throws: SharedMediaStorageFailure.capacity) { try over.requireMetadataCapacity() }
        #expect(exact.maximumTerminalSlotBytes == ordinary.maximumTerminalSlotBytes)
        for charge in exact.charges where charge.terminal {
            #expect(try charge.metadataCapBytes == charge.packageBytes)
            #expect(charge.packageBytes == exact.maximumTerminalSlotBytes)
        }
        let identity = Reader.Original(assetID: first.assetID, physicalOriginID: first.physicalOriginID,
            receiptBytes: first.receiptBytes, identityBytes: 512, retiring: first.retiring)
        let identities = try Projection.maximum(copy(s, originals: [identity] + s.ownedOriginals.dropFirst()))
        #expect(identities.currentBytes == ordinary.currentBytes + 512 - first.identityBytes)
        #expect(identities.maximumLivePackageMetadataBytes == ordinary.maximumLivePackageMetadataBytes)
        #expect(identities.maximumTerminalSlotBytes == ordinary.maximumTerminalSlotBytes)
        let targetIndex = try #require(s.release.progress.plan.targets.firstIndex { $0.original.assetID == first.assetID })
        for (left, right) in zip(ordinary.charges, identities.charges) {
            #expect(try left.metadataCapBytes == right.metadataCapBytes)
            #expect(left.originReceiptBytes == right.originReceiptBytes)
            let delta = left.stages[targetIndex] <= 2 ? 512 - first.identityBytes : 0
            #expect(right.originIdentityBytes == left.originIdentityBytes + delta)
            #expect(try right.total == left.total + delta)
        }
    }

    private func copy(_ s: Reader.Snapshot, originals: [Reader.Original]? = nil,
                      origins: [Reader.TargetOrigin]? = nil, pairs: [SharedMediaNativePairFileState]? = nil,
                      execution: Int64? = nil) -> Reader.Snapshot {
        .init(release: s.release, inventoryRevision: s.inventoryRevision, envelopeBytes: s.envelopeBytes,
            membershipBytes: s.membershipBytes, consumerBytes: s.consumerBytes, executionBytes: execution ?? s.executionBytes,
            slotBytes: s.slotBytes, pairs: pairs ?? s.pairs, ownedOriginals: originals ?? s.ownedOriginals,
            targetOrigins: origins ?? s.targetOrigins)
    }
}

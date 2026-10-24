import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Held pair removal raw seal", .serialized)
@MainActor
struct SharedMediaNativeReleasePairRemovalSealTests {
    typealias Fixture = SharedMediaNativeReleasePairRemovalOwnerTests

    @Test func deletionSealRejectsOmissionsExtraWritesAndRawDrift() async throws {
        let (h, owner, before) = try await Fixture().fixture()
        let snapshot = try SharedMediaNativeReleasePairOwnerTests().snapshot(h), state = try #require(snapshot.pairs.first)
        let after = try SharedMediaNativeReleasePairRemovalRecovery.successor(before)
        let next = try SharedMediaNativeReceivingReleaseState.expected(after, prepared: snapshot.release.origin.prepared, received: snapshot.release.origin.received)
        for fault in ["valid", "omitDeletion", "deletedRaw", "package", "slot", "extraDelete", "extraInsert", "original"] {
            let c = h.context(), inventoryID = h.inventoryID, packageID = h.packageID, pairID = try state.intent().pairID
            let inventory = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
            let package = try h.package(in: c)
            let member = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
            let pair = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == pairID }))
            let row = try #require(try SharedMediaNativeReceivingPhaseGraph.row(packageID, in: c))
            let seal = try SharedMediaNativeReleasePairRemovalPoststate(state: state, before: before, after: after, successor: next, context: c)
            let firstWorkID = try #require(state.work.first?.id)
            let firstWork = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == firstWorkID }))
            if fault == "deletedRaw" { firstWork.sha256 = String(repeating: "b", count: 64) }
            if fault != "omitDeletion" { try SharedMediaNativePairRemovalRows.apply(context: c, package: package, pair: pair, before: state) }
            package.revision = next.package.revision; package.allocatedByteCount = next.package.allocated
            member.revision = next.member.revision; member.membersData = next.member.bytes
            row.revision = next.slotRevision; row.resultData = try after.encoded(); row.resultSHA256 = SharedMediaAcquisitionEncoding.digest(row.resultData!)
            inventory.revision += 1
            switch fault {
            case "package": package.supportingContextData.append(0)
            case "slot": row.preparedSHA256 = String(repeating: "c", count: 64)
            case "extraDelete": c.delete(inventory)
            case "extraInsert":
                c.insert(SharedMediaLeaseRecord(id: UUID(), allocationID: UUID(), processEpoch: UUID(), purposeRaw: "unrelated", stateRaw: "closed"))
            case "original":
                let id = try #require(before.plan.targets.first?.original.assetID)
                let asset = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == id }))
                asset.contentType = "changed"
            default: break
            }
            if fault == "valid" { try seal.validate(c) }
            else { #expect(throws: (any Error).self) { try seal.validate(c) } }
            c.rollback()
        }
        #expect(try SharedMediaNativeReleasePairOwnerTests().snapshot(h).release.progress == before)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func predecessorSealRejectsRawDriftAndEqualLogicalReplacement() async throws {
        let (h, owner, before) = try await Fixture().fixture()
        let snapshot = try SharedMediaNativeReleasePairOwnerTests().snapshot(h), state = try #require(snapshot.pairs.first)
        let after = try SharedMediaNativeReleasePairRemovalRecovery.successor(before)
        let next = try SharedMediaNativeReceivingReleaseState.expected(after, prepared: snapshot.release.origin.prepared, received: snapshot.release.origin.received)
        let c = h.context()
        let seal = try SharedMediaNativeReleasePairRemovalPoststate(state: state, before: before, after: after, successor: next, context: c)
        let id = try #require(state.work.first?.id)
        let read = h.context(), work = try SharedMediaNativePairPlanGraph.one(read, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == id }))
        let prior = work.sha256
        work.sha256 = String(repeating: "d", count: 64); try read.save()
        #expect(throws: (any Error).self) { try seal.requirePredecessor(h.context()) }
        work.sha256 = prior; try read.save()
        try seal.requirePredecessor(h.context())
        let leaseID = try state.selected(id).1.leaseID
        let replacementContext = h.context()
        let lease = try SharedMediaNativePairPlanGraph.one(replacementContext, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == leaseID }))
        let replacement = SharedMediaLeaseRecord(id: lease.id, allocationID: lease.allocationID, processEpoch: lease.processEpoch,
            purposeRaw: lease.purposeRaw, stateRaw: lease.stateRaw)
        replacementContext.delete(lease); try replacementContext.save()
        replacementContext.insert(replacement); try replacementContext.save()
        #expect(throws: (any Error).self) { try seal.requirePredecessor(h.context()) }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }
}

import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Held pair-retirement exact seal", .serialized)
@MainActor
struct SharedMediaNativeReleasePairSealTests {
    let ownerTests = SharedMediaNativeReleasePairOwnerTests()
    typealias Store = SharedMediaNativeAppMetadataTests.Store

    @Test func jointRawSealRejectsIncompleteAndUnrelatedWritesWithoutPersistence() async throws {
        let (h, owner, progress) = try await ownerTests.fixture()
        try owner.setMetadataFault { if $0 == .beforeSave { throw SharedMediaStorageFailure.unavailable } }
        await #expect(throws: (any Error).self) { _ = try await owner.retireAppReleasePair(progress) }
        let attempt = try #require(try await owner.frozenAppReleasePairForTesting(progress))
        let saved = try ownerTests.snapshot(h), slot = try ownerTests.start.row(h)
        for fault in ["progress", "membership", "preservedScalar", "missingLease", "wrongLease", "extraLease", "unrelated", "deletion"] {
            let c = h.context(), seal = try SharedMediaNativeReleasePairPoststate(attempt, context: c)
            try apply(attempt, h: h, context: c)
            try seal.validate(c) // Positive joint predecessor-derived successor.
            let row = try ownerTests.start.record(h, c)
            switch fault {
            case "progress": row.resultData = slot.resultData; row.resultSHA256 = slot.resultSHA256; row.revision = slot.revision
            case "membership":
                let id = h.packageID
                let member = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
                member.membersData = saved.release.state.member.bytes; member.revision = saved.release.state.member.revision
            case "preservedScalar":
                let id = try attempt.state.intent().ai.assetID
                try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == id })).contentType = "changed"
            case "missingLease", "wrongLease":
                let id = try attempt.state.intent().ai.leaseID
                let lease = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == id }))
                if fault == "missingLease" { c.delete(lease) } else { lease.finalFileToken = "wrong" }
            case "extraLease":
                c.insert(SharedMediaLeaseRecord(id: UUID(), allocationID: UUID(), processEpoch: UUID(), purposeRaw: "unrelated", stateRaw: "closed"))
            case "unrelated": try h.package(h.ordinaryID, in: c).revision += 1
            default: c.delete(try h.package(h.ordinaryID, in: c))
            }
            #expect(throws: (any Error).self) { try seal.validate(c) }
            c.rollback()
            #expect(try ownerTests.start.row(h) == slot)
            let after = try ownerTests.snapshot(h)
            #expect(after.release.state == saved.release.state && after.pairs == saved.pairs)
            #expect(after.inventoryRevision == saved.inventoryRevision)
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func frozenAttemptSurvivesCollisionDenialWithoutReplacement() async throws {
        let (h, owner, progress) = try await ownerTests.fixture()
        var saves = 0
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1; throw SharedMediaStorageFailure.unavailable } }
        await #expect(throws: (any Error).self) { _ = try await owner.retireAppReleasePair(progress) }
        let first = try #require(try await owner.frozenAppReleasePairForTesting(progress))
        let bytes = try first.closure.encoded(), expected = first.after, before = try ownerTests.start.row(h)
        // An ordinary legacy queue is a coherent indexed alias, outside the
        // native receiving membership. It must not cause a replacement UUID.
        let c = h.context(), collision = OfflineQueuedScan(id: first.closure.retirementID.uuidString, fieldNotes: "synthetic collision")
        c.insert(collision); try c.save()
        try owner.setMetadataFault { if $0 == .beforeSave { saves += 1 } }
        await #expect(throws: (any Error).self) { _ = try await owner.retireAppReleasePair(progress) }
        #expect(try ownerTests.start.row(h) == before && saves == 1)
        c.delete(collision); try c.save()
        let retained = try #require(try await owner.frozenAppReleasePairForTesting(progress))
        #expect(retained === first && retained.after == expected)
        #expect(try retained.closure.encoded() == bytes)
        // Reference identity plus immutable fields proves target, ID and both
        // original inspection objects were retained, rather than regenerated.
        #expect(retained.proofs.map(\.workID) == first.proofs.map(\.workID))
        #expect(try await owner.retireAppReleasePair(progress) == expected && saves == 2)
        #expect(try ownerTests.snapshot(h).pairs.first?.work.first?.closure == bytes)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func ordinaryRetirementIDsAreDeniedByIndexedNamespaceChecks() async throws {
        let ordinary = SharedMediaNativeAppPairRetirementTests()
        let (h, ready) = try await ordinary.fixture("ready"), owner = try await ordinary.reopen(h)
        try owner.setPreparationFault { if $0 == .beforeFileRelease { throw SharedMediaStorageFailure.unavailable } }
        await #expect(throws: (any Error).self) { try await owner.retireAppPhotoPair(packageID: h.packageID, pairID: ready.intent().pairID) }
        let state = try ordinary.state(h), id = try #require(state.work.first?.retirementID)
        #expect(state.phase == "retiring")
        // This is the real, coherent ordinary retirement path, without a
        // receiving Progress witness. The direct query must still see its ID.
        #expect(throws: SharedMediaStorageFailure.conflict) { try SharedMediaNativeReleaseStageIdentity.direct(id, context: h.context()) }
        #expect(try ordinary.state(h) == state)
        // Isolate the two namespace columns with saved synthetic drift. This
        // checks the indexed denial itself, not whole-graph admission of drift.
        for field in ["work", "counter"] {
            let c = h.context(), probe = UUID(), asset = try state.intent().ai.assetID
            let work = try #require(try c.fetch(FetchDescriptor<SharedMediaDerivativeWorkRecord>()).first)
            let counter = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == asset }))
            let oldWork = work.retirementID, oldCounter = counter.retirementID
            if field == "work" { work.retirementID = probe } else { counter.retirementID = probe }
            try c.save()
            #expect(throws: SharedMediaStorageFailure.conflict) {
                try SharedMediaNativeReleaseStageIdentity.direct(probe, context: h.context())
            }
            work.retirementID = oldWork; counter.retirementID = oldCounter; try c.save()
            #expect(try ordinary.state(h) == state)
        }
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    private func apply(_ a: SharedMediaNativeReleasePairAttempt, h: Store, context c: ModelContext) throws {
        let package = try h.package(in: c), id = h.packageID, pairID = a.closure.pairID
        let pair = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == pairID }))
        let member = try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
        try SharedMediaNativePairRetirementRows.apply(context: c, package: package, pair: pair, before: a.state, closure: a.closure)
        package.revision = a.successor.package.revision
        member.revision = a.successor.member.revision; member.membersData = a.successor.member.bytes
        let row = try ownerTests.start.record(h, c)
        row.revision = a.successor.slotRevision; row.resultData = try a.after.encoded()
        row.resultSHA256 = SharedMediaAcquisitionEncoding.digest(row.resultData!)
        try ownerTests.start.inventory(h, c).revision += 1
    }
}

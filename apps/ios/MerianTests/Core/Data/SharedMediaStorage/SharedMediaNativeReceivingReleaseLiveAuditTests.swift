import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Clean held-release current-row audit", .serialized)
@MainActor
struct SharedMediaNativeReceivingReleaseLiveAuditTests {
    typealias Fixture = SharedMediaNativeReleaseLiveFixture
    typealias Values = SharedMediaNativeReceivingReleaseValues
    typealias Audit = SharedMediaNativeReceivingReleaseLiveAudit

    @Test(arguments: [1, 2])
    func persistedStagesAndHistoricalClosuresSurviveIndependentProgress(_ count: Int) async throws {
        let f = try await Fixture.make(count: count)
        _ = try f.read()
        for field in ["phase", "revision", "digest", "prepared", "package", "member", "queue", "original"] {
            try reject(f) { c in
                let id = f.store.packageID
                let slot = try Fixture.one(c, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
                switch field {
                case "phase": let old = slot.phaseRaw; slot.phaseRaw = "received"; return { slot.phaseRaw = old }
                case "revision": slot.revision += 1; return { slot.revision -= 1 }
                case "digest": let old = slot.resultSHA256; slot.resultSHA256 = String(repeating: "d", count: 64); return { slot.resultSHA256 = old }
                case "prepared": slot.preparedData = try f.prepared.encoded(); return { slot.preparedData = nil }
                case "package": let row = try f.store.package(in: c); row.allocatedByteCount += 1; return { row.allocatedByteCount -= 1 }
                case "member":
                    let row = try Fixture.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
                    let old = row.membersData; row.membersData = try SharedMediaMembership(groups: []).encoded(); return { row.membersData = old }
                case "queue":
                    let rows = try SharedMediaNativeReleaseOrigin.read(f.progress.plan, in: c).rows
                    rows.queue.queueAttemptCount = 1; return { rows.queue.queueAttemptCount = 0 }
                default:
                    let asset = f.progress.plan.targets[0].original.assetID
                    let row = try Fixture.one(c, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == asset }))
                    row.liveCount += 1; return { row.liveCount -= 1 }
                }
            }
        }
        try f.retirePair(0); _ = try f.read()
        try f.inventoryAdvance(); _ = try f.read()
        // The generic immediate-successor wrapper remains strict while the
        // release-specific historical/current-state wrapper accepts this state.
        let generic = f.store.context(), target = f.progress.plan.targets[0], id = target.pairID
        let workID = target.ai.workID, inventoryID = f.store.inventoryID
        let row = try Fixture.one(generic, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == id }))
        let work = try Fixture.one(generic, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == workID }))
        let inventory = try Fixture.one(generic, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let input = try SharedMediaNativeDerivativeIntent.decode(f.entries[0].intent.bytes).ai
        #expect(throws: (any Error).self) {
            try SharedMediaNativePairFileGraph.validate(work, input: input, pair: row,
                package: f.store.package(in: generic), inventory: inventory, context: generic)
        }
        for field in ["canonical", "marker", "work", "allocation"] {
            try reject(f) { c in
                let leaseID = field == "marker" ? target.display.leaseID : target.ai.leaseID
                if field == "canonical" || field == "marker" {
                    let lease = try Fixture.one(c, FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == leaseID }))
                    let old = lease.terminalProof; lease.terminalProof = "invalid"; return { lease.terminalProof = old }
                }
                if field == "work" {
                    let row = try Fixture.one(c, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == workID }))
                    let old = row.retirementParentIdentity; row.retirementParentIdentity = "1:2"; return { row.retirementParentIdentity = old }
                }
                let asset = target.ai.assetID
                let row = try Fixture.one(c, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == asset }))
                let old = row.stateRaw; row.stateRaw = "nativePairMaterializedV2"; return { row.stateRaw = old }
            }
        }
        if count == 2 {
            try f.retirePair(1); _ = try f.read()
            try f.removePair(1); _ = try f.read()
            try f.retireOriginal(1); _ = try f.read()
            try f.removeOriginal(1); _ = try f.read()
        }
        try f.removePair(0); _ = try f.read()
        // A saved leftover alias must fail even after the canonical pair rows
        // disappeared. This is logical row evidence, not a filesystem proof.
        let stale = f.store.context(), aliasID = UUID()
        stale.insert(SharedMediaLeaseRecord(id: aliasID, allocationID: target.ai.assetID, processEpoch: UUID(),
            purposeRaw: SharedMediaNativePairPlanGraph.contract, stateRaw: "closed"))
        try stale.save()
        #expect(throws: (any Error).self) { _ = try f.read() }
        stale.delete(try Fixture.one(stale, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == aliasID })))
        try stale.save(); _ = try f.read()
        try f.retireOriginal(0); _ = try f.read()
        try reject(f) { c in
            let asset = target.original.assetID
            let row = try Fixture.one(c, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == asset }))
            let old = row.physicalIdentity; row.physicalIdentity = "invalid"; return { row.physicalIdentity = old }
        }
        try f.removeOriginal(0); _ = try f.read()
        try reject(f) { c in
            let receiptID = target.acquisitionID
            let row = try Fixture.one(c, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == receiptID }))
            let old = row.ownerID; row.ownerID = UUID(); return { row.ownerID = old }
        }
        // Runtime routing and generic mutation facts remain closed.
        let closed = f.store.context(), packageID = f.store.packageID
        let slot = try Fixture.one(closed, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == packageID }))
        #expect(throws: (any Error).self) { _ = try SharedMediaNativeReceivingSlot.decode(.init(slot), profile: f.prepared.profile) }
        let dirty = f.store.context(), package = try f.store.package(in: dirty)
        package.revision += 1
        #expect(throws: (any Error).self) { _ = try Audit.read(packageID: packageID, inventoryID: inventoryID, context: dirty) }
        dirty.rollback()
    }

    @Test func sharedRemovalDoesNotRequireTheOtherOwnerToSurviveForever() async throws {
        let f = try await Fixture.make(count: 1), target = f.progress.plan.targets[0]
        let c = f.store.context(), assetID = target.original.assetID, packageID = UUID(), refID = UUID()
        let intent = try SharedMediaNativeDerivativeIntent.decode(f.entries[0].intent.bytes)
        let destination = PhotoOriginalReference(ownerID: f.store.ownerID, packageID: packageID, referenceID: refID,
            assetID: assetID, assetGeneration: target.original.assetGeneration, draftGeneration: f.store.draft, referenceRevision: 0)
        let other = f.store.row(packageID, envelope: try PhotoPreparationPolicy.encodeDraft(contexts: [], presentation: []), phase: "draftOwned")
        other.allocatedByteCount = intent.preparation.original.byteCount
        c.insert(other)
        c.insert(PhotoPreparationReference(id: refID, packageID: packageID, assetID: assetID, ownerID: f.store.ownerID,
            roleRaw: "original", ordinal: 0, revision: 0, isLive: true))
        c.insert(SharedMediaReferenceRecord(id: refID, allocationID: assetID, accountID: f.store.ownerID,
            ownerID: refID.uuidString.lowercased(), roleRaw: SharedMediaPhotoLedger.namespace, stateRaw: "live", revision: 0))
        c.insert(SharedMediaPendingMembershipRecord(packageID: packageID, inventoryID: f.store.inventoryID,
            inventoryGeneration: f.prepared.profile.generation, ownerID: f.store.ownerID, draftGeneration: f.store.draft,
            membersData: try SharedMediaNativeAppOriginalRows.shareMembership(destination, leaseID: target.acquisitionID)))
        let count = try Fixture.one(c, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID }))
        count.liveCount += 1; count.revision += 1; try f.save(c)
        _ = try f.read(); try f.retirePair(0); _ = try f.read(); try f.removePair(0); _ = try f.read()
        let remove = f.store.context()
        let (ref, edge) = try SharedMediaNativeAppOriginalRows.reference(remove, source: target.original, live: true)
        remove.delete(ref); remove.delete(edge)
        let counter = try Fixture.one(remove, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID }))
        counter.liveCount -= 1; counter.revision += 1
        f.progress = try f.progress.advancing(.init(pairID: target.pairID, stage: .removed, pair: f.progress.targets[0].pair,
            original: .init(disposition: .shared, retirementID: nil, closureSHA256: String(repeating: "c", count: 64))))
        try f.save(remove); _ = try f.read()
        try reject(f) { c in
            let row = try Fixture.one(c, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID }))
            row.liveCount += 1; return { row.liveCount -= 1 }
        }
        // Later independent physical cleanup is simulated, not authorized by
        // this historical shared-release assertion.
        let later = f.store.context()
        try f.eraseOriginal(target, context: later)
        later.delete(try Fixture.one(later, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID })))
        later.delete(try Fixture.one(later, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID })))
        try f.save(later); _ = try f.read()
    }

    private func reject(_ f: Fixture, mutate: (ModelContext) throws -> () throws -> Void) throws {
        let c = f.store.context(), restore = try mutate(c)
        try c.save()
        #expect(throws: (any Error).self) { _ = try f.read() }
        try restore(); try c.save()
        _ = try f.read()
    }
}

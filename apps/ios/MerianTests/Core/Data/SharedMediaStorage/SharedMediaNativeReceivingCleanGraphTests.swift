import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Clean-only native receiving classification", .serialized)
@MainActor
struct SharedMediaNativeReceivingCleanGraphTests {
    typealias Graph = SharedMediaNativeReceivingCleanGraph
    typealias Fixture = SharedMediaNativeReleaseLiveFixture

    @Test(arguments: [1, 2])
    func classifiesOnlyExactSavedReleaseEvidenceThroughIndependentCleanup(_ count: Int) async throws {
        let f = try await Fixture.make(count: count)
        let inventoryID = f.store.inventoryID, packageID = f.store.packageID
        func check() throws -> SharedMediaNativeReceivingIntentGraph.Row {
            let c = f.store.context()
            let inventory = try Fixture.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
            let row = SharedMediaNativeReceivingIntentGraph.Row(try Fixture.one(c,
                FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == packageID })))
            let pending = try Graph.pending(c, inventory: inventory)
            let witness = try #require(pending[packageID])
            guard case .releasing(let snapshot) = witness else { Issue.record("Expected release evidence"); return row }
            #expect(snapshot.release.progress == f.progress)
            #expect(snapshot.release.slot == row && pending.count == 1)
            #expect(witness.identities == [f.prepared.operationID, f.prepared.queueID, f.prepared.observationID,
                f.prepared.bindingID, f.prepared.generation, f.prepared.eventID])
            #expect(!c.hasChanges)
            // This clean classifier does not open generic mutation facts.
            #expect(throws: (any Error).self) { _ = try SharedMediaNativeReceivingPhaseGraph.pending(c, inventory: inventory) }
            #expect(throws: SharedMediaStorageFailure.closed) {
                _ = try Graph.pending(c, inventory: inventory, checkpoint: { throw SharedMediaStorageFailure.closed })
            }
            return row
        }
        let before = try check()
        try f.retirePair(0); _ = try check()
        let current = f.store.context()
        let inventory = try Fixture.one(current, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        #expect(throws: (any Error).self) { _ = try Graph.validate(before, context: current, inventory: inventory) }
        if count == 2 {
            try f.retirePair(1); _ = try check()
            try f.removePair(1); _ = try check()
            try f.retireOriginal(1); _ = try check()
            try f.removeOriginal(1); _ = try check()
        }
        try f.removePair(0); _ = try check()
        try f.retireOriginal(0); _ = try check()
        try f.removeOriginal(0); _ = try check()
        let dirty = f.store.context()
        let inv = try Fixture.one(dirty, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        inv.revision += 1
        #expect(throws: (any Error).self) { _ = try Graph.pending(dirty, inventory: inv) }
        dirty.rollback()
        let corrupt = f.store.context()
        let slot = try Fixture.one(corrupt, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == packageID }))
        let owner = slot.ownerID; slot.ownerID = UUID(); try corrupt.save()
        #expect(throws: (any Error).self) { _ = try check() }
        slot.ownerID = owner; try corrupt.save(); _ = try check()
    }

    @Test func preservesPreparedAbandonedAndReceivedClassification() async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(staged: true)
        let prepared = try SharedMediaNativeReceivingIntent.Prepared(request), id = h.inventoryID
        func check(_ phase: String) throws {
            let c = h.context(), inventory = try Fixture.one(c,
                FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
            guard case .generic(let witness) = try #require(Graph.pending(c, inventory: inventory)[h.packageID]) else {
                Issue.record("Expected generic evidence"); return
            }
            #expect(witness.row.phase == phase && !c.hasChanges)
            #expect(try SharedMediaNativeReceivingPhaseGraph.pending(c, inventory: inventory)[h.packageID]?.row == witness.row)
        }
        try check("prepared")
        let terminal = try await owner.abandonAppReceiving(prepared); try check("abandoned")
        let packageID = h.packageID
        let abandoned = SharedMediaNativeReceivingIntentGraph.Row(try Fixture.one(h.context(),
            FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == packageID })))
        let replacement = try await owner.restageAppReceiving(terminal, draftGeneration: h.draft,
            pairIDs: SharedMediaNativeReceivingStagingTests().pairIDs(request))
        try check("prepared")
        let current = h.context(), inventory = try Fixture.one(current,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
        #expect(throws: SharedMediaStorageFailure.stale) {
            _ = try Graph.validate(abandoned, context: current, inventory: inventory)
        }
        _ = try await owner.receiveAppPrepared(replacement); try check("received")
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test(arguments: [1, 2])
    func scopedAuditAndBudgetFollowIndependentReleaseCleanup(_ count: Int) async throws {
        let f = try await Fixture.make(count: count)
        try await auditAndMeasure(f)
        try f.retirePair(0); try await auditAndMeasure(f)
        if count == 2 {
            try f.retirePair(1); try await auditAndMeasure(f)
            try f.removePair(1); try await auditAndMeasure(f)
            try f.retireOriginal(1); try await auditAndMeasure(f)
            try f.removeOriginal(1); try await auditAndMeasure(f)
        }
        try f.removePair(0); try await auditAndMeasure(f)
        try f.retireOriginal(0); try await auditAndMeasure(f)
        try f.removeOriginal(0); try await auditAndMeasure(f)
    }

    @Test func foreignPendingOriginIsChargedOnceByIntegratedBudget() async throws {
        let f = try await Fixture.make(count: 1, foreignOriginal: true)
        try await auditAndMeasure(f)
        try f.retirePair(0); try await auditAndMeasure(f)
        try f.removePair(0); try await auditAndMeasure(f)
    }

    @Test func releaseOwnedOriginalSurvivesWithoutLocalReference() async throws {
        let f = try await Fixture.make(count: 1)
        try f.retirePair(0); try f.removePair(0)
        let c = f.store.context(), target = f.progress.plan.targets[0], source = target.original
        let destination = PhotoOriginalReference(ownerID: source.ownerID, packageID: UUID(),
            referenceID: UUID(), assetID: source.assetID, assetGeneration: source.assetGeneration,
            draftGeneration: f.store.draft, referenceRevision: 0)
        let package = f.store.row(destination.packageID,
            envelope: try PhotoPreparationPolicy.encodeDraft(contexts: [], presentation: []), phase: "draftOwned")
        let assetID = source.assetID
        let asset = try Fixture.one(c, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID }))
        package.allocatedByteCount = asset.byteCount
        c.insert(package)
        c.insert(try SharedMediaPendingMembershipRecord(packageID: package.id, inventoryID: f.store.inventoryID,
            inventoryGeneration: f.prepared.profile.generation, ownerID: source.ownerID, draftGeneration: destination.draftGeneration,
            membersData: SharedMediaNativeAppOriginalRows.shareMembership(destination, leaseID: target.acquisitionID)))
        c.insert(PhotoPreparationReference(id: destination.referenceID, packageID: package.id, assetID: assetID,
            ownerID: source.ownerID, roleRaw: "original", ordinal: 0, revision: 0, isLive: true))
        c.insert(SharedMediaReferenceRecord(id: destination.referenceID, allocationID: assetID,
            accountID: source.ownerID, ownerID: destination.referenceID.uuidString.lowercased(),
            roleRaw: SharedMediaPhotoLedger.namespace, stateRaw: "live", revision: 0))
        let (ref, edge) = try SharedMediaNativeAppOriginalRows.reference(c, source: source, live: true)
        c.delete(ref); c.delete(edge)
        let count = try Fixture.one(c, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID }))
        count.revision += 2 // Synthetic sharing then local removal; live count is unchanged.
        f.progress = try f.progress.advancing(.init(pairID: target.pairID, stage: .removed,
            pair: f.progress.targets[0].pair, original: .init(disposition: .shared, retirementID: nil,
                closureSHA256: String(repeating: "1", count: 64))))
        try f.save(c)
        try await auditAndMeasure(f)
        let snapshot = try SharedMediaNativeReleaseMetadataSnapshot.read(packageID: f.store.packageID,
            inventoryID: f.store.inventoryID, context: f.store.context())
        #expect(snapshot.ownedOriginals.map(\.assetID) == [assetID])
        #expect(try SharedMediaNativeOriginalLiability.read(context: f.store.context(), inventoryID: f.store.inventoryID).entries.count == 1)
    }

    @Test func integratedAuditRejectsCorruptReleaseAndOrphanSlots() async throws {
        let f = try await Fixture.make(count: 1)
        try await auditAndMeasure(f)
        let c = f.store.context(), id = f.store.packageID
        let row = try Fixture.one(c, FetchDescriptor<SharedMediaReceivingIntentRecord>(predicate: #Predicate { $0.id == id }))
        let hash = row.resultSHA256
        row.resultSHA256 = String(repeating: "0", count: 64); try c.save()
        await #expect(throws: (any Error).self) { try await auditAndMeasure(f) }
        row.resultSHA256 = hash; try c.save(); try await auditAndMeasure(f)
        // The raw slot reverse pass must not ignore a release after its pending
        // root disappears. This is an intentionally corrupt persisted fixture.
        let member = try Fixture.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id }))
        c.delete(member); try c.save()
        await #expect(throws: (any Error).self) { try await auditAndMeasure(f) }
    }

    private func auditAndMeasure(_ f: Fixture) async throws {
        let c = f.store.context(), inventoryID = f.store.inventoryID
        let inventory = try Fixture.one(c,
            FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let profile = try SharedMediaNativeAppEligibility.profile(inventory)
        let expected = SharedMediaStorageSnapshot(generation: inventory.generation,
            revision: inventory.revision, phase: inventory.phaseRaw, cursor: inventory.cursor)
        _ = try await SharedMediaNativeScopedAudit(app: f.store.container, profile: profile,
            expected: expected, check: {}, betweenPages: { await Task.yield() }).run()
        let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c,
            inventory: inventory, ownerID: f.store.ownerID, format: .appV2)
        let identity = try #require(budget.originalIdentity)
        let release = try SharedMediaNativeReleaseMetadataSnapshot.read(packageID: f.store.packageID,
            inventoryID: inventoryID, context: c)
        let projection = try SharedMediaNativeReleaseSurvivorProjection.maximum(release)
        let current = try release.packagePayloadBytes + release.originReceiptBytes
        let future = try projection.charges.map { try $0.packageBytes + $0.originReceiptBytes }
        let maximum = max(current, future.max() ?? 0)
        let outstanding = try maximum - current + identity.reservedBytes
        try budget.totals.checkAvailable(SharedMediaStoragePolicy.reserve + outstanding)
        #expect(throws: SharedMediaStorageFailure.capacity) {
            try budget.totals.checkAvailable(SharedMediaStoragePolicy.reserve + outstanding - 1)
        }
        // Independent fixture inventory sum: all allocations are pending here,
        // including the foreign origin. Padding the real Totals to the durable
        // cap detects both omitted physical bytes and duplicate origin charges.
        let allocations = try c.fetch(FetchDescriptor<SharedMediaAllocationRecord>())
        let physical = try PhotoPreparationPolicy.add(allocations.map { try SharedMediaStoragePolicy.add($0.materializedBytes, $0.reservedBytes) })
        let otherMetadata = try PhotoPreparationPolicy.add(budget.metadataByPackage.filter { $0.key != f.store.packageID }.map(\.value))
        let total = try PhotoPreparationPolicy.add([physical, maximum, otherMetadata, Int64(identity.entries.count) * 512])
        var exact = budget.totals
        try exact.includePhotoPhysical(materialized: PhotoPreparationPolicy.durable - total, reserved: 0)
        #expect(throws: SharedMediaStorageFailure.capacity) {
            try exact.includePhotoPhysical(materialized: 1, reserved: 0)
        }
        #expect(!c.hasChanges)
        // A successful clean audit still cannot feed generic mutation facts.
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeAppMetadataFacts.capture(c, profile: profile)
        }
    }

}

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
                f.prepared.bindingID, f.prepared.generation, f.prepared.eventID, f.progress.plan.releaseID])
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
            let budget = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: c, inventory: inventory,
                ownerID: h.ownerID, format: .appV2)
            let base = try #require(budget.baseMetadataByPackage[h.packageID])
            let charged = try #require(budget.metadataByPackage[h.packageID])
            switch witness.slot {
            case .prepared(let value):
                let future = try SharedMediaNativeReceivingReservation.maximum(value, currentMetadata: base, pairStates: witness.states)
                #expect(charged == base + Int64(try value.encoded().count) + future.reserved)
                #expect(budget.receivedLiabilityByPackage[h.packageID] == nil)
            case .abandoned:
                #expect(charged == base + Int64(try #require(witness.row.resultData).count))
                #expect(budget.receivedLiabilityByPackage[h.packageID] == nil)
            case .received(_, _, let transaction):
                #expect(charged == base + Int64(try #require(witness.row.preparedData).count)
                    + Int64(try #require(witness.row.resultData).count) + 2 * Int64(transaction.metadata.utf8.count))
                #expect(try budget.receivedLiabilityByPackage[h.packageID]?.charged == charged)
            }
            let fresh = h.context()
            let freshInventory = try Fixture.one(fresh, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
            let again = try SharedMediaNativeAcquisitionBudget.evaluateScoped(context: fresh, inventory: freshInventory,
                ownerID: h.ownerID, format: .appV2)
            #expect(again.totals == budget.totals && again.metadataByPackage == budget.metadataByPackage)
            #expect(again.baseMetadataByPackage == budget.baseMetadataByPackage)
            #expect(again.receivedLiabilityByPackage == budget.receivedLiabilityByPackage && again.originalIdentity == budget.originalIdentity)
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

extension SharedMediaNativeReceivingCleanGraphTests {
    typealias ReceivedReader = SharedMediaNativeReceivedReleaseSnapshot
    typealias Store = SharedMediaNativeAppMetadataTests.Store

    @Test(arguments: ["generic-staged", "staged-staged", "live-staged", "live-live"])
    func indexesCoreAndReleaseIdentitiesAcrossIndependentRoots(_ mode: String) async throws {
        let (h, secondID) = try await twoReceived()
        let first = try ReceivedReader.read(packageID: h.packageID, inventoryID: h.inventoryID,
            releaseID: UUID(), context: h.context())
        if mode.hasPrefix("staged") { try stage(first, in: h) }
        if mode.hasPrefix("live") { _ = try live(first, in: h) }
        let second = try ReceivedReader.read(packageID: secondID, inventoryID: h.inventoryID,
            releaseID: UUID(), context: h.context())
        func saveSecond(_ releaseID: UUID) throws {
            if mode.hasSuffix("live") { _ = try live(second, in: h, releaseID: releaseID) }
            else { try stage(second, in: h, releaseID: releaseID) }
        }
        try saveSecond(second.components.progress.plan.releaseID)
        #expect(try roots(h).count == 2)
        try await audit(h)
        let collisions = [first.components.prepared.eventID]
            + (mode.hasPrefix("generic") ? [] : [first.components.progress.plan.releaseID])
        for identity in collisions {
            try saveSecond(identity)
            // Each root is structurally valid alone; the complete index must
            // reject cross-root release/core and release/release substitutions.
            let c = h.context(), inv = try inventory(h, c)
            let row = try #require(try SharedMediaNativeReceivingPhaseGraph.row(secondID, in: c))
            _ = try Graph.validate(.init(row), context: c, inventory: inv)
            #expect(throws: SharedMediaStorageFailure.conflict) { _ = try Graph.pending(c, inventory: inv) }
            await #expect(throws: (any Error).self) { try await audit(h) }
            try saveSecond(second.components.progress.plan.releaseID)
            #expect(try roots(h).count == 2)
        }
    }

    @Test func mixedRunwaySumsEveryRemainingSaveIncludingTerminalConsumption() async throws {
        let (h, secondID) = try await twoReceived()
        let first = try ReceivedReader.read(packageID: h.packageID, inventoryID: h.inventoryID,
            releaseID: UUID(), context: h.context())
        let f = try live(first, in: h)
        let second = try ReceivedReader.read(packageID: secondID, inventoryID: h.inventoryID,
            releaseID: UUID(), context: h.context())
        try stage(second, in: h)
        for terminalOnly in [false, true] {
            if terminalOnly {
                try f.retirePair(0); try f.removePair(0)
                try f.retireOriginal(0); try f.removeOriginal(0)
                #expect(try f.progress.remainingAdvances == 2) // Released + consumption.
            }
            let witnesses = try roots(h)
            let remaining = try PhotoPreparationPolicy.add(witnesses.values.map { try $0.remainingAdvances })
            let c = h.context(), inv = try inventory(h, c), old = inv.revision
            inv.revision = Int64.max - remaining; try c.save()
            #expect(try roots(h).count == 2)
            try await audit(h)
            inv.revision += 1; try c.save()
            let fresh = h.context(), current = try inventory(h, fresh)
            // Both local witnesses still fit individually: only their sum fails.
            for id in [h.packageID, secondID] {
                let row = try #require(try SharedMediaNativeReceivingPhaseGraph.row(id, in: fresh))
                let witness = try Graph.validate(.init(row), context: fresh, inventory: current)
                try Graph.requireAggregateRunway(inventoryRevision: current.revision, witnesses: [witness])
            }
            #expect(throws: (any Error).self) { _ = try roots(h) }
            await #expect(throws: (any Error).self) { try await audit(h) }
            inv.revision = old; try c.save() // Synthetic boundary probe only.
        }
    }

    @Test(arguments: ["partial", "foreign", "orphan", "abandoned", "releasing", "terminal", "terminalOrphan"])
    func stagedRawAuditRejectsUnownedMalformedAndUnsupportedTerminalSlots(_ corruption: String) async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(staged: true)
        _ = try await owner.receiveAppPrepared(.init(request))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let value = try ReceivedReader.read(packageID: h.packageID, inventoryID: h.inventoryID,
            releaseID: UUID(), context: h.context())
        try stage(value, in: h); try await audit(h)
        let c = h.context(), id = h.packageID
        let row = try #require(try SharedMediaNativeReceivingPhaseGraph.row(id, in: c))
        switch corruption {
        case "partial": row.releaseStartSHA256 = nil
        case "foreign": row.ownerID = UUID()
        case "abandoned", "releasing": row.phaseRaw = corruption // Complete sidecar on an incompatible phase.
        case "terminal", "terminalOrphan":
            row.phaseRaw = "released"; row.releaseStartData = nil; row.releaseStartSHA256 = nil
        default: break
        }
        if corruption == "orphan" || corruption == "terminalOrphan" {
            c.delete(try Fixture.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == id })))
        }
        try c.save()
        await #expect(throws: (any Error).self) { try await audit(h) }
        #expect(!c.hasChanges)
    }

    @Test(arguments: [false, true])
    func stagedAuditRebuildsProofAfterPageSuspension(_ headerDrift: Bool) async throws {
        let (h, owner, request) = try await SharedMediaNativeAppReceivingTests().fixture(staged: true)
        _ = try await owner.receiveAppPrepared(.init(request))
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let value = try ReceivedReader.read(packageID: h.packageID, inventoryID: h.inventoryID,
            releaseID: UUID(), context: h.context())
        try stage(value, in: h)
        var changed = false
        await #expect(throws: (any Error).self) {
            try await audit(h) {
                if !changed {
                    changed = true
                    let c = h.context()
                    if headerDrift { try inventory(h, c).revision += 1 }
                    else {
                        let row = try #require(try SharedMediaNativeReceivingPhaseGraph.row(h.packageID, in: c))
                        row.releaseStartSHA256 = String(repeating: "0", count: 64)
                    }
                    try c.save()
                }
                await Task.yield()
            }
        }
        #expect(changed)
    }

    private func inventory(_ h: Store, _ c: ModelContext) throws -> SharedMediaInventoryRecord {
        let id = h.inventoryID
        return try Fixture.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
    }
    private func roots(_ h: Store) throws -> [UUID: Graph.Witness] {
        let c = h.context()
        return try Graph.pending(c, inventory: inventory(h, c))
    }
    private func audit(_ h: Store, betweenPages: @escaping () async throws -> Void = { await Task.yield() }) async throws {
        let c = h.context(), inv = try inventory(h, c)
        _ = try await SharedMediaNativeScopedAudit(app: h.container,
            profile: SharedMediaNativeAppEligibility.profile(inv),
            expected: .init(generation: inv.generation, revision: inv.revision, phase: inv.phaseRaw, cursor: inv.cursor),
            check: {}, betweenPages: betweenPages).run()
    }
    private func stage(_ value: ReceivedReader.Snapshot, in h: Store, releaseID: UUID? = nil) throws {
        let c = h.context(), inv = try inventory(h, c)
        let request = try SharedMediaNativeReleaseStartRequest(prepared: value.components.prepared,
            received: value.components.received, stagePreHeader: value.header,
            releaseID: releaseID ?? value.components.progress.plan.releaseID)
        let bytes = try request.encoding()
        let row = try #require(try SharedMediaNativeReceivingPhaseGraph.row(value.slot.id, in: c))
        row.releaseStartData = bytes.data; row.releaseStartSHA256 = bytes.sha256
        inv.revision += 1; try c.save()
    }
    @discardableResult
    private func live(_ value: ReceivedReader.Snapshot, in h: Store, releaseID: UUID? = nil) throws -> Fixture {
        let plan = try Fixture.Values.Plan(prepared: value.components.prepared, received: value.components.received,
            header: value.header, releaseID: releaseID ?? value.components.progress.plan.releaseID,
            acquisitionIDs: value.components.progress.plan.targets.map(\.acquisitionID))
        let f = try Fixture(store: h, prepared: value.components.prepared, received: value.components.received, plan: plan)
        try f.save(h.context()); return f
    }
    private func twoReceived() async throws -> (Store, UUID) {
        let (h, owner, first) = try await SharedMediaNativeAppReceivingTests().fixture(staged: true)
        _ = try await owner.receiveAppPrepared(.init(first))
        let c = h.context(), inv = try inventory(h, c), id = UUID(), draft = UUID()
        // Only an empty draft is seeded. Its media and receiving rows are made
        // by the real owner in this same store; no unrelated graph is copied.
        c.insert(PhotoPreparationRecord(id: id, ownerID: h.ownerID, contractVersion: PhotoPreparationPolicy.contract,
            draftID: id, draftGeneration: draft, revision: 0, phaseRaw: "draftOwned",
            supportingContextData: try PhotoPreparationPolicy.encodeDraft(contexts: [], presentation: []),
            allocatedByteCount: 0, retirementRequested: false))
        c.insert(SharedMediaPendingMembershipRecord(packageID: id, inventoryID: inv.id,
            inventoryGeneration: inv.generation, ownerID: h.ownerID, draftGeneration: draft,
            membersData: try SharedMediaMembership(groups: []).encoded()))
        try c.save()
        let metadata = try await owner.prepareAppMetadata(packageID: id, draftGeneration: draft,
            contexts: [.init(freeText: "Independent second submitted description")])
        _ = try await owner.saveAppMetadata(metadata)
        let request = try await owner.prepareAppOriginal(packageID: id, draftGeneration: draft, ordinal: 0, kind: .picker)
        let data = PhotoPreparationTestHarness.image()
        let acquired = try await owner.acquireAppOriginal(request) { data }
        let original = PhotoOriginalReference(ownerID: h.ownerID, packageID: id, referenceID: request.referenceID,
            assetID: request.assetID, assetGeneration: request.assetGeneration, draftGeneration: draft,
            referenceRevision: acquired.referenceRevision)
        let ready = try await owner.prepareAndDeliverAppPhoto(original: original,
            recipe: .init(format: .stillImage, isPro: false, cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0))
        let prepared = try await owner.stageAppReceiving(packageID: id, draftGeneration: draft,
            pairIDs: [ready.intent().pairID])
        _ = try await owner.receiveAppPrepared(prepared)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        return (h, id)
    }
}

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
}

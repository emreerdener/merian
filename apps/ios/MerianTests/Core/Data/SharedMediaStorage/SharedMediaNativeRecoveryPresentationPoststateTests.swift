import Foundation
import SwiftData
import Testing
@testable import Merian

@Suite("Native recovery presentation transaction seals", .serialized, .sharedProcessState(.offlineQueueManager))
@MainActor
struct SharedMediaNativeRecoveryPresentationPoststateTests {
    typealias Proof = SharedMediaNativeRecoveryPresentationPoststate
    typealias Store = SharedMediaNativeAppMetadataTests.Store

    private func inventory(_ h: Store, _ c: ModelContext) throws -> SharedMediaInventoryRecord {
        let id = h.inventoryID
        return try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == id }))
    }
    private func queue(_ p: SharedMediaNativeReceivingIntent.Prepared, _ c: ModelContext) throws -> OfflineQueuedScan {
        let id = p.queueID.uuidString.lowercased()
        return try SharedMediaNativePairPlanGraph.one(c, FetchDescriptor<OfflineQueuedScan>(predicate: #Predicate { $0.id == id }))
    }
    private func apply(_ proof: Proof, _ h: Store, _ p: SharedMediaNativeReceivingIntent.Prepared) throws {
        let c = h.context(), inv = try inventory(h, c)
        try proof.requirePredecessor(c, inventory: inv)
        try queue(p, c).recoveryPresentationData = proof.successor.encoded()
        inv.revision += 1
        try proof.validate(c, inventory: inv)
        try c.save()
        let fresh = h.context()
        try proof.requirePersisted(fresh, inventory: inventory(h, fresh))
    }

    @Test func exactReserveSettleProofPreservesClosedOrdinaryReader() async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let c = h.context(), inv = try inventory(h, c), original = inv.revision
        let proof = try Proof(prepared: p, reservationID: UUID(), context: c, inventory: inv)
        #expect(proof.successor.revision == 1 && proof.successor.needsAttention)
        // Test-only persistence of the exact write set. No owner admission,
        // byte-capacity proof or presentation acknowledgement is claimed here.
        try apply(proof, h, p)
        let saved = h.context(), savedInventory = try inventory(h, saved)
        #expect(savedInventory.revision == original + 1)
        #expect(throws: (any Error).self) {
            _ = try SharedMediaNativeReceivingRows.read(proof.transaction, in: saved, absent: false)
        }
        #expect(throws: (any Error).self) { try proof.requirePredecessor(saved, inventory: savedInventory) }
        #expect(throws: (any Error).self) { _ = try proof.reserving(id: UUID(), context: saved, inventory: savedInventory) }
        let settled = try proof.settling(elapsed: .nanoseconds(1), context: saved, inventory: savedInventory)
        #expect(settled.successor.revision == 2 && settled.successor.chargedMilliseconds == 1)
        try apply(settled, h, p)
        let next = h.context(), nextInventory = try inventory(h, next)
        #expect(throws: (any Error).self) { _ = try proof.settling(elapsed: .zero, context: next, inventory: nextInventory) }
        #expect(throws: (any Error).self) { _ = try settled.settling(elapsed: .zero, context: next, inventory: nextInventory) }
        let reservedAgain = try settled.reserving(id: UUID(), context: next, inventory: nextInventory)
        #expect(reservedAgain.successor.revision == 3)
        try apply(reservedAgain, h, p)
        let cold = h.context()
        #expect(throws: (any Error).self) {
            _ = try Proof(prepared: p, reservationID: UUID(), context: cold, inventory: inventory(h, cold))
        }
    }

    @Test func interleavedInventoryProgressCannotRefreshSettlementProof() async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let c = h.context()
        let proof = try Proof(prepared: p, reservationID: UUID(), context: c, inventory: inventory(h, c))
        try apply(proof, h, p)
        let interleaved = h.context()
        try inventory(h, interleaved).revision += 1; try interleaved.save()
        let fresh = h.context(), current = try inventory(h, fresh)
        #expect(throws: (any Error).self) { _ = try proof.settling(elapsed: .zero, context: fresh, inventory: current) }
        #expect(throws: (any Error).self) { _ = try proof.reserving(id: UUID(), context: fresh, inventory: current) }
        #expect(try queue(p, fresh).recoveryPresentationData == proof.successor.encoded())
        #expect(!fresh.hasChanges)
    }

    @Test func rejectsExtraWritesChangedPredecessorsAndLostQueue() async throws {
        let (h, owner, p) = try await SharedMediaNativePhotoAllocationTests().fixture()
        #expect(await owner.invalidateAndAwaitForAccountTransition())
        let c = h.context(), inv = try inventory(h, c)
        let proof = try Proof(prepared: p, reservationID: UUID(), context: c, inventory: inv)
        try queue(p, c).recoveryPresentationData = proof.successor.encoded(); inv.revision += 1
        try proof.validate(c, inventory: inv)
        try queue(p, c).fieldNotes = "unexpected mutation"
        #expect(throws: (any Error).self) { try proof.validate(c, inventory: inv) }
        c.rollback()
        let changed = h.context(), changedQueue = try queue(p, changed)
        let alternate = try AnalysisRecoveryPresentation.initial(for: proof.successor.identity).reserve(id: UUID())
        changedQueue.recoveryPresentationData = try alternate.reserved.encoded(); try changed.save()
        let fresh = h.context()
        #expect(throws: (any Error).self) { try proof.requirePredecessor(fresh, inventory: inventory(h, fresh)) }
        changedQueue.recoveryPresentationData = nil; try changed.save()
        let slotContext = h.context()
        let row = try #require(try SharedMediaNativeReceivingPhaseGraph.row(p.package.id, in: slotContext))
        row.releaseStartData = Data([1]); try slotContext.save()
        let staged = h.context()
        #expect(throws: (any Error).self) { try proof.requirePredecessor(staged, inventory: inventory(h, staged)) }
        row.releaseStartData = nil; try slotContext.save()
        let deleted = h.context(); deleted.delete(try queue(p, deleted)); try deleted.save()
        let afterDeletion = h.context()
        #expect(throws: (any Error).self) { try proof.requirePredecessor(afterDeletion, inventory: inventory(h, afterDeletion)) }
    }
}

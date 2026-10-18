import Foundation
import SwiftData

/// Exact explicit-abandonment and synced-absence transitions. Every instance
/// starts from a pristine graph under the existing native mutation authority.
@MainActor
final class SharedMediaNativePendingCleanup {
    private let container: ModelContainer, context: ModelContext
    private let inventory: SharedMediaInventoryRecord
    private let authority: SharedMediaNativeMutationAuthority
    init(container: ModelContainer, inventoryID: UUID, authority: SharedMediaNativeMutationAuthority) throws {
        try authority.validate()
        self.container = container; self.authority = authority
        context = ModelContext(container); context.autosaveEnabled = false
        inventory = try Self.one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        guard authority.binding.bytes == (try JSONEncoder().encode(["nativeQualificationV1", inventory.id.uuidString, inventory.storeIdentity, inventory.rootIdentity])) else { throw SharedMediaStorageFailure.conflict }
        try SharedMediaNativeAcquisitionGraph.audit(context: context, inventoryID: inventoryID)
    }
    func state(_ request: SharedMediaAcquisitionIntent) throws -> SharedMediaNativePendingState {
        try request.validate()
        guard request.ownerID == authority.ownerID, request.inventoryID == inventory.id,
              request.inventoryGeneration == inventory.generation else { throw SharedMediaStorageFailure.conflict }
        let operationID = request.operationID, packageID = request.packageID
        let receipt = try Self.one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == operationID }))
        switch try SharedMediaAcquisitionReceipt.read(receipt, expected: request) {
        case .reserved, .held: break
        default: throw SharedMediaStorageFailure.stale
        }
        let package = try Self.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let member = try Self.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        let work = try Self.one(context, FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == operationID }))
        let closure = try work.terminalProof.map { try SharedMediaNativePendingClosure.decode($0, request: request) }
        return .init(request: request, receiptPhase: receipt.phaseRaw, receiptRevision: receipt.revision,
            inventoryRevision: inventory.revision, packageRevision: package.revision, membershipRevision: member.revision,
            membershipBytes: member.membersData, envelope: package.supportingContextData,
            allocatedBytes: package.allocatedByteCount, phase: package.phaseRaw, closure: closure)
    }
    func nextSavedAbandonment() throws -> SharedMediaAcquisitionIntent? {
        var query = FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.writerStateRaw == "closedPendingCleanupV1" }, sortBy: [SortDescriptor(\.id)])
        query.fetchLimit = 1
        guard let work = try context.fetch(query).first else { return nil }
        let id = work.id
        let receipt = try Self.one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }))
        switch try SharedMediaAcquisitionReceipt.read(receipt) {
        case .reserved(let request), .held(let request):
            guard try state(request).closure != nil else { throw SharedMediaStorageFailure.conflict }; return request
        default: throw SharedMediaStorageFailure.conflict
        }
    }
    func abandon(_ before: SharedMediaNativePendingState, proof: SharedMediaNativePendingInspection,
                 beforeSave: () throws -> Void, afterSave: () throws -> Void) throws {
        guard before.closure == nil, proof.binding == authority.binding.bytes, proof.epoch == authority.binding.epoch else { throw SharedMediaStorageFailure.conflict }
        try requireBefore(before)
        let encoded = try proof.closure.encoded(request: before.request)
        guard encoded.utf8.count <= SharedMediaAcquisitionResult.reservedEncodingBytes else { throw SharedMediaStorageFailure.capacity }
        let id = before.request.operationID, assetID = before.request.assetID, packageID = before.request.packageID
        let allocation = try Self.one(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID }))
        let lease = try Self.one(context, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == id }))
        let work = try Self.one(context, FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == id }))
        let package = try Self.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        allocation.stateRaw = "p1PendingCleanupV1"; lease.stateRaw = "closedPendingCleanupV1"
        work.writerStateRaw = "closedPendingCleanupV1"; work.terminalProof = encoded
        package.phaseRaw = "needsAttention"; package.revision = try increment(package.revision)
        inventory.revision = try increment(inventory.revision)
        try abandonedResult(before, closure: proof.closure)
        _ = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
        try beforeSave(); try requireBefore(before)
        do { try context.save() } catch { context.rollback(); throw error }; try afterSave()
    }
    func abandonedResult(_ before: SharedMediaNativePendingState, closure: SharedMediaNativePendingClosure) throws {
        let actual = try state(before.request)
        let expected = SharedMediaNativePendingState(request: before.request, receiptPhase: before.receiptPhase, receiptRevision: before.receiptRevision,
            inventoryRevision: try increment(before.inventoryRevision), packageRevision: try increment(before.packageRevision),
            membershipRevision: before.membershipRevision, membershipBytes: before.membershipBytes,
            envelope: before.envelope, allocatedBytes: before.allocatedBytes, phase: "needsAttention", closure: closure)
        guard actual == expected else { throw SharedMediaStorageFailure.stale }
    }
    func release(_ proof: SharedMediaNativePendingAbsence, beforeSave: () throws -> Void, afterSave: () throws -> Void) throws {
        let disposal = proof.disposal, before = disposal.state
        guard before.closure != nil, disposal.binding == authority.binding.bytes, disposal.epoch == authority.binding.epoch else { throw SharedMediaStorageFailure.conflict }
        try requireBefore(before)
        let id = before.request.operationID, assetID = before.request.assetID, packageID = before.request.packageID
        let receipt = try Self.one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }))
        let package = try Self.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let member = try Self.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        context.delete(try Self.one(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID })))
        context.delete(try Self.one(context, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == id })))
        context.delete(try Self.one(context, FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == id })))
        receipt.phaseRaw = "terminal"; receipt.revision = 2; receipt.terminalOutcomeRaw = "released"
        receipt.requestData = nil; receipt.resultData = nil; receipt.packageID = nil; receipt.assetID = nil
        package.phaseRaw = try remainingPhase(packageID); package.revision = try increment(package.revision)
        inventory.revision = try increment(inventory.revision)
        member.membersData = try Self.successor(before); member.revision = try increment(member.revision)
        try releasedResult(before)
        _ = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
        try beforeSave(); try requireBefore(before)
        do { try context.save() } catch { context.rollback(); throw error }; try afterSave()
    }
    func releasedResult(_ before: SharedMediaNativePendingState) throws {
        let id = before.request.operationID, packageID = before.request.packageID
        let receipt = try Self.one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }))
        guard case .released = try SharedMediaAcquisitionReceipt.read(receipt, expected: before.request) else { throw SharedMediaStorageFailure.stale }
        let package = try Self.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let member = try Self.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        guard before.request.ownerID == authority.ownerID, before.request.inventoryID == inventory.id,
              before.request.inventoryGeneration == inventory.generation,
              inventory.revision == (try increment(before.inventoryRevision)), package.revision == (try increment(before.packageRevision)),
              member.revision == (try increment(before.membershipRevision)), member.membersData == (try Self.successor(before)),
              package.ownerID == authority.ownerID, package.draftGeneration == before.request.draftGeneration,
              package.supportingContextData == before.envelope, package.allocatedByteCount == before.allocatedBytes,
              package.accountingTierRaw == "pending", !package.retirementRequested,
              package.phaseRaw == (try remainingPhase(packageID)) else { throw SharedMediaStorageFailure.stale }
        try SharedMediaPendingGraph.derive(in: context, inventory: inventory).validateMembership(in: context, inventory: inventory)
    }
    private func remainingPhase(_ packageID: UUID) throws -> String {
        var query = FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.packageID == packageID }); query.fetchLimit = 3
        let jobs = try context.fetch(query)
        guard jobs.count <= 2 else { throw SharedMediaStorageFailure.conflict }
        var attention = false
        for work in jobs {
            let id = work.id
            let row = try Self.one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }))
            switch try SharedMediaAcquisitionReceipt.read(row) {
            case .held: attention = true
            case .reserved: attention = attention || work.writerStateRaw == "closedPendingCleanupV1"
            default: throw SharedMediaStorageFailure.conflict
            }
        }
        return attention ? "needsAttention" : (jobs.isEmpty ? "draftOwned" : "acquiring")
    }
    private func requireBefore(_ before: SharedMediaNativePendingState) throws {
        let fresh = try Self(container: container, inventoryID: inventory.id, authority: authority)
        guard try fresh.state(before.request) == before else { throw SharedMediaStorageFailure.stale }
    }
    private static func successor(_ before: SharedMediaNativePendingState) throws -> Data {
        let old = try SharedMediaMembership.decode(before.membershipBytes)
        let removals: [SharedMediaMembership.Kind: UUID] = [.work: before.request.operationID, .lease: before.request.operationID, .allocation: before.request.assetID]
        for (kind, id) in removals { guard old.ids(kind).contains(id) else { throw SharedMediaStorageFailure.conflict } }
        return try SharedMediaMembership(groups: old.groups.compactMap { group in
            let ids = group.ids.filter { $0 != removals[group.kind] }; return ids.isEmpty ? nil : .init(kind: group.kind, ids: ids)
        }).encoded()
    }
    private func increment(_ value: Int64) throws -> Int64 { try SharedMediaStoragePolicy.add(value, 1) }
    private static func one<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> T {
        var query = descriptor; query.fetchLimit = 2; let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }; return row
    }
}

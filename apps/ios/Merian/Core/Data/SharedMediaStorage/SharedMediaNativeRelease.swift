import Foundation
import SwiftData

/// Accounting release requires the namespace owner's unforgeable synced-absence
/// proof and the identical saved retirement. There is no token-only deletion.
@MainActor
final class SharedMediaNativeRelease {
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
    func result(_ state: SharedMediaNativeRetirementState) throws {
        try authority.validate()
        let operationID = state.request.operationID, packageID = state.reference.packageID
        let receipt = try Self.one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == operationID }))
        guard case .released = try SharedMediaAcquisitionReceipt.read(receipt, expected: state.request) else { throw SharedMediaStorageFailure.stale }
        let package = try Self.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let member = try Self.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        guard state.request.ownerID == authority.ownerID, state.request.inventoryID == inventory.id,
              state.request.inventoryGeneration == inventory.generation,
              inventory.revision == (try SharedMediaStoragePolicy.add(state.inventoryRevision, 1)),
              package.revision == (try SharedMediaStoragePolicy.add(state.packageRevision, 1)),
              member.revision == (try SharedMediaStoragePolicy.add(state.membershipRevision, 1)),
              package.supportingContextData == state.envelope, package.draftGeneration == state.reference.draftGeneration,
              package.ownerID == authority.ownerID, package.accountingTierRaw == "pending", !package.retirementRequested else { throw SharedMediaStorageFailure.stale }
        let expected = try SharedMediaNativeLifecycleMembership.removing(state.membershipBytes, referenceID: state.reference.referenceID,
            assetID: state.file.assetID, leaseID: state.request.operationID, removeAsset: true)
        guard member.membersData == expected else { throw SharedMediaStorageFailure.stale }
        try SharedMediaPendingGraph.derive(in: context, inventory: inventory).validateMembership(in: context, inventory: inventory)
    }
    func apply(_ proof: SharedMediaNativeReleaseProof, beforeSave: () throws -> Void, afterSave: () throws -> Void) throws {
        let retirement = proof.retirement, state = retirement.state
        guard retirement.binding == authority.binding.bytes, retirement.epoch == authority.binding.epoch else { throw SharedMediaStorageFailure.conflict }
        if (try? result(state)) != nil { return }
        try requireBefore(state)
        let assetID = state.file.assetID, referenceID = state.reference.referenceID
        let packageID = state.reference.packageID, operationID = state.request.operationID
        let package = try Self.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let member = try Self.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        let receipt = try Self.one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == operationID }))
        context.delete(try Self.one(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == referenceID })))
        context.delete(try Self.one(context, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == referenceID })))
        context.delete(try Self.one(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID })))
        context.delete(try Self.one(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID })))
        context.delete(try Self.one(context, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID })))
        context.delete(try Self.one(context, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == operationID })))
        receipt.phaseRaw = "terminal"; receipt.revision = 2; receipt.terminalOutcomeRaw = "released"
        receipt.requestData = nil; receipt.resultData = nil; receipt.packageID = nil; receipt.assetID = nil
        package.allocatedByteCount -= state.file.byteCount
        guard package.allocatedByteCount >= 0 else { throw SharedMediaStorageFailure.conflict }
        package.revision = try SharedMediaStoragePolicy.add(package.revision, 1)
        inventory.revision = try SharedMediaStoragePolicy.add(inventory.revision, 1)
        member.membersData = try SharedMediaPendingGraph.derive(in: context, inventory: inventory).membership(packageID: packageID).encoded()
        member.revision = try SharedMediaStoragePolicy.add(member.revision, 1)
        try result(state)
        _ = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
        try beforeSave()
        try requireBefore(state)
        do { try context.save() } catch { context.rollback(); throw error }
        try afterSave()
    }
    private func requireBefore(_ state: SharedMediaNativeRetirementState) throws {
        let saved = try SharedMediaNativeRemoval(container: container, inventoryID: inventory.id, authority: authority).retirement(assetID: state.file.assetID)
        guard saved == state else { throw SharedMediaStorageFailure.stale }
    }
    private static func one<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>) throws -> T {
        var query = query; query.fetchLimit = 2; let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }; return row
    }
}

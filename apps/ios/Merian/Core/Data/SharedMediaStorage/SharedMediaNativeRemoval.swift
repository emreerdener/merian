import Foundation
import SwiftData

/// Logical removal and saved retirement readback. Physical release is separate:
/// no missing row or unsaved mutation can authorize an unlink.
@MainActor
final class SharedMediaNativeRemoval {
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
    func prepare(_ source: PhotoOriginalReference) throws -> SharedMediaNativeRemovalRequest {
        let rows = try resolve(source, live: true)
        try requireNoRecovery()
        let previous = try PhotoPreparationPolicy.decodeDraft(rows.package.supportingContextData)
        return .init(source: source, inventoryID: inventory.id, inventoryGeneration: inventory.generation,
            inventoryRevision: inventory.revision, packageRevision: rows.package.revision, membershipRevision: rows.member.revision,
            membershipBytes: rows.member.membersData, previousEnvelope: rows.package.supportingContextData,
            envelope: try PhotoPreparationPolicy.encodeDraft(contexts: previous.contexts, presentation: previous.presentation.filter { $0.referenceID != source.referenceID }),
            liveCount: rows.count.liveCount, countRevision: rows.count.revision, retirementID: UUID())
    }
    func file(_ request: SharedMediaNativeRemovalRequest) throws -> PhotoPreparationFile {
        try requireBefore(request)
        return Self.file(try resolve(request.source, live: true).asset)
    }
    func result(_ request: SharedMediaNativeRemovalRequest) throws {
        try validate(request)
        let id = request.source.referenceID, assetID = request.source.assetID, packageID = request.source.packageID
        let package = try Self.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let member = try Self.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        let count = try Self.one(context, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID }))
        guard inventory.revision == request.inventoryRevision + 1, package.revision == request.packageRevision + 1,
              package.ownerID == authority.ownerID, package.draftGeneration == request.source.draftGeneration,
              package.accountingTierRaw == "pending", !package.retirementRequested,
              package.supportingContextData == request.envelope, member.revision == request.membershipRevision + 1,
              count.liveCount == request.liveCount - 1, count.revision == request.countRevision + 1 else { throw SharedMediaStorageFailure.stale }
        if request.liveCount == 1 {
            let rows = try resolve(request.source, live: false)
            guard rows.count.retirementID == request.retirementID, rows.asset.cleanupStateRaw == "retiring",
                  rows.allocation.stateRaw == SharedMediaNativeRetirementIdentity.allocationState,
                  let identity = rows.allocation.physicalIdentity,
                  try SharedMediaNativeRetirementIdentity.decode(identity).retirementID == request.retirementID else { throw SharedMediaStorageFailure.stale }
        } else {
            guard count.retirementID == nil,
                  try context.fetchCount(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == id })) == 0,
                  try context.fetchCount(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == id })) == 0 else { throw SharedMediaStorageFailure.stale }
        }
        let expectedMembers: Data
        if request.liveCount == 1 { expectedMembers = request.membershipBytes }
        else {
            let lease = try Self.one(context, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.allocationID == assetID }))
            let survivors = try context.fetchCount(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.packageID == packageID && $0.assetID == assetID }))
            expectedMembers = try SharedMediaNativeLifecycleMembership.removing(request.membershipBytes, referenceID: id,
                assetID: assetID, leaseID: lease.id, removeAsset: survivors == 0)
        }
        guard member.membersData == expectedMembers else { throw SharedMediaStorageFailure.stale }
        try SharedMediaPendingGraph.derive(in: context, inventory: inventory).validateMembership(in: context, inventory: inventory)
    }
    func apply(_ request: SharedMediaNativeRemovalRequest, proof: SharedMediaPhotoRetirementInspection?,
               beforeSave: () throws -> Void, afterSave: () throws -> Void) throws {
        try validate(request)
        try requireBefore(request)
        let rows = try resolve(request.source, live: true)
        if request.liveCount == 1 {
            guard let proof, proof.binding == authority.binding.bytes, proof.epoch == authority.binding.epoch,
                  proof.file == Self.file(rows.asset), proof.identity.file == rows.allocation.physicalIdentity else { throw SharedMediaStorageFailure.conflict }
            let saved = try SharedMediaNativeRetirementIdentity(retirementID: request.retirementID, assetID: rows.asset.id,
                assetGeneration: rows.asset.generation, inventoryID: inventory.id, inventoryGeneration: inventory.generation,
                ownerID: authority.ownerID, proof: proof.identity)
            // Immutable completion descriptor is the same object, parent and namespace.
            let assetID = rows.asset.id
            let receipt = try Self.one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID }))
            guard case .completed(_, let result) = try SharedMediaAcquisitionReceipt.read(receipt), result.descriptor == proof.identity else { throw SharedMediaStorageFailure.conflict }
            rows.ref.isLive = false; rows.ref.revision = try plus(rows.ref.revision)
            rows.edge.stateRaw = "retired"; rows.edge.revision = rows.ref.revision
            rows.asset.cleanupStateRaw = "retiring"; rows.count.retirementID = request.retirementID
            rows.allocation.stateRaw = SharedMediaNativeRetirementIdentity.allocationState; rows.allocation.physicalIdentity = try saved.encoded()
        } else {
            context.delete(rows.ref); context.delete(rows.edge)
            rows.package.allocatedByteCount -= rows.asset.byteCount
        }
        rows.count.liveCount -= 1; rows.count.revision = try plus(rows.count.revision)
        rows.package.supportingContextData = request.envelope; rows.package.revision = try plus(rows.package.revision)
        inventory.revision = try plus(inventory.revision)
        rows.member.membersData = try SharedMediaPendingGraph.derive(in: context, inventory: inventory).membership(packageID: rows.package.id).encoded()
        rows.member.revision = try plus(rows.member.revision)
        try result(request)
        _ = try SharedMediaNativeAcquisitionBudget.evaluate(context: context, inventory: inventory)
        try beforeSave()
        try Self(container: container, inventoryID: inventory.id, authority: authority).requireBefore(request)
        do { try context.save() } catch { context.rollback(); throw error }
        try afterSave()
    }
    func retirement(assetID: UUID) throws -> SharedMediaNativeRetirementState {
        try authority.validate()
        let snapshot = try SharedMediaNativeOriginalAccounting.audit(assetID: assetID, inventoryID: inventory.id, context: context)
        guard let identity = snapshot.retirement, snapshot.ownerID == authority.ownerID else { throw SharedMediaStorageFailure.stale }
        let receipt = try Self.one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID }))
        guard case .completed(let request, _) = try SharedMediaAcquisitionReceipt.read(receipt) else { throw SharedMediaStorageFailure.conflict }
        let ref = try Self.one(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.assetID == assetID }))
        let packageID = ref.packageID
        let package = try Self.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let member = try Self.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        guard package.accountingTierRaw == "pending", package.ownerID == authority.ownerID, !package.retirementRequested else { throw SharedMediaStorageFailure.closed }
        return .init(request: request,
            file: .init(assetID: assetID, generation: snapshot.assetGeneration, token: snapshot.fileToken, byteCount: snapshot.byteCount, sha256: snapshot.sha256, contentType: snapshot.contentType),
            identity: identity, reference: .init(ownerID: ref.ownerID, packageID: packageID, referenceID: ref.id, assetID: assetID,
                assetGeneration: snapshot.assetGeneration, draftGeneration: package.draftGeneration, referenceRevision: ref.revision - 1),
            inventoryRevision: inventory.revision, packageRevision: package.revision, membershipRevision: member.revision,
            countRevision: snapshot.countRevision, membershipBytes: member.membersData, envelope: package.supportingContextData)
    }
    /// Bounded discovery. The caller settles a page before requesting the next.
    func nextRetirementAsset() throws -> UUID? {
        try authority.validate()
        var q = FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.liveCount == 0 }, sortBy: [SortDescriptor(\.id)])
        q.fetchLimit = 1
        return try context.fetch(q).first?.id
    }
    private func requireBefore(_ request: SharedMediaNativeRemovalRequest) throws {
        try validate(request); try requireNoRecovery()
        let rows = try resolve(request.source, live: true)
        guard inventory.revision == request.inventoryRevision, rows.package.revision == request.packageRevision,
              rows.member.revision == request.membershipRevision, rows.member.membersData == request.membershipBytes,
              rows.package.supportingContextData == request.previousEnvelope,
              rows.count.liveCount == request.liveCount, rows.count.revision == request.countRevision else { throw SharedMediaStorageFailure.stale }
    }
    private func validate(_ request: SharedMediaNativeRemovalRequest) throws {
        try authority.validate(); try request.source.validate()
        guard request.inventoryID == inventory.id, request.inventoryGeneration == inventory.generation,
              request.source.ownerID == authority.ownerID,
              [request.inventoryRevision, request.packageRevision, request.membershipRevision, request.countRevision].allSatisfy({ $0 >= 0 && $0 < Int64.max }),
              request.source.referenceRevision < Int64.max, request.liveCount > 0 else { throw SharedMediaStorageFailure.stale }
        let before = try PhotoPreparationPolicy.decodeDraft(request.previousEnvelope), after = try PhotoPreparationPolicy.decodeDraft(request.envelope)
        // Context equality is semantic; exact desired envelope bytes are retained in the intent.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard before.contexts == after.contexts,
              try encoder.encode(after.presentation) == encoder.encode(before.presentation.filter({ $0.referenceID != request.source.referenceID })) else { throw SharedMediaStorageFailure.conflict }
    }
    private struct Rows {
        let package: PhotoPreparationRecord, member: SharedMediaPendingMembershipRecord
        let ref: PhotoPreparationReference, edge: SharedMediaReferenceRecord, asset: PhotoPreparationAsset
        let allocation: SharedMediaAllocationRecord, count: SharedMediaAssetReferenceCountRecord
    }
    private func resolve(_ handle: PhotoOriginalReference, live: Bool) throws -> Rows {
        let id = handle.referenceID, assetID = handle.assetID, packageID = handle.packageID
        let package = try Self.one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        let member = try Self.one(context, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        let ref = try Self.one(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == id }))
        let edge = try Self.one(context, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == id }))
        let asset = try Self.one(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID }))
        let allocation = try Self.one(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID }))
        let count = try Self.one(context, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID }))
        guard handle.ownerID == authority.ownerID, package.ownerID == handle.ownerID, package.draftGeneration == handle.draftGeneration,
              package.accountingTierRaw == "pending", package.phaseRaw == "draftOwned", !package.retirementRequested,
              ref.ownerID == handle.ownerID, ref.packageID == packageID, ref.assetID == assetID, ref.isLive == live,
              ref.revision == (try SharedMediaStoragePolicy.add(handle.referenceRevision, live ? 0 : 1)),
              asset.generation == handle.assetGeneration, count.assetGeneration == handle.assetGeneration,
              count.liveCount == (live ? count.liveCount : 0), !live || count.liveCount > 0 else { throw SharedMediaStorageFailure.stale }
        return .init(package: package, member: member, ref: ref, edge: edge, asset: asset, allocation: allocation, count: count)
    }
    private func requireNoRecovery() throws {
        guard try context.fetchCount(FetchDescriptor<PhotoPreparationLease>()) == 0,
              try context.fetchCount(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.cleanupStateRaw != "ready" })) == 0 else { throw PhotoPreparationFailure.cleanupPending }
    }
    private func plus(_ value: Int64) throws -> Int64 { try SharedMediaStoragePolicy.add(value, 1) }
    private static func file(_ asset: PhotoPreparationAsset) -> PhotoPreparationFile {
        .init(assetID: asset.id, generation: asset.generation, token: asset.fileToken, byteCount: asset.byteCount, sha256: asset.sha256, contentType: asset.contentType)
    }
    private static func one<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>) throws -> T {
        var query = query; query.fetchLimit = 2; let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }; return row
    }
}

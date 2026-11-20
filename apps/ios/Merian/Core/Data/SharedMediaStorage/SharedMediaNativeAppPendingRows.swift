import Foundation
import SwiftData

/// Exact reservation rows. This value has no save or file authority.
@MainActor
struct SharedMediaNativeAppPendingRows {
    let inventory: SharedMediaInventoryRecord
    let package: PhotoPreparationRecord
    let member: SharedMediaPendingMembershipRecord
    let receipt: SharedMediaAcquisitionReceiptRecord
    let allocation: SharedMediaAllocationRecord
    let lease: SharedMediaLeaseRecord
    let work: PhotoPreparationLease

    init(_ c: ModelContext, request r: SharedMediaAcquisitionIntent) throws {
        let inventoryID = r.inventoryID, packageID = r.packageID, id = r.operationID, assetID = r.assetID
        inventory = try Self.one(c, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        package = try Self.one(c, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        member = try Self.one(c, FetchDescriptor<SharedMediaPendingMembershipRecord>(predicate: #Predicate { $0.id == packageID }))
        receipt = try Self.one(c, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }))
        allocation = try Self.one(c, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID }))
        lease = try Self.one(c, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == id }))
        work = try Self.one(c, FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == id }))
    }
    func state(_ r: SharedMediaAcquisitionIntent) throws -> SharedMediaNativePendingState {
        let held: Bool
        switch try SharedMediaAcquisitionReceipt.read(receipt, expected: r) {
        case .held: held = true
        case .reserved: held = false
        default: throw SharedMediaStorageFailure.stale
        }
        let closure = try work.terminalProof.map { try SharedMediaNativePendingClosure.decode($0, request: r) }
        let closed = closure != nil
        guard allocation.inventoryID == r.inventoryID, allocation.accountID == r.ownerID,
              allocation.packageID == r.packageID, allocation.namespaceRaw == SharedMediaPhotoLedger.namespace,
              allocation.poolRaw == "durable", allocation.fileToken == r.finalToken,
              allocation.stateRaw == (closed ? "p1PendingCleanupV1" : (held ? "p1Held" : "p1Reserved")),
              allocation.materializedBytes == 0, allocation.reservedBytes == r.maximumBytes, allocation.physicalIdentity == nil,
              lease.allocationID == r.assetID, lease.processEpoch == r.writerEpoch, lease.purposeRaw == "p1AcquireV1",
              lease.stateRaw == (closed ? "closedPendingCleanupV1" : (held ? "unknown" : "open")),
              work.assetID == r.assetID, work.packageID == r.packageID, work.ownerID == r.ownerID,
              work.processEpoch == r.writerEpoch, work.purposeRaw == "acquire", work.partialFileToken == r.partialToken,
              work.finalFileToken == r.finalToken, work.reservedByteCount == r.maximumBytes,
              work.allocatedByteCount == 0, work.sourceIdentity == nil,
              work.writerStateRaw == lease.stateRaw else { throw SharedMediaStorageFailure.conflict }
        return .init(request: r, receiptPhase: receipt.phaseRaw, receiptRevision: receipt.revision,
            inventoryRevision: inventory.revision, packageRevision: package.revision, membershipRevision: member.revision,
            membershipBytes: member.membersData, envelope: package.supportingContextData,
            allocatedBytes: package.allocatedByteCount, phase: package.phaseRaw, closure: closure)
    }
    /// Only stable surviving work is supported. Unsupported active preparation
    /// blocks before disposal; completed derivative pairs keep their own rows.
    func remainingPhase(_ c: ModelContext, request r: SharedMediaAcquisitionIntent) throws -> String {
        let envelope = try SharedMediaNativeDraftEnvelope.decode(package.supportingContextData)
        guard envelope.attempt == nil else { throw SharedMediaStorageFailure.closed }
        if case .preparation(let value) = envelope, value.frozen != nil { throw SharedMediaStorageFailure.closed }
        for blob in envelope.intents {
            let intent = try SharedMediaNativeDerivativeIntent.decode(blob.bytes)
            guard intent.preparation.original.reference.assetID != r.assetID,
                  try SharedMediaNativePairFileGraph.state(context: c, inventory: inventory, package: package,
                    member: member, pairID: intent.pairID).phase == "ready" else { throw SharedMediaStorageFailure.closed }
        }
        var attention = false, pending = false
        for id in try SharedMediaMembership.decode(member.membersData).ids(.work) where id != r.operationID {
            let job = try Self.one(c, FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == id }))
            guard try SharedMediaNativePairFileGraph.nativeWork(assetID: job.assetID, context: c) == nil else { throw SharedMediaStorageFailure.closed }
            let row = try Self.one(c, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id }))
            switch try SharedMediaAcquisitionReceipt.read(row) {
            case .held: attention = true
            case .reserved: attention = attention || job.writerStateRaw == "closedPendingCleanupV1"
            default: throw SharedMediaStorageFailure.conflict
            }
            pending = true
        }
        return attention ? "needsAttention" : (pending ? "acquiring" : "draftOwned")
    }
    static func membership(_ before: SharedMediaNativePendingState) throws -> Data {
        let old = try SharedMediaMembership.decode(before.membershipBytes)
        let removed: [SharedMediaMembership.Kind: UUID] = [.work: before.request.operationID, .lease: before.request.operationID, .allocation: before.request.assetID]
        for (kind, id) in removed { guard old.ids(kind).contains(id) else { throw SharedMediaStorageFailure.conflict } }
        return try SharedMediaMembership(groups: old.groups.compactMap { group in
            let ids = group.ids.filter { $0 != removed[group.kind] }
            return ids.isEmpty ? nil : .init(kind: group.kind, ids: ids)
        }).encoded()
    }
    static func noAdoption(_ c: ModelContext, request r: SharedMediaAcquisitionIntent) throws {
        let asset = r.assetID, reference = r.referenceID
        guard try c.fetchCount(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == asset })) == 0,
              try c.fetchCount(FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == asset })) == 0,
              try c.fetchCount(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.assetID == asset || $0.id == reference })) == 0,
              try c.fetchCount(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.allocationID == asset || $0.id == reference })) == 0,
              try SharedMediaNativePairFileGraph.nativeWork(assetID: asset, context: c) == nil else { throw SharedMediaStorageFailure.conflict }
    }
    static func one<T: PersistentModel>(_ c: ModelContext, _ query: FetchDescriptor<T>) throws -> T {
        try SharedMediaNativePairPlanGraph.one(c, query)
    }
}

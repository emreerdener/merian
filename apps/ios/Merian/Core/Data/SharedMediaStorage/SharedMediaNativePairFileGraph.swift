import Foundation
import SwiftData

/// Native output rows are covered only by their exact immutable intent joins.
/// Acquisition receipts remain a separate, mutually exclusive authority.
@MainActor
enum SharedMediaNativePairFileGraph {
    static func state(context: ModelContext, inventory: SharedMediaInventoryRecord,
                      package: PhotoPreparationRecord, member: SharedMediaPendingMembershipRecord, pairID: UUID? = nil) throws -> SharedMediaNativePairFileState {
        let plan = try SharedMediaNativePairPlanGraph.state(context: context, inventory: inventory, package: package, member: member, pairID: pairID)
        let intent = try SharedMediaNativeDerivativeIntent.decode(plan.intent.bytes), selectedID = intent.pairID
        let pair = try one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == selectedID }))
        let values = try [intent.ai.id, intent.display.id].map { id in
            let row = try one(context, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == id }))
            let leaseID = row.leaseID
            var query = FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == leaseID }); query.fetchLimit = 2
            let leases = try context.fetch(query)
            guard leases.count <= 1 else { throw SharedMediaStorageFailure.conflict }
            return SharedMediaNativePairFileState.Work(id: id, writerEpoch: row.writerEpoch, phase: row.phaseRaw,
                writerState: row.writerStateRaw, device: row.partialDevice, inode: row.partialInode,
                finalIdentity: row.finalIdentity, retirementID: row.retirementID,
                retirementPartial: row.retirementPartialIdentity, retirementFinal: row.retirementFinalIdentity,
                retirementParent: row.retirementParentIdentity, retirementNamespace: row.retirementNamespaceIdentity,
                closure: leases.first?.terminalProof)
        }
        return .init(plan: plan, phase: pair.phaseRaw, publishedRevision: pair.publishedRevision,
            allocatedBytes: package.allocatedByteCount, work: values)
    }

    /// Read-only reverse partition. No row is accepted merely because it carries
    /// a native purpose tag. The enclosing audit also validates every joined pair.
    static func nativeWork(assetID: UUID, context: ModelContext) throws -> SharedMediaDerivativeWorkRecord? {
        var query = FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.assetID == assetID }); query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count <= 1 else { throw SharedMediaStorageFailure.conflict }
        guard let work = rows.first else { return nil }
        let pairID = work.pairID
        let pair = try one(context, FetchDescriptor<SharedMediaDerivativePairRecord>(predicate: #Predicate { $0.id == pairID }))
        guard pair.contractVersion == SharedMediaNativePairPlanGraph.contract,
              work.id == pair.aiWorkID || work.id == pair.displayWorkID,
              try context.fetchCount(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID })) == 0 else {
            throw SharedMediaStorageFailure.conflict
        }
        return work
    }

    static func validate(_ work: SharedMediaDerivativeWorkRecord, input: SharedMediaDerivativeInput,
                         pair: SharedMediaDerivativePairRecord, package: PhotoPreparationRecord,
                         inventory: SharedMediaInventoryRecord, context: ModelContext) throws {
        let assetID = input.assetID, referenceID = input.referenceID, leaseID = input.leaseID
        let allocation = try one(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID }))
        let retiring = pair.phaseRaw == "retiring", completed = work.finalIdentity != nil
        let token = pair.ownerID.uuidString.lowercased() + "/" + pair.packageID.uuidString.lowercased() + "/" + assetID.uuidString.lowercased()
        guard ["writing", "ready", "retiring"].contains(pair.phaseRaw),
              (work.partialDevice == nil) == (work.partialInode == nil),
              allocation.inventoryID == inventory.id, allocation.accountID == pair.ownerID,
              allocation.packageID == pair.packageID, allocation.namespaceRaw == SharedMediaPhotoLedger.namespace,
              allocation.fileToken == token, allocation.poolRaw == "durable",
              allocation.materializedBytes == (completed ? input.byteCount : 0),
              allocation.reservedBytes == (completed ? 0 : input.byteCount), allocation.physicalIdentity == work.finalIdentity,
              allocation.stateRaw == (retiring ? "nativePairRetiringV2" : completed ? "nativePairMaterializedV2" : "nativePairReservedV2") else {
            throw SharedMediaStorageFailure.conflict
        }
        if retiring {
            guard work.phaseRaw == "retiring", work.writerStateRaw == "closed", work.retirementID != nil,
                  work.retirementPartialIdentity != nil, work.retirementFinalIdentity != nil,
                  work.retirementParentIdentity != nil, work.retirementNamespaceIdentity != nil else { throw SharedMediaStorageFailure.conflict }
        } else {
            guard work.retirementID == nil, work.retirementPartialIdentity == nil, work.retirementFinalIdentity == nil,
                  work.retirementParentIdentity == nil, work.retirementNamespaceIdentity == nil,
                  ["reserved", "writing", "completed"].contains(work.phaseRaw),
                  (work.phaseRaw == "reserved") == (work.partialDevice == nil),
                  (work.phaseRaw == "completed") == completed,
                  work.writerStateRaw == (completed ? "closed" : "open"),
                  pair.phaseRaw != "ready" || completed else { throw SharedMediaStorageFailure.conflict }
        }
        var leases = FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.assetID == assetID }); leases.fetchLimit = 2
        var shared = FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.allocationID == assetID }); shared.fetchLimit = 2
        let p1 = try context.fetch(leases), sl = try context.fetch(shared)
        if pair.phaseRaw == "ready" {
            guard p1.isEmpty, sl.isEmpty else { throw SharedMediaStorageFailure.conflict }
        } else {
            guard p1.count == 1, sl.count == 1, let lease = p1.first, let common = sl.first,
                  lease.id == leaseID, common.id == leaseID, lease.packageID == package.id,
                  lease.ownerID == package.ownerID, lease.processEpoch == work.writerEpoch,
                  lease.purposeRaw == SharedMediaNativePairPlanGraph.contract, lease.sourceIdentity == nil,
                  lease.partialFileToken == token + ".partial", lease.finalFileToken == token,
                  lease.reservedByteCount == (completed ? 0 : input.byteCount), lease.allocatedByteCount == (completed ? input.byteCount : 0),
                  lease.writerStateRaw == (retiring ? "closedNativePairRetirementV2" : completed ? "closedPairWaiting" : "open"),
                  common.processEpoch == work.writerEpoch, common.purposeRaw == SharedMediaNativePairPlanGraph.contract,
                  common.stateRaw == (completed || retiring ? "closed" : "open") else { throw SharedMediaStorageFailure.conflict }
            if retiring {
                guard let raw = lease.terminalProof else { throw SharedMediaStorageFailure.conflict }
                let aiID = pair.aiWorkID
                let ai = try one(context, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == aiID }))
                let aiLeaseID = ai.leaseID
                let canonical = try one(context, FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == aiLeaseID }))
                guard let canonicalRaw = canonical.terminalProof else { throw SharedMediaStorageFailure.conflict }
                let closure = try SharedMediaNativePairClosure.decode(canonicalRaw)
                guard raw == (work.id == aiID ? canonicalRaw : try closure.siblingMarker()) else { throw SharedMediaStorageFailure.conflict }
                try closure.require(work: work, pair: pair, package: package, inventory: inventory, context: context)
            } else { guard lease.terminalProof == nil else { throw SharedMediaStorageFailure.conflict } }
        }
        if completed {
            let asset = try one(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID }))
            let ref = try one(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.assetID == assetID }))
            let edge = try one(context, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.allocationID == assetID }))
            let counter = try one(context, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID }))
            guard asset.ownerID == pair.ownerID, asset.generation == input.assetGeneration, asset.fileToken == token,
                  asset.byteCount == input.byteCount, asset.sha256 == input.sha256, asset.contentType == input.contentType,
                  asset.acquisitionKindRaw == "nativeDerivativeV2", asset.cleanupStateRaw == (retiring ? "retiring" : "ready"),
                  ref.id == referenceID, ref.packageID == pair.packageID, ref.ownerID == pair.ownerID,
                  ref.roleRaw == input.role, ref.ordinal == pair.ordinal, ref.isLive == !retiring, ref.revision == (retiring ? 1 : 0),
                  edge.id == referenceID, edge.accountID == pair.ownerID, edge.ownerID == referenceID.uuidString.lowercased(),
                  edge.roleRaw == SharedMediaPhotoLedger.namespace, edge.stateRaw == (retiring ? "retired" : "live"), edge.revision == ref.revision,
                  counter.assetGeneration == input.assetGeneration, counter.inventoryID == inventory.id,
                  counter.inventoryGeneration == inventory.generation, counter.ownerID == pair.ownerID,
                  counter.liveCount == (retiring ? 0 : 1), counter.revision == (retiring ? 1 : 0), counter.retirementID == work.retirementID else {
                throw SharedMediaStorageFailure.conflict
            }
        } else {
            guard try context.fetchCount(FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID })) == 0,
                  try context.fetchCount(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == referenceID || $0.assetID == assetID })) == 0,
                  try context.fetchCount(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == referenceID || $0.allocationID == assetID })) == 0,
                  try context.fetchCount(FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID })) == 0 else { throw SharedMediaStorageFailure.conflict }
        }
    }

    private static func one<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>) throws -> T {
        try SharedMediaNativePairPlanGraph.one(context, query)
    }
}

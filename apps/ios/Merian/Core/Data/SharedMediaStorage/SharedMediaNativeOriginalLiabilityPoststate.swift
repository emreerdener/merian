import Foundation
import SwiftData

/// A clean persisted baseline plus one sealed native mutation. No arbitrary
/// dirty context can mint this measurement, and no capacity or I/O is granted.
@MainActor
enum SharedMediaNativeOriginalLiabilityPoststate {
    typealias Reader = SharedMediaNativeOriginalLiability
    @MainActor
    enum Proof {
        case metadata(SharedMediaNativeAppMetadataPoststate)
        case acquisition(SharedMediaNativeAppAcquisitionPoststate)
        case preparation(SharedMediaNativeAppPreparationPoststate)
        case pairPlan(SharedMediaNativeAppPairPlanPoststate)
        case pairClosure(SharedMediaNativeAppPairPlanClosurePoststate)
        case pairFile(SharedMediaNativeAppPairPoststate)
        case pairRetirement(SharedMediaNativeAppPairRetirementPoststate)
        case intent(SharedMediaNativeAppIntentPoststate)
        case staging(SharedMediaNativeAppStagingPoststate)
        case pendingCleanup(SharedMediaNativeAppPendingPoststate)
        case original(SharedMediaNativeAppOriginalPoststate)
        case originalRelease(SharedMediaNativeAppOriginalReleasePoststate)

        fileprivate var predecessorRevision: Int64 {
            switch self {
            case .metadata(let proof): return proof.predecessorRevision
            case .acquisition(let proof): return proof.predecessorRevision
            case .preparation(let proof): return proof.predecessorRevision
            case .pairPlan(let proof): return proof.predecessorRevision
            case .pairClosure(let proof): return proof.predecessorRevision
            case .pairFile(let proof): return proof.predecessorRevision
            case .pairRetirement(let proof): return proof.predecessorRevision
            case .intent(let proof): return proof.predecessorRevision
            case .staging(let proof): return proof.predecessorRevision
            case .pendingCleanup(let proof): return proof.predecessorRevision
            case .original(let proof): return proof.predecessorRevision
            case .originalRelease(let proof): return proof.predecessorRevision
            }
        }

        fileprivate func graph(_ context: ModelContext, _ inventory: SharedMediaInventoryRecord) throws -> SharedMediaPendingGraph {
            switch self {
            case .metadata(let proof): return try SharedMediaPendingGraph.deriveMetadataPoststate(in: context, inventory: inventory, proof: proof)
            case .acquisition(let proof): return try SharedMediaPendingGraph.deriveAcquisitionPoststate(in: context, inventory: inventory, proof: proof)
            case .preparation(let proof): return try SharedMediaPendingGraph.derivePreparationPoststate(in: context, inventory: inventory, proof: proof)
            case .pairPlan(let proof): return try SharedMediaPendingGraph.derivePairPlanPoststate(in: context, inventory: inventory, proof: proof)
            case .pairClosure(let proof): return try SharedMediaPendingGraph.derivePairClosurePoststate(in: context, inventory: inventory, proof: proof)
            case .pairFile(let proof): return try SharedMediaPendingGraph.derivePairFilePoststate(in: context, inventory: inventory, proof: proof)
            case .pairRetirement(let proof): return try SharedMediaPendingGraph.derivePairRetirementPoststate(in: context, inventory: inventory, proof: proof)
            case .intent(let proof): return try SharedMediaPendingGraph.deriveIntentPoststate(in: context, inventory: inventory, proof: proof)
            case .staging(let proof): return try SharedMediaPendingGraph.deriveStagingPoststate(in: context, inventory: inventory, proof: proof)
            case .pendingCleanup(let proof): return try SharedMediaPendingGraph.derivePendingCleanupPoststate(in: context, inventory: inventory, proof: proof)
            case .original(let proof): return try SharedMediaPendingGraph.deriveOriginalPoststate(in: context, inventory: inventory, proof: proof)
            case .originalRelease(let proof): return try SharedMediaPendingGraph.deriveOriginalReleasePoststate(in: context, inventory: inventory, proof: proof)
            }
        }
    }

    static func read(context: ModelContext, inventory: SharedMediaInventoryRecord, proof: Proof) throws -> Reader.Snapshot {
        let graph = try proof.graph(context, inventory)
        let pristine = ModelContext(context.container); pristine.autosaveEnabled = false
        let before = try Reader.read(context: pristine, inventoryID: inventory.id)
        guard before.generation == inventory.generation, before.revision == proof.predecessorRevision,
              inventory.revision == (try SharedMediaStoragePolicy.add(before.revision, 1)),
              before.retainedTargets.isEmpty else { throw SharedMediaStorageFailure.stale }
        var expected = before.entries
        var completed: Reader.Entry?, changedOriginal: UUID?, released: UUID?
        switch proof {
        case .acquisition(let value):
            completed = try value.completedIdentity(context: context, inventory: inventory)
            if let completed {
                guard expected.updateValue(completed, forKey: completed.assetID) == nil else { throw SharedMediaStorageFailure.conflict }
            }
        case .original(let value):
            let request = value.request, id = request.source.assetID
            guard let prior = expected[id], prior.acquisitionID == request.original.leaseID,
                  prior.currentBytes == Int64(request.original.physicalIdentity.utf8.count), !prior.retiring else {
                throw SharedMediaStorageFailure.conflict
            }
            if case .remove(let removal) = request.action, request.original.liveCount == 1 {
                let savedReceipt = try receipt(pristine, id)
                guard case .completed(let acquisition, let result) = try SharedMediaAcquisitionReceipt.read(savedReceipt),
                      acquisition.operationID == prior.acquisitionID else { throw SharedMediaStorageFailure.conflict }
                let retirement = try SharedMediaNativeRetirementIdentity(retirementID: removal.retirementID,
                    assetID: id, assetGeneration: request.source.assetGeneration, inventoryID: inventory.id,
                    inventoryGeneration: inventory.generation, ownerID: request.profile.ownerID, proof: result.descriptor)
                let bytes = Int64(try retirement.encoded().utf8.count)
                expected[id] = .init(assetID: id, acquisitionID: prior.acquisitionID, physicalOriginID: prior.physicalOriginID,
                    currentBytes: bytes, reservedBytes: 512 - bytes, retiring: true)
                changedOriginal = id
            }
        case .originalRelease(let value):
            released = value.assetID
            guard expected.removeValue(forKey: value.assetID)?.retiring == true else { throw SharedMediaStorageFailure.conflict }
        case .metadata, .preparation, .pairPlan, .pairClosure, .pairFile,
             .pairRetirement, .intent, .staging, .pendingCleanup:
            break // These exact typed write sets cannot change an original identity.
        }
        var observed = Set<UUID>()
        for allocation in graph.allocations {
            let id = allocation.id
            if try SharedMediaNativePairFileGraph.nativeWork(assetID: id, context: context) != nil { continue }
            let row = try receipt(context, id)
            switch try SharedMediaAcquisitionReceipt.read(row) {
            case .reserved, .held:
                guard expected[id] == nil else { throw SharedMediaStorageFailure.conflict }
                continue
            case .released: throw SharedMediaStorageFailure.conflict
            case .completed(let request, _):
                guard let entry = expected[id], observed.insert(id).inserted,
                      entry.assetID == id, entry.acquisitionID == request.operationID,
                      entry.physicalOriginID == request.packageID,
                      allocation.packageID == entry.physicalOriginID,
                      allocation.inventoryID == inventory.id, allocation.accountID == request.ownerID,
                      allocation.physicalIdentity.map({ Int64($0.utf8.count) }) == entry.currentBytes,
                      entry.currentBytes > 0, entry.currentBytes <= 512,
                      entry.reservedBytes == 512 - entry.currentBytes else { throw SharedMediaStorageFailure.conflict }
                if completed?.assetID != id {
                    let old = try one(pristine, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == id }))
                    try unchanged(allocation, old, replacingIdentity: changedOriginal == id)
                    let oldReceipt = try receipt(pristine, id)
                    guard row.id == oldReceipt.id, row.inventoryID == oldReceipt.inventoryID,
                          row.inventoryGeneration == oldReceipt.inventoryGeneration, row.ownerID == oldReceipt.ownerID,
                          row.requestData == oldReceipt.requestData, row.resultData == oldReceipt.resultData,
                          try SharedMediaAcquisitionReceipt.read(row) == SharedMediaAcquisitionReceipt.read(oldReceipt) else {
                        throw SharedMediaStorageFailure.conflict
                    }
                }
            }
        }
        guard observed == Set(expected.keys), released.map({ !observed.contains($0) }) ?? true else {
            throw SharedMediaStorageFailure.conflict
        }
        let result = Reader.Snapshot(inventoryID: before.inventoryID, generation: before.generation,
            revision: inventory.revision, entries: expected, retainedTargets: [])
        _ = try PhotoPreparationPolicy.add([result.currentBytes, result.reservedBytes])
        // Revalidate the seal after measurement. The persisted baseline was
        // never audited through a dirty context or promoted to mutation authority.
        _ = try proof.graph(context, inventory)
        return result
    }

    private static func unchanged(_ row: SharedMediaAllocationRecord, _ old: SharedMediaAllocationRecord,
                                  replacingIdentity: Bool) throws {
        guard row.id == old.id, row.inventoryID == old.inventoryID, row.accountID == old.accountID,
              row.packageID == old.packageID, row.namespaceRaw == old.namespaceRaw, row.fileToken == old.fileToken,
              row.poolRaw == old.poolRaw, row.materializedBytes == old.materializedBytes, row.reservedBytes == old.reservedBytes,
              replacingIdentity || (row.stateRaw == old.stateRaw && row.physicalIdentity == old.physicalIdentity) else {
            throw SharedMediaStorageFailure.conflict
        }
    }
    private static func receipt(_ context: ModelContext, _ id: UUID) throws -> SharedMediaAcquisitionReceiptRecord {
        try one(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == id }))
    }
    private static func one<T: PersistentModel>(_ context: ModelContext, _ query: FetchDescriptor<T>) throws -> T {
        try SharedMediaNativePairPlanGraph.one(context, query)
    }
}

import Foundation
import SwiftData

/// Read-only audit of one persisted original's complete reference set. The
/// caller must hold the native store fence throughout this synchronous call.
/// Pages bound materialization, not total database work or runtime memory.
/// This is not a whole-store/namespace audit, phase validator or capability.
@MainActor
enum SharedMediaNativeOriginalAccounting {
    struct Snapshot: Equatable, Sendable {
        let inventoryID: UUID
        let inventoryGeneration: UUID
        let inventoryRevision: Int64
        let assetID: UUID
        let assetGeneration: UUID
        let ownerID: UUID
        let liveCount: Int64
        let countRevision: Int64
        let retirement: SharedMediaNativeRetirementIdentity?
        let leaseID: UUID
        let leaseEpoch: UUID
        let fileToken: String
        let physicalIdentity: String
        let byteCount: Int64
        let sha256: String
        let contentType: String
    }

    /// No partial success escapes: both directions must reach exhaustion under
    /// the same fence. A saved counter is never created, repaired or trusted alone.
    static func audit(assetID: UUID, inventoryID: UUID, context: ModelContext) throws -> Snapshot {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let inventory = try one(context, FetchDescriptor<SharedMediaInventoryRecord>(predicate: #Predicate { $0.id == inventoryID }))
        let generation = inventory.generation, revision = inventory.revision
        let asset = try one(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == assetID }))
        let allocation = try one(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID }))
        let counter = try one(context, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == assetID }))
        let lease = try one(context, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.allocationID == assetID }))
        guard revision >= 0, allocation.inventoryID == inventoryID,
              counter.inventoryID == inventoryID, counter.inventoryGeneration == generation,
              counter.assetGeneration == asset.generation, counter.ownerID == asset.ownerID,
              counter.revision >= 0, counter.liveCount >= 0,
              allocation.accountID == asset.ownerID,
              allocation.namespaceRaw == SharedMediaPhotoLedger.namespace, allocation.poolRaw == "durable",
              allocation.materializedBytes == asset.byteCount, allocation.reservedBytes == 0,
              asset.byteCount > 0, asset.byteCount <= PhotoPreparationPolicy.original,
              asset.sha256.utf8.count == 64,
              asset.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              !asset.contentType.isEmpty, asset.contentType.utf8.count <= 128,
              allocation.fileToken == asset.fileToken, let origin = allocation.packageID,
              asset.fileToken == asset.ownerID.uuidString.lowercased() + "/" + origin.uuidString.lowercased() + "/" + assetID.uuidString.lowercased(),
              let identity = allocation.physicalIdentity, !identity.isEmpty, identity.utf8.count <= 512,
              lease.purposeRaw == "p1AcquireV1", lease.stateRaw == "closed" else {
            throw SharedMediaStorageFailure.conflict
        }
        // Physical origin need not remain a logical package owner. Do not join
        // allocation.packageID to a possibly deleted package or infer ownership.
        let retirement: SharedMediaNativeRetirementIdentity?
        if counter.liveCount > 0 {
            guard asset.cleanupStateRaw == "ready", allocation.stateRaw == "p1Materialized",
                  counter.retirementID == nil else { throw SharedMediaStorageFailure.conflict }
            retirement = nil
        } else {
            guard counter.revision > 0, asset.cleanupStateRaw == "retiring",
                  allocation.stateRaw == SharedMediaNativeRetirementIdentity.allocationState else {
                throw SharedMediaStorageFailure.conflict
            }
            let saved = try SharedMediaNativeRetirementIdentity.decode(identity)
            guard saved.retirementID == counter.retirementID, saved.assetID == assetID,
                  saved.assetGeneration == asset.generation, saved.ownerID == asset.ownerID,
                  saved.inventoryID == inventoryID, saved.inventoryGeneration == generation,
                  Int64(saved.proof.file.split(separator: ":")[2]) == asset.byteCount else {
                throw SharedMediaStorageFailure.conflict
            }
            retirement = saved
        }
        let liveP1 = try context.fetchCount(FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.assetID == assetID && $0.isLive }))
        let liveShared = try context.fetchCount(FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.allocationID == assetID && $0.stateRaw == "live" }))
        guard Int64(liveP1) == counter.liveCount, liveP1 == liveShared else { throw SharedMediaStorageFailure.conflict }
        var references = FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.assetID == assetID }, sortBy: [SortDescriptor(\.id)])
        var edges = FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.allocationID == assetID }, sortBy: [SortDescriptor(\.id)])
        references.fetchLimit = SharedMediaStoragePolicy.pageSize
        edges.fetchLimit = SharedMediaStoragePolicy.pageSize
        let totalP1 = try visit(context, descriptor: references) { ref in
            let id = ref.id
            let edge = try one(context, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == id }))
            try validate(ref, edge: edge, asset: asset, retiring: retirement != nil, context: context)
        }
        let totalShared = try visit(context, descriptor: edges) { edge in
            let id = edge.id
            let ref = try one(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == id }))
            try validate(ref, edge: edge, asset: asset, retiring: retirement != nil, context: context)
        }
        // Non-last retirement deletes the pair. Only the final retired pair
        // survives until physical absence is acknowledged by the native owner.
        guard totalP1 == totalShared, totalP1 == (retirement == nil ? counter.liveCount : 1),
              inventory.generation == generation, inventory.revision == revision, !context.hasChanges else {
            throw SharedMediaStorageFailure.conflict
        }
        return .init(inventoryID: inventoryID, inventoryGeneration: generation, inventoryRevision: revision,
            assetID: assetID, assetGeneration: asset.generation, ownerID: asset.ownerID,
            liveCount: counter.liveCount, countRevision: counter.revision, retirement: retirement,
            leaseID: lease.id, leaseEpoch: lease.processEpoch, fileToken: asset.fileToken,
            physicalIdentity: identity, byteCount: asset.byteCount, sha256: asset.sha256, contentType: asset.contentType)
    }

    private static func validate(_ ref: PhotoPreparationReference, edge: SharedMediaReferenceRecord,
                                 asset: PhotoPreparationAsset, retiring: Bool, context: ModelContext) throws {
        let packageID = ref.packageID
        let package = try one(context, FetchDescriptor<PhotoPreparationRecord>(predicate: #Predicate { $0.id == packageID }))
        guard ref.assetID == asset.id, ref.ownerID == asset.ownerID, ref.roleRaw == "original",
              (0..<2).contains(ref.ordinal), ref.revision >= 0, ref.isLive == !retiring,
              !retiring || ref.revision > 0,
              package.ownerID == asset.ownerID, package.draftID == package.id,
              package.contractVersion == PhotoPreparationPolicy.contract, package.revision >= 0,
              ["pending", "retained"].contains(package.accountingTierRaw),
              edge.id == ref.id, edge.allocationID == asset.id, edge.accountID == asset.ownerID,
              edge.ownerID == ref.id.uuidString.lowercased(), edge.roleRaw == SharedMediaPhotoLedger.namespace,
              edge.stateRaw == (ref.isLive ? "live" : "retired"), edge.revision == ref.revision else {
            throw SharedMediaStorageFailure.conflict
        }
    }

    private static func one<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws -> T {
        var query = descriptor; query.fetchLimit = 2
        let rows = try context.fetch(query)
        guard rows.count == 1, let row = rows.first else { throw SharedMediaStorageFailure.conflict }
        return row
    }

    private static func visit<T: PersistentModel>(_ context: ModelContext, descriptor: FetchDescriptor<T>,
                                                  body: (T) throws -> Void) throws -> Int64 {
        var query = descriptor, total: Int64 = 0
        var offset = 0
        while true {
            query.fetchOffset = offset
            let page = try context.fetch(query)
            for row in page { try body(row) }
            total = try SharedMediaStoragePolicy.add(total, Int64(page.count))
            if page.count < SharedMediaStoragePolicy.pageSize { return total }
            let (next, overflow) = offset.addingReportingOverflow(page.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }
            offset = next
        }
    }
}

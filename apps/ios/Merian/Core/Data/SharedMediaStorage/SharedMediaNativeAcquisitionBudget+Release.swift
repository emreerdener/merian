import Foundation
import SwiftData

/// Releasing packages bypass ordinary receiving measurement. Keep their
/// survivor and companion contributions together under the same budget owner.
extension SharedMediaNativeAcquisitionBudget {
    /// Clean held-release values only. Identity is deliberately absent here:
    /// the single asset-owned pass below supplies current bytes and headroom.
    static func releaseContribution(_ snapshot: SharedMediaNativeReleaseMetadataSnapshot.Snapshot,
                                            graph: SharedMediaPendingGraph, context: ModelContext,
                                            inventory: SharedMediaInventoryRecord,
                                            totals: inout SharedMediaStoragePolicy.Totals,
                                            chargedPhysical: inout Set<UUID>, chargedReceipts: inout Set<UUID>) throws -> Int64 {
        func one<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> T {
            var query = descriptor; query.includePendingChanges = true
            return try SharedMediaNativePairPlanGraph.one(context, query)
        }
        guard !context.hasChanges, snapshot.inventoryRevision == inventory.revision else {
            throw SharedMediaStorageFailure.stale
        }
        let projection = try SharedMediaNativeReleaseSurvivorProjection.maximum(snapshot)
        try projection.requireMetadataCapacity()
        let current = projection.currentIdentityExcludedBytes
        let maximum = projection.maximumIdentityExcludedBytes
        try totals.includePhotoPhysical(materialized: current, reserved: maximum - current)
        try totals.includePhotoPhysical(materialized: projection.recoveryPresentation.materializedBytes,
            reserved: projection.recoveryPresentation.reservedBytes)
        let id = snapshot.release.state.package.id
        for original in snapshot.ownedOriginals {
            let assetID = original.assetID
            let allocation = try one(FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == assetID }))
            guard allocation.inventoryID == inventory.id, allocation.packageID == id,
                  allocation.accountID == snapshot.release.progress.plan.profile.ownerID,
                  allocation.reservedBytes == 0,
                  allocation.physicalIdentity.map({ Int64($0.utf8.count) }) == original.identityBytes,
                  chargedReceipts.insert(assetID).inserted else { throw SharedMediaStorageFailure.conflict }
            let receipt = try one(FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.assetID == assetID }))
            guard case .completed(let request, let result) = try SharedMediaAcquisitionReceipt.read(receipt),
                  request.assetID == assetID, request.packageID == id,
                  request.inventoryID == inventory.id, request.inventoryGeneration == inventory.generation,
                  request.ownerID == allocation.accountID, allocation.materializedBytes == result.byteCount,
                  try SharedMediaAcquisitionReceipt.metadataCharge(request: request, result: result) == original.receiptBytes else {
                throw SharedMediaStorageFailure.conflict
            }
            // The complete metadata/live audit binds receipt, acquisition and
            // physical origin. The same allocation may also be in a recipient's
            // pending graph; only an origin absent there adds physical bytes.
            if chargedPhysical.insert(assetID).inserted {
                try totals.includePhotoPhysical(materialized: allocation.materializedBytes, reserved: 0)
            }
        }
        let metadata = try PhotoPreparationPolicy.add([projection.maximumLivePackageMetadataBytes, projection.recoveryPresentation.chargedBytes])
        var logical = metadata
        for reference in graph.references where reference.packageID == id {
            guard let asset = graph.assets.first(where: { $0.id == reference.assetID }) else {
                throw SharedMediaStorageFailure.conflict
            }
            logical = try SharedMediaStoragePolicy.add(logical, asset.byteCount)
        }
        try totals.includePhotoPackage(id: id, bytes: logical)
        return metadata
    }

}

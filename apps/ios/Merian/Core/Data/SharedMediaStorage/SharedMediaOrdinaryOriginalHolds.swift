import Foundation
import SwiftData

/// Complete accepted liabilities for one materialized original. The caller
/// supplies the native store fence and a clean context. Historical acceptance
/// does not require the source draft/reference to survive, and grants no file
/// access, queue admission, release or retirement authority.
@MainActor
enum SharedMediaOrdinaryOriginalHolds {
    static func count(context: ModelContext, inventory: SharedMediaInventoryRecord,
                      asset: PhotoPreparationAsset, allocation: SharedMediaAllocationRecord,
                      counter: SharedMediaAssetReferenceCountRecord, lease: SharedMediaLeaseRecord,
                      checkpoint: () throws -> Void) throws -> Int64 {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        let assetID = asset.id
        var query = FetchDescriptor<SharedMediaOrdinaryTransferRecord>(predicate: #Predicate {
            $0.sourceAssetID == assetID
        }, sortBy: [SortDescriptor(\.cursorKey)])
        query.fetchLimit = SharedMediaStoragePolicy.pageSize
        var total: Int64 = 0
        var offset = 0
        while true {
            try Task.checkCancellation(); try checkpoint()
            query.fetchOffset = offset
            let page = try context.fetch(query)
            for row in page {
                try Task.checkCancellation(); try checkpoint()
                let generation = row.submissionGeneration
                var parentQuery = FetchDescriptor<SharedMediaOrdinarySubmissionRecord>(predicate: #Predicate {
                    $0.submissionGeneration == generation
                })
                parentQuery.fetchLimit = 2
                let parents = try context.fetch(parentQuery)
                guard parents.count == 1, let parent = parents.first else { throw SharedMediaStorageFailure.conflict }
                let receipt = try SharedMediaOrdinarySubmissionReceipt.read(parent, in: context)
                guard case .accepted = receipt.state,
                      let request = receipt.holds.requests.first(where: { $0.id == row.id }),
                      let acceptance = try receipt.holds.acceptances()[row.id] else { throw SharedMediaStorageFailure.conflict }
                let completed = request.completion
                guard request.profile.inventoryID == inventory.id,
                      request.profile.generation == inventory.generation,
                      request.profile.ownerID == asset.ownerID,
                      request.source.assetID == asset.id, request.source.assetGeneration == asset.generation,
                      request.acquisition.finalToken == asset.fileToken,
                      request.acquisition.packageID == allocation.packageID,
                      completed.descriptor.file == allocation.physicalIdentity,
                      completed.byteCount == asset.byteCount, completed.sha256 == asset.sha256,
                      completed.contentType == asset.contentType, completed.leaseID == lease.id,
                      request.acquisition.writerEpoch == lease.processEpoch,
                      acceptance.inventoryRevision <= inventory.revision,
                      acceptance.countRevision <= counter.revision,
                      acceptance.countRevision != counter.revision || acceptance.liveCount == counter.liveCount else {
                    throw SharedMediaStorageFailure.conflict
                }
                total = try SharedMediaStoragePolicy.add(total, 1)
            }
            if page.count < SharedMediaStoragePolicy.pageSize { break }
            let (next, overflow) = offset.addingReportingOverflow(page.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }
            offset = next
        }
        try checkpoint()
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        return total
    }
}

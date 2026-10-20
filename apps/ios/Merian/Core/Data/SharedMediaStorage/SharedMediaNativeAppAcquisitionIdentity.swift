import Foundation
import SwiftData

/// Exact collision checks for proposed IDs. The caller retains its operation
/// fence and both header revisions throughout every page suspension. These
/// read-only facts cannot authorize a reservation or change a saved request.
@MainActor
enum SharedMediaNativeAppAcquisitionIdentity {
    static func audit(_ request: SharedMediaAcquisitionIntent, container: ModelContainer,
                      check: () throws -> Void) async throws {
        try request.validate(); try check()
        let wanted = Set([request.operationID, request.assetID, request.referenceID])
        var offset = 0
        while true {
            try Task.checkCancellation(); try check()
            let count: Int = try {
                let context = ModelContext(container); context.autosaveEnabled = false
                var query = FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(sortBy: [SortDescriptor(\.id)])
                query.fetchOffset = offset; query.fetchLimit = SharedMediaStoragePolicy.pageSize
                let rows = try context.fetch(query)
                for row in rows {
                    let ids: Set<UUID>
                    switch try SharedMediaAcquisitionReceipt.read(row) {
                    case .reserved(let old), .held(let old), .completed(let old, _):
                        ids = [old.operationID, old.assetID, old.referenceID]
                    case .released(let old): ids = [old.operationID]
                    }
                    guard wanted.isDisjoint(with: ids) else { throw SharedMediaStorageFailure.conflict }
                }
                return rows.count
            }()
            try check()
            if count < SharedMediaStoragePolicy.pageSize { break }
            let (next, overflow) = offset.addingReportingOverflow(count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
            await Task.yield(); try check()
        }
        let context = ModelContext(container); context.autosaveEnabled = false
        try direct(request, context: context); try check()
    }

    /// Repeat indexed probes immediately before a fresh reservation. Receipt
    /// requestData reference aliases are covered by the pinned paged audit;
    /// any header drift invalidates that audit instead of rescanning in save.
    static func direct(_ request: SharedMediaAcquisitionIntent, context: ModelContext) throws {
        guard !context.hasChanges else { throw SharedMediaStorageFailure.conflict }
        for id in [request.operationID, request.assetID, request.referenceID] {
            try empty(context, FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(predicate: #Predicate { $0.id == id || $0.assetID == id }))
            try empty(context, FetchDescriptor<SharedMediaAllocationRecord>(predicate: #Predicate { $0.id == id }))
            try empty(context, FetchDescriptor<SharedMediaLeaseRecord>(predicate: #Predicate { $0.id == id || $0.allocationID == id }))
            try empty(context, FetchDescriptor<PhotoPreparationLease>(predicate: #Predicate { $0.id == id || $0.assetID == id }))
            try empty(context, FetchDescriptor<PhotoPreparationAsset>(predicate: #Predicate { $0.id == id }))
            try empty(context, FetchDescriptor<PhotoPreparationReference>(predicate: #Predicate { $0.id == id || $0.assetID == id }))
            try empty(context, FetchDescriptor<SharedMediaReferenceRecord>(predicate: #Predicate { $0.id == id || $0.allocationID == id }))
            try empty(context, FetchDescriptor<SharedMediaAssetReferenceCountRecord>(predicate: #Predicate { $0.id == id }))
            try empty(context, FetchDescriptor<SharedMediaDerivativeWorkRecord>(predicate: #Predicate { $0.id == id || $0.assetID == id || $0.referenceID == id || $0.leaseID == id }))
            try empty(context, FetchDescriptor<SharedMediaInboxSourceRecord>(predicate: #Predicate { $0.id == id || $0.workID == id }))
            try empty(context, FetchDescriptor<SharedMediaInboxHandoffRecord>(predicate: #Predicate { $0.id == id || $0.assetID == id || $0.sourceHoldID == id }))
        }
    }
    private static func empty<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) throws {
        var query = descriptor; query.fetchLimit = 1; query.includePendingChanges = true
        guard try context.fetch(query).isEmpty else { throw SharedMediaStorageFailure.conflict }
    }
}

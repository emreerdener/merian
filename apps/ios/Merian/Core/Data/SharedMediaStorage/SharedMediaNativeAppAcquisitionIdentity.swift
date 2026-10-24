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
        let wanted = Self.freshIDs(request)
        var offset = 0
        while true {
            try Task.checkCancellation(); try check()
            let count: Int = try {
                let context = ModelContext(container); context.autosaveEnabled = false
                var query = FetchDescriptor<SharedMediaAcquisitionReceiptRecord>(sortBy: [SortDescriptor(\.id)])
                query.fetchOffset = offset; query.fetchLimit = SharedMediaStoragePolicy.pageSize
                let rows = try context.fetch(query)
                for row in rows {
                    let receipt = try SharedMediaAcquisitionReceipt.read(row)
                    for id in wanted { try SharedMediaNativeReleaseStageIdentity.requireAbsent(id, receipt: receipt) }
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
        try SharedMediaNativeReleaseStageIdentity.requireFresh(freshIDs(request), inventoryID: request.inventoryID, context: context)
    }
    private static func freshIDs(_ request: SharedMediaAcquisitionIntent) -> [UUID] {
        let ids = [request.operationID, request.assetID, request.referenceID]
        if case .absent = request.packageExpectation { return ids + [request.packageID] }
        return ids
    }
}

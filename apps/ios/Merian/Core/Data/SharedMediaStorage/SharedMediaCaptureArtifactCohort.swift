import Foundation
import SwiftData

/// Bounded active membership with paginated terminal accounting. Old abort
/// tombstones are checked, never deleted or mistaken for current members.
@MainActor
enum SharedMediaCaptureArtifactCohort {
    static func activeRows(_ descriptor: FetchDescriptor<SharedMediaOrdinaryArtifactRecord>, context: ModelContext, includeAcceptedRelease: Bool = false,
                           retired: (SharedMediaCaptureArtifactLedger.Snapshot) throws -> Void) throws -> [SharedMediaOrdinaryArtifactRecord] {
        var query = descriptor, result: [SharedMediaOrdinaryArtifactRecord] = []
        query.sortBy = [SortDescriptor(\.cursorKey)]; query.fetchLimit = 64
        while true {
            try Task.checkCancellation()
            let rows = try context.fetch(query)
            for row in rows {
                let value = try SharedMediaCaptureArtifactLedger.auditReceipt(row)
                if let retirement = value.retirement {
                    guard retirement.releasedRevision != nil else { throw SharedMediaStorageFailure.closed }
                    if retirement.version == 2 { try SharedMediaCaptureAbortedPreparation.requireRetirement(value, context: context) }
                    try retired(value)
                } else {
                    guard includeAcceptedRelease || value.acceptedRelease == nil else { throw SharedMediaStorageFailure.closed }
                    guard result.count < 64 else { throw SharedMediaStorageFailure.capacity }
                    result.append(row)
                }
            }
            if rows.count < 64 { return result }
            let (next, overflow) = (query.fetchOffset ?? 0).addingReportingOverflow(rows.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }
            query.fetchOffset = next
        }
    }
}

import Foundation
import SwiftData

/// Local foreground admission only. No network, optimistic authority or hidden
/// queue wake. Callers retain the displayed ticket and its exact tap request.
@MainActor
enum ObservationAnalysisReviewAdmission {
    typealias Store = ObservationAnalysisReviewPersistence

    static func stage(_ request: ObservationAnalysisReviewRequest, ticket: ObservationAnalysisReviewTicket,
                      container: ModelContainer, isCurrent: () -> Bool,
                      save: (ModelContext) throws -> Void = { try $0.save() }) throws -> ObservationAnalysisReviewIntent {
        guard try ticket.request(request.decision, operationID: request.operationID) == request else {
            throw Store.IntegrityError.conflict
        }
        return try Store.stage(request, ownerID: ticket.ownerID, container: container, isCurrent: isCurrent, validateNew: { context in
            let scan = try ObservationHistorySyncService.enrolledScan(ticket.observationID.uuidString, context: context)
            try ObservationHistorySelectionIntent.requireIdle(scan.id, context: context)
            try ObservationHistoryStateSyncService.requireSettledReview(scan, context: context)
            guard try currentTicket(ticket, scan: scan, context: context) == ticket else { throw Store.IntegrityError.conflict }
            if case let .undo(rejectionID) = request.decision {
                guard try ObservationAnalysisReviewStatus.undoOperation(ticket, context: context) == rejectionID else {
                    throw Store.IntegrityError.conflict
                }
            }
        }, save: save)
    }

    static func currentTicket(_ ticket: ObservationAnalysisReviewTicket, scan: LocalScanRecord,
                              context: ModelContext) throws -> ObservationAnalysisReviewTicket {
        guard scan.analysisOwnerAccountID == ticket.ownerID.uuidString.lowercased(),
              scan.id.lowercased() == ticket.observationID.uuidString.lowercased() else { throw Store.IntegrityError.accountChanged }
        let entry = try ObservationHistoryListingService.entry(ticket.analysisID, scan: scan, context: context)
        let scope = ObservationHistoryListingService.Context(owner: ticket.ownerID,
            selected: try ObservationHistoryPage.uuid(scan.selectedAnalysisID), revision: try ObservationHistoryPage.integer(scan.observationStateRevision),
            pendingOperation: nil, undoOperation: nil)
        return try .init(entry: entry, context: scope, observationID: ticket.observationID)
    }
}

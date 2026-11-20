import Foundation
import SwiftData

/// Exact advisory provenance. The server repeats the receipt/authority check at mutation time.
struct ObservationRejectionUndoEligibility: Equatable {
    enum Source: Equatable { case local, recovered }
    enum Resolution { case available(ObservationRejectionUndoEligibility), unavailable(ObservationRejectionUndoReply.Reason) }
    let ticket: ObservationAnalysisReviewTicket
    let operationID: UUID
    let source: Source
    private init(ticket: ObservationAnalysisReviewTicket, operationID: UUID, source: Source) {
        self.ticket = ticket; self.operationID = operationID; self.source = source
    }
    static func lookup(_ ticket: ObservationAnalysisReviewTicket) -> ObservationRejectionUndoLookup {
        .init(observationID: ticket.observationID, analysisID: ticket.analysisID,
              observationRevision: ticket.observationRevision, reviewRevision: ticket.reviewRevision)
    }
    static func recovered(_ reply: ObservationRejectionUndoReply, ticket: ObservationAnalysisReviewTicket) throws -> Resolution {
        guard reply.request == lookup(ticket) else { throw ObservationHistoryError.resultConflict }
        switch reply.outcome {
        case let .unavailable(reason): return .unavailable(reason)
        case let .available(operation):
            guard ticket.rejectionOperationID == operation else { throw ObservationHistoryError.resultConflict }
            return .available(.init(ticket: ticket, operationID: operation, source: .recovered))
        }
    }
    static func local(_ ticket: ObservationAnalysisReviewTicket, context: ModelContext) throws -> Self? {
        guard let operation = try ObservationAnalysisReviewStatus.undoOperation(ticket, context: context) else { return nil }
        return .init(ticket: ticket, operationID: operation, source: .local)
    }
    func validate(ticket current: ObservationAnalysisReviewTicket, context: ModelContext) throws {
        guard current == ticket, current.rejectionOperationID == operationID else { throw ObservationHistoryError.resultConflict }
        if source == .local, try Self.local(current, context: context) != self { throw ObservationHistoryError.resultConflict }
    }
}

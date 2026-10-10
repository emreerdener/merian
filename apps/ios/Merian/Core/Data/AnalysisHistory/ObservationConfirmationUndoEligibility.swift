import Foundation
import SwiftData

/// Advisory provenance only. The server repeats receipt/authority validation at mutation time.
struct ObservationConfirmationUndoEligibility: Equatable {
    enum Source: Equatable { case local, recovered }
    enum Resolution { case available(ObservationConfirmationUndoEligibility), unavailable(ObservationConfirmationUndoReply.Reason) }
    let ticket: ObservationAnalysisReviewTicket
    let operationID: UUID
    let action: ObservationConfirmationAction
    let source: Source
    private init(ticket: ObservationAnalysisReviewTicket, operationID: UUID, action: ObservationConfirmationAction, source: Source) {
        self.ticket = ticket; self.operationID = operationID; self.action = action; self.source = source
    }
    static func recovered(_ reply: ObservationConfirmationUndoReply, ticket: ObservationAnalysisReviewTicket) throws -> Resolution {
        guard reply.request == lookup(ticket) else { throw ObservationHistoryError.resultConflict }
        switch reply.outcome {
        case let .unavailable(reason): return .unavailable(reason)
        case let .available(operation, action):
            guard ticket.confirmationOperationID == operation, ticket.confirmationAction == action else {
                throw ObservationHistoryError.resultConflict
            }
            return .available(.init(ticket: ticket, operationID: operation, action: action, source: .recovered))
        }
    }
    static func lookup(_ ticket: ObservationAnalysisReviewTicket) -> ObservationConfirmationUndoLookup {
        .init(observationID: ticket.observationID, analysisID: ticket.analysisID,
              observationRevision: ticket.observationRevision, reviewRevision: ticket.reviewRevision)
    }
    static func local(_ ticket: ObservationAnalysisReviewTicket, context: ModelContext) throws -> Self? {
        guard let operation = ticket.confirmationOperationID, let action = ticket.confirmationAction,
              let job = try context.fetchOfflineJob(id: ObservationAnalysisReviewPersistence.jobID(operation, observationID: ticket.observationID)) else { return nil }
        let saved = try ObservationAnalysisReviewPersistence.restore(job)
        guard saved.ownerID == ticket.ownerID, saved.request.analysisID == ticket.analysisID,
              saved.request.decision.action == action.rawValue, saved.isComplete, let receipt = saved.receipt,
              case let .applied(observation, review) = receipt.outcome,
              observation <= ticket.observationRevision, review == ticket.reviewRevision else { return nil }
        return .init(ticket: ticket, operationID: operation, action: action, source: .local)
    }
    func validate(ticket current: ObservationAnalysisReviewTicket, context: ModelContext) throws {
        guard current == ticket, current.confirmationOperationID == operationID, current.confirmationAction == action else {
            throw ObservationHistoryError.resultConflict
        }
        // Recovered eligibility deliberately has no dependency on a local original receipt.
        if source == .local, try Self.local(current, context: context) != self { throw ObservationHistoryError.resultConflict }
    }
}

import Foundation

/// Explicitly composed local admission/status. The queue alone owns delivery.
@MainActor
struct IdentificationHistoryReviewAccess {
    var stage: (ObservationAnalysisReviewRequest, ObservationAnalysisReviewTicket) throws -> Void
    var status: (ObservationAnalysisReviewTicket, UUID) throws -> ObservationAnalysisReviewStatus?
    var pending: () throws -> ObservationAnalysisReviewStatus?
    var undo: (ObservationAnalysisReviewTicket) throws -> UUID?
    var wake: () -> Void
    var generation: () -> UInt64
}

extension IdentificationHistorySession {
    func pendingReview() throws -> ObservationAnalysisReviewStatus? {
        try check()
        return try ObservationAnalysisReviewStatus.pending(ownerID: session.userID,
            observationID: ObservationHistoryPage.uuid(observation), container: container, isCurrent: isCurrent)
    }
    func reviewAccess(wake: @escaping () -> Void, generation: @escaping () -> UInt64) -> IdentificationHistoryReviewAccess {
        .init(stage: { [self] request, ticket in
            try check()
            guard ticket.ownerID == session.userID, ticket.observationID == (try ObservationHistoryPage.uuid(observation)) else {
                throw ObservationHistoryError.accountChanged
            }
            _ = try ObservationAnalysisReviewAdmission.stage(request, ticket: ticket, container: container, isCurrent: isCurrent)
        }, status: { [self] ticket, operation in
            try check()
            guard ticket.ownerID == session.userID, ticket.observationID == (try ObservationHistoryPage.uuid(observation)) else {
                throw ObservationHistoryError.accountChanged
            }
            return try ObservationAnalysisReviewStatus.read(operationID: operation, ownerID: session.userID,
                observationID: ObservationHistoryPage.uuid(observation), analysisID: ticket.analysisID, container: container, isCurrent: isCurrent)
        }, pending: { [self] in try pendingReview() }, undo: { [self] ticket in
            try check()
            guard ticket.ownerID == session.userID, ticket.observationID == (try ObservationHistoryPage.uuid(observation)) else {
                throw ObservationHistoryError.accountChanged
            }
            return try ObservationAnalysisReviewStatus.undoOperation(ticket, container: container, isCurrent: isCurrent)
        }, wake: wake, generation: generation)
    }
}

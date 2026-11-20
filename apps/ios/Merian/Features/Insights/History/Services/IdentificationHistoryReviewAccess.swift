import Foundation

/// Explicitly composed local admission/status. The queue alone owns delivery.
@MainActor
struct IdentificationHistoryReviewAccess {
    struct ConfirmationUndoConfiguration {
        let owner: ObservationConfirmationUndoOwner
        let fetch: (ObservationConfirmationUndoLookup, UUID, @escaping @MainActor @Sendable () throws -> Void) async throws -> ObservationConfirmationUndoReply
    }
    struct RejectionUndoConfiguration {
        let owner: ObservationRejectionUndoOwner
        let fetch: (ObservationRejectionUndoLookup, UUID, @escaping @MainActor @Sendable () throws -> Void) async throws -> ObservationRejectionUndoReply
    }
    var stage: (ObservationAnalysisReviewRequest, ObservationAnalysisReviewTicket) throws -> Void
    var status: (ObservationAnalysisReviewTicket, UUID) throws -> ObservationAnalysisReviewStatus?
    var pending: () throws -> ObservationAnalysisReviewStatus?
    var undo: (ObservationAnalysisReviewTicket) throws -> UUID?
    var wake: () -> Void
    var generation: () -> UInt64
    var prepareConfirmationUndo: ((ObservationAnalysisReviewTicket) async throws -> ObservationConfirmationUndoEligibility.Resolution)?
    var stageConfirmationUndo: ((ObservationAnalysisReviewRequest, ObservationAnalysisReviewTicket, ObservationConfirmationUndoEligibility) throws -> Void)?
    var prepareRejectionUndo: ((ObservationAnalysisReviewTicket) async throws -> ObservationRejectionUndoEligibility.Resolution)?
    var stageRejectionUndo: ((ObservationAnalysisReviewRequest, ObservationAnalysisReviewTicket, ObservationRejectionUndoEligibility) throws -> Void)?
}

extension IdentificationHistorySession {
    func pendingReview() throws -> ObservationAnalysisReviewStatus? {
        try check()
        return try ObservationAnalysisReviewStatus.pending(ownerID: session.userID,
            observationID: ObservationHistoryPage.uuid(observation), container: container, isCurrent: isCurrent)
    }
    func reviewAccess(wake: @escaping () -> Void, generation: @escaping () -> UInt64) -> IdentificationHistoryReviewAccess {
        var access = IdentificationHistoryReviewAccess(stage: { [self] request, ticket in
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
        if let configuration = confirmationUndo {
            let service = ObservationConfirmationUndoService(cloud: cloud, fetch: configuration.fetch)
            access.prepareConfirmationUndo = { [self] ticket in
                try check()
                guard ticket.ownerID == session.userID, ticket.observationID == (try ObservationHistoryPage.uuid(observation)) else {
                    throw ObservationHistoryError.accountChanged
                }
                let result = try await configuration.owner.prepare(ticket: ticket, session: session, generation: self.generation,
                    container: container, service: service, isCurrent: commonEnvironmentIsCurrent)
                try Task.checkCancellation(); try check()
                return result
            }
            access.stageConfirmationUndo = { [self] request, ticket, eligibility in
                try check()
                guard ticket.ownerID == session.userID, ticket.observationID == (try ObservationHistoryPage.uuid(observation)) else {
                    throw ObservationHistoryError.accountChanged
                }
                _ = try ObservationAnalysisReviewAdmission.stage(request, ticket: ticket, container: container,
                    isCurrent: isCurrent, confirmationUndo: eligibility)
            }
        }
        if let configuration = rejectionUndo {
            let service = ObservationRejectionUndoService(cloud: cloud, fetch: configuration.fetch)
            access.prepareRejectionUndo = { [self] ticket in
                try check()
                guard ticket.ownerID == session.userID, ticket.observationID == (try ObservationHistoryPage.uuid(observation)) else {
                    throw ObservationHistoryError.accountChanged
                }
                let result = try await configuration.owner.prepare(ticket: ticket, session: session, generation: self.generation,
                    container: container, service: service, isCurrent: commonEnvironmentIsCurrent)
                try Task.checkCancellation(); try check()
                return result
            }
            access.stageRejectionUndo = { [self] request, ticket, eligibility in
                try check()
                guard ticket.ownerID == session.userID, ticket.observationID == (try ObservationHistoryPage.uuid(observation)) else {
                    throw ObservationHistoryError.accountChanged
                }
                _ = try ObservationAnalysisReviewAdmission.stage(request, ticket: ticket, container: container,
                    isCurrent: isCurrent, rejectionUndo: eligibility)
            }
        }
        return access
    }
}

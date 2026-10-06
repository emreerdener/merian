import Foundation

/// Explicit community-help consent only. Saved operation delivery belongs to the queue.
@MainActor
struct IdentificationHistoryPublicationAccess {
    struct Configuration {
        let owner: ObservationPublicationPreparationOwner
        let fetch: (ObservationPublicationConsentRequest, UUID) async throws -> ObservationPublicationConsentSnapshot
        let wake: () -> Void
        let generation: () -> UInt64
    }
    var prepare: (ObservationAnalysisReviewTicket) async throws -> ObservationPublicationConsentService.Prepared
    var stage: (ObservationPublicationConsentService.Acceptance) throws -> Void
    var status: (ObservationAnalysisReviewTicket, UUID) throws -> ObservationPublicationOperationStatus?
    var generation: () -> UInt64
}

extension IdentificationHistorySession {
    func publicationAccess(_ configuration: IdentificationHistoryPublicationAccess.Configuration) -> IdentificationHistoryPublicationAccess {
        let service = ObservationPublicationConsentService(cloud: cloud, fetch: configuration.fetch, wake: configuration.wake)
        func validate(_ ticket: ObservationAnalysisReviewTicket) throws {
            try check()
            guard ticket.ownerID == session.userID, ticket.observationID == (try ObservationHistoryPage.uuid(observation)) else {
                throw ObservationHistoryError.accountChanged
            }
        }
        return .init(prepare: { [self] ticket in
            try validate(ticket)
            // Shared work uses only the account/container environment. Closing this
            // presentation must not poison another waiter in the same scope.
            let prepared = try await configuration.owner.prepare(ticket: ticket, session: session, generation: generation,
                container: container, service: service, isCurrent: commonEnvironmentIsCurrent)
            try Task.checkCancellation()
            try check()
            return prepared
        }, stage: { [self] acceptance in
            try check()
            guard acceptance.request.observationID == (try ObservationHistoryPage.uuid(observation)) else {
                throw ObservationHistoryError.accountChanged
            }
            _ = try service.stage(acceptance, container: container, isCurrent: isCurrent)
        }, status: { [self] ticket, operation in
            try validate(ticket)
            return try ObservationPublicationOperationStatus.read(operationID: operation, ownerID: session.userID,
                observationID: ticket.observationID, analysisID: ticket.analysisID, container: container, isCurrent: isCurrent)
        }, generation: configuration.generation)
    }
}

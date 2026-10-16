import Foundation
import Observation

/// One observation's unsaved choice, retained by the parent Insight presentation.
/// Revision changes and History dismissal do not authorize another operation.
@MainActor @Observable
final class PublicationConsentContinuation {
    struct Held {
        let ticket: ObservationAnalysisReviewTicket
        let acceptance: ObservationPublicationConsentService.Acceptance
    }
    private struct Scope: Equatable {
        let owner: UUID
        let observation: UUID
        let container: ObjectIdentifier
    }
    private var scope: Scope?
    private(set) var held: Held?
    private(set) var settledOperation: UUID?
    var isOccupied: Bool { held != nil || settledOperation != nil }

    func bind(owner: UUID, observation: UUID, container: AnyObject) {
        let next = Scope(owner: owner, observation: observation, container: ObjectIdentifier(container))
        if held != nil, scope?.owner == owner, scope?.container == next.container, scope?.observation != observation { return }
        if scope != next { held = nil; settledOperation = nil; scope = next }
    }
    func matches(_ ticket: ObservationAnalysisReviewTicket) -> Bool {
        scope?.owner == ticket.ownerID && scope?.observation == ticket.observationID
    }
    func retain(_ acceptance: ObservationPublicationConsentService.Acceptance, ticket: ObservationAnalysisReviewTicket) throws {
        guard matches(ticket), !isOccupied, acceptance.request.observationID == ticket.observationID,
              acceptance.request.analysisID == ticket.analysisID else { throw ObservationHistoryError.resultConflict }
        held = Held(ticket: ticket, acceptance: acceptance)
    }
    func acknowledge(_ operation: UUID) {
        if held?.acceptance.request.operationID == operation { held = nil; settledOperation = operation }
    }
    func clear() { held = nil; settledOperation = nil; scope = nil }
}

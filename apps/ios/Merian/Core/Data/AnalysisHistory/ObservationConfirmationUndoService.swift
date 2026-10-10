import Foundation
import SwiftData

@MainActor
struct ObservationConfirmationUndoService {
    var cloud: ObservationHistoryCloudClient
    let fetch: (ObservationConfirmationUndoLookup, UUID, @escaping @MainActor @Sendable () throws -> Void) async throws -> ObservationConfirmationUndoReply

    func prepare(ticket: ObservationAnalysisReviewTicket, container: ModelContainer,
                 isCurrent: @escaping @MainActor () -> Bool) async throws -> ObservationConfirmationUndoEligibility.Resolution {
        @MainActor @Sendable func validate() throws -> ObservationConfirmationUndoEligibility? {
            guard !Task.isCancelled, isCurrent() else { throw ObservationHistoryError.accountChanged }
            return try ConfirmedSpeciesReviewPersistence.transaction {
                let context = ModelContext(container)
                let scan = try ObservationHistorySyncService.enrolledScan(ticket.observationID.uuidString, context: context)
                guard try ObservationAnalysisReviewAdmission.currentTicket(ticket, scan: scan, context: context) == ticket,
                      !(try ObservationHistoryEnrollmentIntent.holds(scan.id, context: context)) else {
                    throw ObservationHistoryError.resultConflict
                }
                return try ObservationConfirmationUndoEligibility.local(ticket, context: context)
            }
        }
        if let local = try validate() { return .available(local) }
        let lease = try cloud.begin(ticket.ownerID)
        defer { cloud.finish(lease) }
        guard cloud.isCurrent(lease), lease.session.userID == ticket.ownerID else { throw ObservationHistoryError.accountChanged }
        let reply = try await fetch(ObservationConfirmationUndoEligibility.lookup(ticket), ticket.ownerID) {
            guard cloud.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
            _ = try validate()
        }
        guard cloud.isCurrent(lease) else { throw ObservationHistoryError.accountChanged }
        _ = try validate()
        return try ObservationConfirmationUndoEligibility.recovered(reply, ticket: ticket)
    }
}

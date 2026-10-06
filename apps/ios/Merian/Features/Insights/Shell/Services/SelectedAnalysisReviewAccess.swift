import Foundation
import SwiftData
import UIKit

/// Prepared read/admission only. Opening does not enroll, request consent or send review.
@MainActor
struct SelectedAnalysisReviewAccess {
    var open: (SelectedAnalysisReviewBaseline, ModelContainer) throws -> SelectedAnalysisReviewSession

    static func prepared(cloud: ObservationHistoryCloudClient,
                         session: @escaping (String, ModelContainer) throws -> IdentificationHistorySession) -> Self {
        .init(open: { baseline, container in
            let scope = try session(baseline.observationID.uuidString, container)
            do {
                try scope.check()
                guard let access = scope.dependencies.review else { throw ObservationHistoryError.unavailable }
                let ticket = try ticket(baseline, cloud: cloud, container: container)
                return SelectedAnalysisReviewSession(ticket: ticket, access: access, isScopeCurrent: {
                    (try? scope.check()) != nil
                }, matchesDisplayedTicket: {
                    guard scope.isCurrent() else { return false }
                    return (try? Self.ticket(baseline, cloud: cloud, container: container)) == ticket
                }, close: scope.close, publication: scope.dependencies.publicationConsent, photo: scope.dependencies.photo)
            } catch { scope.close(); throw error }
        })
    }

    private static func ticket(_ baseline: SelectedAnalysisReviewBaseline, cloud: ObservationHistoryCloudClient,
                               container: ModelContainer) throws -> ObservationAnalysisReviewTicket {
        // These listing operations each own the shared nonrecursive lock.
        // Recheck the monotonic context after reading the exact child; admission
        // performs its own final ticket validation in the write transaction.
        let listing = ObservationHistoryListingService(cloud: cloud)
        let state = try listing.context(observationID: baseline.observationID.uuidString, container: container)
        guard state.owner == baseline.ownerID, state.selected == baseline.analysisID,
              state.revision == baseline.revision, state.pendingOperation == nil else {
            throw ObservationHistoryError.resultConflict
        }
        let entry = try listing.cached(observationID: baseline.observationID.uuidString,
            analysisID: baseline.analysisID, container: container)
        let final = try listing.context(observationID: baseline.observationID.uuidString, container: container)
        guard final == state else { throw ObservationHistoryError.resultConflict }
        let ticket = try ObservationAnalysisReviewTicket(entry: entry, context: final, observationID: baseline.observationID)
        guard ticket.analysisID == ticket.selectedAnalysisID else { throw ObservationHistoryError.resultConflict }
        return ticket
    }
}

@MainActor
struct SelectedAnalysisReviewSession {
    let ticket: ObservationAnalysisReviewTicket
    let access: IdentificationHistoryReviewAccess
    let isScopeCurrent: () -> Bool
    let matchesDisplayedTicket: () -> Bool
    let close: () -> Void
    var publication: IdentificationHistoryPublicationAccess?
    var photo: ((UUID, UUID) async throws -> UIImage)?

    func reviewModel(presentationIsCurrent: @escaping () -> Bool) -> IdentificationHistoryReviewModel {
        .init(ticket: ticket, access: access, isCurrent: { presentationIsCurrent() && isScopeCurrent() },
            canStartReview: { presentationIsCurrent() && matchesDisplayedTicket() })
    }
}

import Foundation
import SwiftData

/// Prepared selected-chat access. Reading never enrolls, sends or claims an operation.
@MainActor
struct ProtectedInsightChatAccess {
    var open: (SelectedAnalysisReviewBaseline, ModelContainer) throws -> Session

    struct Session {
        let ticket: ProtectedInsightChatTicket
        let status: (UUID?) throws -> ProtectedInsightChatPersistence.StatusPage
        let isCurrent: () -> Bool
        let matchesDisplayedTicket: () -> Bool
        let close: () -> Void
    }

    static func prepared(cloud: ObservationHistoryCloudClient,
                         session: @escaping (String, ModelContainer) throws -> IdentificationHistorySession) -> Self {
        .init(open: { baseline, container in
            let scope = try session(baseline.observationID.uuidString, container)
            do {
                try scope.check()
                let frozen = try ticket(baseline, cloud: cloud, container: container)
                try scope.check()
                return Session(ticket: frozen, status: { after in
                    try ProtectedInsightChatPersistence.status(ownerID: frozen.ownerID, observationID: frozen.observationID,
                        afterMessageID: after, container: container, isCurrent: scope.isCurrent)
                }, isCurrent: scope.isCurrent, matchesDisplayedTicket: {
                    guard scope.isCurrent() else { return false }
                    return (try? ticket(baseline, cloud: cloud, container: container)) == frozen
                }, close: scope.close)
            } catch { scope.close(); throw error }
        })
    }

    private static func ticket(_ baseline: SelectedAnalysisReviewBaseline, cloud: ObservationHistoryCloudClient,
                               container: ModelContainer) throws -> ProtectedInsightChatTicket {
        let listing = ObservationHistoryListingService(cloud: cloud)
        let state = try listing.context(observationID: baseline.observationID.uuidString, container: container)
        guard state.owner == baseline.ownerID, state.selected == baseline.analysisID,
              state.revision == baseline.revision, state.pendingOperation == nil else { throw ObservationHistoryError.resultConflict }
        let entry = try listing.cached(observationID: baseline.observationID.uuidString,
            analysisID: baseline.analysisID, container: container)
        let final = try listing.context(observationID: baseline.observationID.uuidString, container: container)
        guard final == state else { throw ObservationHistoryError.resultConflict }
        return try ProtectedInsightChatTicket(entry: entry, context: final, observationID: baseline.observationID)
    }
}

import Foundation
import SwiftData

/// Prepared selected-chat access. Reading never enrolls, sends or claims an operation.
@MainActor
struct ProtectedInsightChatAccess {
    var open: (SelectedAnalysisReviewBaseline, ModelContainer) throws -> Session

    struct Configuration {
        let deliver: (ProtectedInsightChatIntent, ProtectedInsightChatDeliveryService.Admission, ModelContainer) -> Bool
        let generation: () -> UInt64
    }

    struct Session {
        let ticket: ProtectedInsightChatTicket
        let status: (UUID?) throws -> ProtectedInsightChatPersistence.StatusPage
        let isCurrent: () -> Bool
        let matchesDisplayedTicket: () -> Bool
        let close: () -> Void
        var stage: (ProtectedInsightChatRequest, ProtectedInsightChatTicket) throws -> ProtectedInsightChatIntent = { _, _ in throw ObservationHistoryError.unavailable }
        var deliver: (ProtectedInsightChatIntent, Bool) throws -> Bool = { _, _ in throw ObservationHistoryError.unavailable }
        var generation: () -> UInt64 = { 0 }
        var recoveryAllowed: (ProtectedInsightChatIntent) throws -> Bool = { _ in false }
    }

    static func prepared(cloud: ObservationHistoryCloudClient, configuration: Configuration? = nil,
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
                }, close: scope.close, stage: { request, ticket in
                    guard configuration != nil, ticket.ownerID == frozen.ownerID,
                          ticket.observationID == frozen.observationID else { throw ObservationHistoryError.unavailable }
                    guard request.observationID == ticket.observationID, request.selection == ticket.selection else {
                        throw ObservationHistoryError.resultConflict
                    }
                    if ticket != frozen {
                        // An older retained candidate can recover only an already saved exact
                        // request. This session never admits a newly supplied unseen ticket.
                        let original = try ProtectedInsightChatIntent(request: request, ownerID: ticket.ownerID)
                        return try ProtectedInsightChatPersistence.read(original, container: container, isCurrent: scope.isCurrent)
                    }
                    return try ProtectedInsightChatPersistence.stage(request, ticket: ticket,
                        container: container, isCurrent: scope.isCurrent)
                }, deliver: { intent, replay in
                    guard scope.isCurrent(), intent.ownerID == frozen.ownerID,
                          intent.request.observationID == frozen.observationID, let configuration else { throw ObservationHistoryError.unavailable }
                    let admission: ProtectedInsightChatDeliveryService.Admission
                    if replay {
                        let status = try ProtectedInsightChatPersistence.status(ownerID: frozen.ownerID, observationID: frozen.observationID,
                            container: container, isCurrent: scope.isCurrent)
                        guard let pending = status.unfinished, pending.intent.request == intent.request else { throw ObservationHistoryError.unavailable }
                        guard let claim = try ProtectedInsightChatPersistence.currentAttempt(intent, container: container, isCurrent: scope.isCurrent) else {
                            throw ObservationHistoryError.unavailable
                        }
                        guard pending.state == .held || (pending.state == .running && Date() >= claim.expiresAt) else {
                            throw ObservationHistoryError.unavailable
                        }
                        admission = .explicitReplay(claim)
                    } else { admission = .initial }
                    // The injected queue retains common account scope, never this presentation.
                    return configuration.deliver(intent, admission, container)
                }, generation: configuration?.generation ?? { 0 }, recoveryAllowed: { intent in
                    guard scope.isCurrent(), intent.ownerID == frozen.ownerID,
                          intent.request.observationID == frozen.observationID else { throw ObservationHistoryError.unavailable }
                    guard let claim = try ProtectedInsightChatPersistence.currentAttempt(intent, container: container, isCurrent: scope.isCurrent) else { return false }
                    return Date() >= claim.expiresAt
                })
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

import Foundation
import SwiftData

/// Explicit submission only. Binds current advisory permission once and durably admits the same child.
/// It never uploads, dispatches inference, changes selection or revives attempted held work.
@MainActor
struct ObservationReanalysisAdmission {
    typealias Validator = ObservationReanalysisExecutor.Validator
    var account = ObservationHistoryCloudClient.live
    var preflight: (ObservationReanalysisPreflightRequest, UUID, @escaping Validator) async throws -> IdentificationDispatchAuthorization = {
        try await MerianNetworkClient.shared.prepareObservationReanalysisAdmissionAuthorization(
            input: $0, expectedAuthUserID: $1, validateAttempt: $2)
    }
    var authorizeBound: (IdentificationRecipientExpectation, UUID, @escaping Validator) async throws -> IdentificationDispatchAuthorization = {
        try await MerianNetworkClient.shared.prepareBoundObservationReanalysisAuthorization(
            processor: $0, expectedAuthUserID: $1, validateAttempt: $2)
    }
    var now: () -> Date = Date.init

    func admit(_ draft: ObservationReanalysisDraft, container: ModelContainer,
               isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationReanalysisExecutionStore.Snapshot {
        let lease = try account.begin(draft.identity.ownerID)
        defer { account.finish(lease) }
        let current: @MainActor @Sendable () -> Bool = {
            lease.session.userID == draft.identity.ownerID && account.isCurrent(lease) && isCurrent()
        }
        let read: @MainActor @Sendable () throws -> ObservationReanalysisPersistence.DraftState = {
            try Task.checkCancellation()
            guard case let .ready(state) = try ObservationReanalysisPersistence.preparation(draft.identity,
                container: container, isCurrent: current) else { throw ObservationReanalysisPersistence.IntegrityError.unavailable }
            switch state {
            case let .draft(saved):
                guard saved == draft else { throw ObservationReanalysisPersistence.IntegrityError.conflict }
            case let .bound(saved):
                guard saved.intent.identity == draft.identity, saved.intent.request.evidence == draft.evidence else {
                    throw ObservationReanalysisPersistence.IntegrityError.conflict
                }
            }
            return state
        }
        let state = try read()
        let validate: Validator = { _ = try read() }
        let authorization: IdentificationDispatchAuthorization
        switch state {
        case .draft:
            let input = try ObservationReanalysisPreflightRequest(observationID: draft.identity.observationID,
                analysisID: draft.identity.analysisID, sourceAnalysisID: draft.identity.sourceAnalysisID)
            authorization = try await preflight(input, draft.identity.ownerID, validate)
        case let .bound(saved):
            let snapshot = try ObservationReanalysisExecutionStore.read(draft.identity, container: container, isCurrent: current)
            // Admission replay reports the durable state, without re-preflight, permission I/O or revival.
            guard snapshot.status == .needsAttention, snapshot.attempt == 0 else { return snapshot }
            authorization = try await authorizeBound(saved.intent.request.processor, draft.identity.ownerID, validate)
            guard authorization.recipient == saved.intent.request.processor else { throw ObservationReanalysisPersistence.IntegrityError.conflict }
        }
        try validate()
        guard authorization.recipient != .recoveryOnly else { throw ObservationReanalysisPersistence.IntegrityError.conflict }
        try authorization.validate()
        return try ObservationReanalysisExecutionStore.bindAndAdmit(draft, processor: authorization.recipient,
            now: now(), container: container, isCurrent: current)
    }
}

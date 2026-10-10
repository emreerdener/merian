import Foundation
import SwiftData

/// Explicit submission only. Binds current advisory permission once and durably admits the same child.
/// It never uploads, dispatches inference, changes selection or revives attempted held work.
@MainActor
struct ObservationReanalysisAdmission {
    enum Failure: Error { case recoveryOnly }
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
               admissionClaim: ObservationReanalysisAdmissionStore.Claim? = nil,
               isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationReanalysisExecutionStore.Snapshot {
        let lease = try account.begin(draft.identity.ownerID)
        defer { account.finish(lease) }
        let current: @MainActor @Sendable () -> Bool = {
            lease.session.userID == draft.identity.ownerID && account.isCurrent(lease) && isCurrent()
        }
        let submissionProof: ObservationReanalysisPreparationIntent.Verified?
        if case let .submitted(saved) = try Self.state(draft.identity, claim: admissionClaim, proof: nil,
            container: container, isCurrent: current) {
            guard saved.draft == draft else { throw ObservationReanalysisPersistence.IntegrityError.conflict }
            let source = try ObservationReanalysisSource.capture(observationID: draft.identity.observationID,
                analysisID: draft.identity.sourceAnalysisID, ownerID: draft.identity.ownerID, container: container)
            submissionProof = try await DetachedWork.value(category: .inferenceRequestPreparation) {
                try saved.preparation.verified(source: source)
            }
        } else { submissionProof = nil }
        let read: @MainActor @Sendable () throws -> ObservationReanalysisPersistence.DraftState = {
            try Task.checkCancellation()
            let state = try Self.state(draft.identity, claim: admissionClaim, proof: submissionProof, container: container, isCurrent: current)
            switch state {
            case let .draft(saved):
                guard saved == draft, submissionProof == nil else { throw ObservationReanalysisPersistence.IntegrityError.conflict }
            case let .submitted(saved):
                guard saved.draft == draft, submissionProof?.pending == saved.preparation else { throw ObservationReanalysisPersistence.IntegrityError.conflict }
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
        case .draft, .submitted:
            let input = try ObservationReanalysisPreflightRequest(observationID: draft.identity.observationID,
                analysisID: draft.identity.analysisID, sourceAnalysisID: draft.identity.sourceAnalysisID)
            authorization = try await preflight(input, draft.identity.ownerID, validate)
        case let .bound(saved):
            let snapshot = try ObservationReanalysisExecutionStore.read(draft.identity, container: container, isCurrent: current)
            // Admission replay reports the durable state, without re-preflight, permission I/O or revival.
            guard snapshot.status == .needsAttention, snapshot.attempt == 0, snapshot.dispatch == .ready else { return snapshot }
            authorization = try await authorizeBound(saved.intent.request.processor, draft.identity.ownerID, validate)
            guard authorization.recipient == saved.intent.request.processor else { throw ObservationReanalysisPersistence.IntegrityError.conflict }
        }
        try validate()
        guard authorization.recipient != .recoveryOnly else { throw Failure.recoveryOnly }
        try authorization.validate()
        return try ObservationReanalysisExecutionStore.bindAndAdmit(draft, processor: authorization.recipient,
            now: now(), container: container, isCurrent: current, submissionProof: submissionProof, admissionClaim: admissionClaim)
    }

    private static func state(_ identity: OfflineQueueWork.Reanalysis, claim: ObservationReanalysisAdmissionStore.Claim?,
                              proof: ObservationReanalysisPreparationIntent.Verified?, container: ModelContainer,
                              isCurrent: () -> Bool) throws -> ObservationReanalysisPersistence.DraftState {
        if let claim {
            guard claim.snapshot.identity == identity, claim.snapshot.work.phase == .admissionPending else {
                throw ObservationReanalysisPersistence.IntegrityError.conflict
            }
            let current = try ObservationReanalysisAdmissionStore.validate(claim, container: container, isCurrent: isCurrent, proof: proof)
            return .submitted(.init(preparation: current.work.preparation))
        }
        guard case let .ready(state) = try ObservationReanalysisPersistence.preparation(identity,
            container: container, isCurrent: isCurrent, submissionProof: proof) else { throw ObservationReanalysisPersistence.IntegrityError.unavailable }
        return state
    }
}

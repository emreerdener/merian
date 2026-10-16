import Foundation
import SwiftData

/// One claimed, owner-fenced attempt. The future scheduler owns single-flight, drain and wakeup.
@MainActor
struct ObservationReanalysisExecutor {
    typealias Store = ObservationReanalysisExecutionStore
    typealias Validator = @MainActor @Sendable () throws -> Void
    enum Outcome { case completed(ObservationReanalysisErasureReceipt), waiting, held(Store.Hold) }
    struct Dependencies {
        var recover: (ObservationReanalysisIntent, @escaping Validator) async throws -> Data?
        var authorize: (ObservationReanalysisIntent, @escaping Validator) async throws -> IdentificationDispatchAuthorization
        var read: (ObservationReanalysisDraft, @escaping Validator) async throws -> [ObservationEvidenceUpload.Photo]
        var upload: (ObservationEvidenceUpload, UUID, @escaping Validator) async throws -> ObservationEvidenceUploadReceipt
        var analyze: (ObservationReanalysisIntent, IdentificationDispatchAuthorization) async throws -> ObservationAnalysisReceipt

        static func live(files: ObservationReanalysisFileStore, client: MerianNetworkClient) -> Self {
            Self(recover: { intent, validate in
                try await client.recoverObservationAnalysis(intent.request, expectedAuthUserID: intent.ownerID, validateAttempt: validate)
            }, authorize: { intent, validate in
                try await client.prepareBoundObservationReanalysisAuthorization(processor: intent.request.processor,
                    expectedAuthUserID: intent.ownerID, validateAttempt: validate)
            }, read: { draft, validate in
                try await files.readPhotos(draft: draft, validateBeforeRead: validate, validateBeforeReturn: validate)
            }, upload: { upload, owner, validate in
                try await client.uploadObservationEvidence(upload, ownerID: owner, validateAttempt: validate)
            }, analyze: { intent, authorization in
                try await client.analyzeObservation(intent.request, ownerID: intent.ownerID, authorization: authorization)
            })
        }
    }
    var dependencies: Dependencies
    var account = ObservationHistoryCloudClient.live
    var now: () -> Date = Date.init
    var saveDispatch: (ModelContext) throws -> Void = { try $0.save() }

    @MainActor private final class CurrentClaim {
        var value: Store.Claim
        init(_ value: Store.Claim) { self.value = value }
    }

    func execute(_ expected: Store.Snapshot, admission: Store.Admission, container: ModelContainer,
                 isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> Outcome {
        let owner = expected.intent.ownerID, lease = try account.begin(expected.intent.ownerID)
        defer { account.finish(lease) }
        let current: @MainActor @Sendable () -> Bool = {
            lease.session.userID == owner && account.isCurrent(lease) && isCurrent()
        }
        let claim = CurrentClaim(try Store.claim(expected, admission: admission, now: now(), container: container, isCurrent: current))
        let validate: Validator = {
            try Task.checkCancellation()
            try Store.validate(claim.value, container: container, isCurrent: current)
        }
        let phase: Phase
        do {
            phase = try await perform(claim.value.intent, dispatch: claim.value.snapshot.dispatch, validate: validate) {
                claim.value = try Store.consumeDispatch(claim.value, container: container, isCurrent: current, save: saveDispatch)
            }
        } catch {
            // Stale/cancelled owners cannot settle over deletion or a newer claim.
            try validate()
            if error is CancellationError { throw error }
            let hold = Self.hold(for: error)
            return try settle(claim.value, hold: hold, server: nil, container: container, current: current)
        }
        try validate()
        switch phase {
        case let .result(bytes):
            // Local save errors stay outside transport classification. A replacement owner recovers.
            return .completed(try Store.complete(claim.value, resultBytes: bytes, container: container, isCurrent: current))
        case .recoveryPending:
            return try settle(claim.value, hold: nil, server: claim.value.snapshot.server, container: container, current: current)
        case let .receipt(state):
            return try settle(claim.value, hold: state == .failedTerminal ? .terminalFailure : nil,
                server: state, container: container, current: current)
        }
    }

    private enum Phase { case result(Data), receipt(ObservationAnalysisReceipt.State), recoveryPending }
    private func perform(_ intent: ObservationReanalysisIntent, dispatch: ObservationReanalysisIntent.Dispatch,
                         validate: @escaping Validator, consume: () throws -> Void) async throws -> Phase {
        try validate()
        let recovered = try await dependencies.recover(intent, validate)
        try validate()
        if let recovered { return .result(recovered) }
        guard dispatch == .ready else { return .recoveryPending }
        let authorization = try await dependencies.authorize(intent, validate)
        try validate()
        guard authorization.recipient == intent.request.processor, authorization.recipient != .recoveryOnly else { throw MerianError.invalidResponse }
        let draft = try ObservationReanalysisDraft(identity: intent.identity, evidence: intent.request.evidence)
        let photos = try await dependencies.read(draft, validate)
        try validate()
        let upload = try ObservationEvidenceUpload(observationID: intent.request.observationID, analysisID: intent.request.analysisID, photos: photos)
        // The locked file owner verifies bytes; also bind its output to the entire immutable cohort.
        let references = try await DetachedWork.value(category: .inferenceRequestPreparation) { try upload.prepare().references }
        try validate()
        let expectedPhotos = intent.request.evidence.compactMap { item -> ObservationEvidenceUpload.Reference? in
            if case let .image(photo) = item { return photo }; return nil
        }
        guard references == expectedPhotos else { throw ObservationHistoryError.resultConflict }
        let receipt = try await dependencies.upload(upload, intent.ownerID, validate)
        try validate()
        guard receipt.observationID == intent.request.observationID, receipt.analysisID == intent.request.analysisID,
              receipt.items == expectedPhotos else { throw ObservationHistoryError.resultConflict }
        try authorization.validate()
        try consume()
        try validate()
        let state = try await dependencies.analyze(intent, authorization)
        try validate()
        guard state.observationID == intent.request.observationID, state.analysisID == intent.request.analysisID else { throw MerianError.invalidResponse }
        if state.state == .complete {
            let completed = try await dependencies.recover(intent, validate)
            try validate()
            if let completed { return .result(completed) }
        }
        return .receipt(state.state)
    }

    private func settle(_ claim: Store.Claim, hold: Store.Hold?, server: ObservationAnalysisReceipt.State?,
                        container: ModelContainer, current: () -> Bool) throws -> Outcome {
        let hold = hold ?? (OfflineQueueRetryPolicy.canScheduleAutomaticRetry(currentAttempt: claim.snapshot.attempt) ? nil : .retryLimit)
        let instant = now()
        if let hold {
            try Store.settle(claim, as: .held(hold), now: instant, container: container, isCurrent: current)
            return .held(hold)
        }
        let due = instant.addingTimeInterval(OfflineQueueRetryPolicy.jitteredDelay(forAttempt: claim.snapshot.attempt, scope: .maintenance))
        try Store.settle(claim, as: .waiting(until: due, server: server), now: instant, container: container, isCurrent: current)
        return .waiting
    }

    private static func hold(for error: Error) -> Store.Hold? {
        if let failure = error as? ObservationReanalysisFileStore.Failure {
            switch failure {
            case .conflict, .incomplete: return .evidenceUnavailable
            default: return nil
            }
        }
        if let failure = error as? ObservationHistoryError {
            switch failure {
            case .resultConflict, .invalidSnapshot, .invalidPage: return .reconciliationRequired
            default: return nil
            }
        }
        guard let error = error as? MerianError else { return nil }
        switch error {
        case .aiConsentRequired, .openAIConsentRequired: return .consentRequired
        case .invalidResponse: return .reconciliationRequired
        case let .httpError(_, message):
            guard message.utf8.count <= 8_192,
                  let row = try? JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any],
                  let code = row["code"] as? String else { return nil }
            switch code {
            case "analysis_history_evidence_unavailable": return .evidenceUnavailable
            case "analysis_history_operation_conflict", "invalid_analysis_history", "analysis_history_not_found": return .reconciliationRequired
            default: return nil
            }
        default: return nil
        }
    }
}

/// Retirement can only recover an outcome or replay its fixed retirement RPC; it has no provider dependencies.
@MainActor
struct ObservationReanalysisRetirementExecutor {
    typealias Store = ObservationReanalysisExecutionStore
    typealias Validator = ObservationReanalysisExecutor.Validator
    struct Dependencies {
        var recover: (ObservationReanalysisIntent, @escaping Validator) async throws -> Data?
        var retire: (ObservationAnalysisRetirementRequest, UUID, @escaping Validator, @escaping Validator) async throws -> ObservationAnalysisRetirementReceipt

        static func live(client: MerianNetworkClient) -> Self {
            Self(recover: { intent, validate in
                try await client.recoverObservationAnalysis(intent.request, expectedAuthUserID: intent.ownerID, validateAttempt: validate)
            }, retire: { request, owner, attempt, response in
                try await client.analysisRetirementTransport().retire(request, ownerID: owner,
                    validateAttempt: attempt, validateResponse: response)
            })
        }
    }
    let dependencies: Dependencies
    var now: () -> Date = Date.init

    func execute(_ expected: Store.Snapshot, admission: Store.RetirementAdmission, container: ModelContainer,
                 mayDispatch: @escaping @MainActor @Sendable () -> Bool,
                 maySettleKnownReceipt: @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationReanalysisExecutor.Outcome {
        let claim = try Store.claimRetirement(expected, admission: admission, now: now(), container: container, isCurrent: mayDispatch)
        let validate: Validator = {
            try Task.checkCancellation()
            try Store.validateRetirement(claim, container: container, isCurrent: mayDispatch)
        }
        let validateResponse: Validator = {
            guard maySettleKnownReceipt() else { throw ObservationHistoryError.accountChanged }
            // completeRetirement performs the fresh full-claim CAS immediately after the typed response.
        }
        let recovered: Data?
        do {
            try validate()
            recovered = try await dependencies.recover(expected.intent, validate)
            try validate()
        } catch {
            try validate()
            try Store.holdRetirement(claim, now: now(), container: container, isCurrent: mayDispatch)
            return .held(.reconciliationRequired)
        }
        if let recovered {
            return .completed(try Store.completeRetirementOutcome(claim, resultBytes: recovered, container: container, isCurrent: mayDispatch))
        }
        let proof: ObservationAnalysisRetirementReceipt
        do {
            try validate()
            proof = try await dependencies.retire(claim.request, expected.intent.ownerID, validate, validateResponse)
        } catch {
            try validate()
            // A competing dispatch may have completed after the first read. One exact read, never analyze.
            let outcome = try? await dependencies.recover(expected.intent, validate)
            try validate()
            if let outcome {
                return .completed(try Store.completeRetirementOutcome(claim, resultBytes: outcome, container: container, isCurrent: mayDispatch))
            }
            try Store.holdRetirement(claim, now: now(), container: container, isCurrent: mayDispatch)
            return .held(.reconciliationRequired)
        }
        try validateResponse()
        return .completed(try Store.completeRetirement(claim, proof: proof, container: container, isCurrent: maySettleKnownReceipt))
    }
}

import Foundation
import SwiftData

/// One advisory phase under the same owner as Capture. This never uploads or dispatches inference.
@MainActor
struct ObservationReanalysisAdmissionExecutor {
    typealias Store = ObservationReanalysisAdmissionStore
    typealias Validator = ObservationReanalysisPreparationOwner.Validator
    enum Outcome: Equatable, Sendable {
        case filesReady, admitted, deferred, unclaimed, waiting, held(ObservationReanalysisAdmissionWork.Hold)
    }
    private final class Progress { var claim: Store.Claim? }
    let files: ObservationReanalysisFileStore
    let ownership: ObservationReanalysisPreparationOwner
    var admission = ObservationReanalysisAdmission()
    var account = ObservationHistoryCloudClient.live
    var now: () -> Date = Date.init

    func execute(_ candidate: Store.Candidate, container: ModelContainer,
                 consentGranted: @escaping Validator, canPreflight: @escaping Validator, isCurrent: @escaping Validator) async throws -> Outcome {
        let identity = candidate.snapshot.identity, lease = try account.begin(candidate.snapshot.identity.ownerID)
        defer { account.finish(lease) }
        let current: Validator = {
            lease.session.userID == identity.ownerID && account.isCurrent(lease) && isCurrent()
        }
        let outcome = try await ownership.perform(identity) { tokenCurrent in
            try await executeOwned(candidate, container: container, consentGranted: consentGranted, canPreflight: canPreflight,
                isCurrent: { current() && tokenCurrent() })
        }
        try Task.checkCancellation()
        guard current() else { throw ObservationHistoryError.accountChanged }
        // A phase commit can survive account loss; its former owner cannot receive a private result.
        if outcome == .admitted {
            _ = try ObservationReanalysisExecutionStore.read(identity, container: container, isCurrent: current)
        } else {
            _ = try Store.read(identity, container: container, isCurrent: current)
        }
        return outcome
    }

    private func executeOwned(_ candidate: Store.Candidate, container: ModelContainer,
                              consentGranted: @escaping Validator, canPreflight: @escaping Validator, isCurrent: @escaping Validator) async throws -> Outcome {
        let expected = candidate.snapshot, progress = Progress()
        let validate: ObservationReanalysisExecutor.Validator = {
            try Task.checkCancellation()
            if let claim = progress.claim {
                try Store.validate(claim, container: container, isCurrent: isCurrent)
            } else {
                guard try Store.read(expected.identity, container: container, isCurrent: isCurrent) == expected else {
                    throw ObservationReanalysisPersistence.IntegrityError.conflict
                }
            }
        }
        try validate()
        guard candidate.due <= now() else { return .deferred }
        if expected.work.phase == .admissionPending, !consentGranted() || !canPreflight() { return .deferred }
        do {
            if expected.work.phase == .filesPending {
                let source = try ObservationReanalysisSource.capture(observationID: expected.identity.observationID,
                    analysisID: expected.identity.sourceAnalysisID, ownerID: expected.identity.ownerID, container: container)
                let proof = try await DetachedWork.value(category: .inferenceRequestPreparation) {
                    try expected.work.preparation.verified(source: source)
                }
                try validate()
                // The original v4 remains untouched until the verifier holds the filesystem locks.
                _ = try await files.recover(draft: expected.work.preparation.draft, validateBeforeRead: {
                    try validate()
                    progress.claim = try Store.claim(expected, admission: candidate.admission, now: now(),
                        container: container, isCurrent: isCurrent, proof: proof)
                }) {
                    try validate()
                    guard let claim = progress.claim else { throw ObservationHistoryError.unavailable }
                    return try Store.promoteVerifiedFiles(claim, proof: proof, container: container, isCurrent: isCurrent)
                }
                try Task.checkCancellation()
                return .filesReady
            }
            progress.claim = try Store.claim(expected, admission: candidate.admission, now: now(), container: container, isCurrent: isCurrent)
            guard let claim = progress.claim else { throw ObservationHistoryError.unavailable }
            guard OfflineQueueRetryPolicy.canScheduleAutomaticRetry(currentAttempt: expected.work.attempt) else {
                return try settle(claim, hold: .retryLimit, container: container, isCurrent: isCurrent)
            }
            // Admission calls this at dispatch and after await, including just before one-time binding.
            let permission: Validator = { isCurrent() && consentGranted() && canPreflight() }
            _ = try await admission.admit(expected.work.preparation.draft, container: container,
                admissionClaim: claim, isCurrent: permission)
            try Task.checkCancellation()
            return .admitted
        } catch {
            try Task.checkCancellation()
            guard isCurrent() else { throw ObservationHistoryError.accountChanged }
            if error is CancellationError { throw error }
            // A binding commit wins even if its reply or a final callback failed.
            if progress.claim != nil, expected.work.phase == .admissionPending,
               let bound = try? ObservationReanalysisExecutionStore.read(expected.identity, container: container, isCurrent: isCurrent),
               bound.intent.request.evidence == expected.work.preparation.draft.evidence { return .admitted }
            try validate()
            guard let claim = progress.claim else { return .unclaimed }
            let hold: ObservationReanalysisAdmissionWork.Hold?
            if expected.work.phase == .admissionPending, !consentGranted() { hold = .consentRequired } else if error is ObservationReanalysisAdmission.Failure { hold = .reconciliationRequired } else if Self.requiresConsent(error) { hold = .consentRequired } else { hold = nil }
            return try settle(claim, hold: hold, container: container, isCurrent: isCurrent)
        }
    }

    private static func requiresConsent(_ error: Error) -> Bool {
        guard let error = error as? MerianError else { return false }
        switch error {
        case .aiConsentRequired, .openAIConsentRequired: return true
        default: return false
        }
    }

    private func settle(_ claim: Store.Claim, hold: ObservationReanalysisAdmissionWork.Hold?,
                        container: ModelContainer, isCurrent: () -> Bool) throws -> Outcome {
        let hold = hold ?? (OfflineQueueRetryPolicy.canScheduleAutomaticRetry(currentAttempt: claim.snapshot.work.attempt) ? nil : .retryLimit)
        let instant = now()
        if let hold {
            try Store.settle(claim, as: .held(hold), now: instant, container: container, isCurrent: isCurrent)
            return .held(hold)
        }
        let due = instant.addingTimeInterval(OfflineQueueRetryPolicy.jitteredDelay(forAttempt: claim.snapshot.work.attempt, scope: .maintenance))
        try Store.settle(claim, as: .waiting(due), now: instant, container: container, isCurrent: isCurrent)
        return .waiting
    }
}

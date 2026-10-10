import Foundation
import SwiftData

/// Explicit post-preparation binding only. The shared preparation owner retains the account work.
@MainActor
struct ObservationAudioSubmissionBinding {
    typealias Validate = @MainActor @Sendable () throws -> Void
    let ownership: ObservationReanalysisPreparationOwner
    let account: ObservationHistoryCloudClient
    let authorize: @MainActor @Sendable (UUID, @escaping Validate) async throws -> IdentificationDispatchAuthorization

    /// A saved execution request returns before fresh consent, on a later explicit retry after commit-then-throw.
    /// The caller must inspect admissionState before invoking the file producer on a retry.
    func bind(_ proof: ObservationAudioPreparation.Verified, container: ModelContainer,
              isCurrent: @escaping @MainActor @Sendable () -> Bool,
              save: @escaping @MainActor @Sendable (ModelContext) throws -> Void = { try $0.save() }) async throws -> ObservationAudioExecutionStore.Snapshot {
        let result = try await ownership.perform(proof.preparation.identity) { tokenCurrent in
            let lease = try account.begin(proof.preparation.identity.ownerID)
            defer { account.finish(lease) }
            let current: @MainActor @Sendable () -> Bool = { tokenCurrent() && account.isCurrent(lease) && isCurrent() }
            let validate: Validate = {
                try Task.checkCancellation()
                guard current() else { throw ObservationHistoryError.accountChanged }
                try proof.validate(container: container)
            }
            try validate()
            switch try ObservationAudioExecutionStore.admissionState(proof, container: container, isCurrent: current) {
            case let .bound(saved): return saved
            case .preparation(.admissionPending): break
            default: throw ObservationHistoryError.unavailable
            }
            let candidate = try await DetachedWork.value(category: .inferenceRequestPreparation) {
                try ObservationAudioExecutionIntent(preparation: proof.preparation)
            }
            try validate()
            let authorization = try await authorize(proof.preparation.identity.ownerID, validate)
            try validate()
            let saved = try ObservationAudioExecutionStore.bind(candidate, proof: proof, authorization: authorization,
                container: container, isCurrent: current, save: save)
            try validate()
            return saved
        }
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        try proof.validate(container: container)
        return result
    }
}

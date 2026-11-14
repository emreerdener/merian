import Foundation
import SwiftData

/// Account-bound local recovery only. No upload, recipient admission, provider work or replacement identity.
@MainActor
struct ObservationReanalysisPreparationRecovery {
    let files: ObservationReanalysisFileStore
    let ownership: ObservationReanalysisPreparationOwner
    var account = ObservationHistoryCloudClient.live

    func recover(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer,
                 isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationReanalysisPersistence.DraftState {
        let lease = try account.begin(identity.ownerID)
        defer { account.finish(lease) }
        let result = try await ownership.perform(identity) { tokenCurrent in
            try await recoverOwned(identity, container: container, lease: lease, isCurrent: { tokenCurrent() && isCurrent() })
        }
        try Task.checkCancellation()
        guard account.isCurrent(lease), isCurrent() else { throw ObservationHistoryError.accountChanged }
        _ = try ObservationReanalysisPersistence.preparation(identity, container: container,
            isCurrent: { account.isCurrent(lease) && isCurrent() })
        return result
    }

    private func recoverOwned(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer, lease: AccountBoundWorkLease,
                              isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationReanalysisPersistence.DraftState {
        let validateAccount: @MainActor @Sendable () throws -> Void = {
            try Task.checkCancellation()
            guard lease.session.userID == identity.ownerID, account.isCurrent(lease), isCurrent() else { throw ObservationHistoryError.accountChanged }
        }
        try validateAccount()
        let state = try ObservationReanalysisPersistence.preparation(identity, container: container,
            isCurrent: { account.isCurrent(lease) && isCurrent() })
        guard case let .pending(pending) = state else {
            guard case let .ready(ready) = state else { throw ObservationHistoryError.unavailable }
            return ready
        }
        let source = try ObservationReanalysisSource.capture(observationID: identity.observationID,
            analysisID: identity.sourceAnalysisID, ownerID: identity.ownerID, container: container)
        let proof = try await DetachedWork.value(category: .inferenceRequestPreparation) { try pending.verified(source: source) }
        try validateAccount()
        let validate: @MainActor @Sendable (Bool) throws -> Void = { makeReady in
            try validateAccount()
            try ObservationReanalysisPersistence.validatePreparation(proof, container: container,
                isCurrent: { account.isCurrent(lease) && isCurrent() }, makeReady: makeReady)
        }
        let recovered: ObservationReanalysisPersistence.DraftState = try await files.recover(draft: pending.draft, validateBeforeRead: { try validate(false) }) {
            try validate(true)
            return pending.ready
        }
        // A committed phase remains durable even if its former account loses the right to receive this result.
        try validateAccount()
        return recovered
    }
}

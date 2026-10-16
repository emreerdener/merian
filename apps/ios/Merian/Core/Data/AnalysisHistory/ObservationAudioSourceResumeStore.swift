import Foundation
import SwiftData

/// Exact saved V10 source recovery only. No files, consent, claim, binding or dispatch capability.
@MainActor
struct ObservationAudioSourceResumeStore {
    struct Saved: Sendable {
        let source: ObservationReanalysisSource
        let proof: ObservationAudioPreparation.Verified
        let snapshot: ObservationSourceReservationStore.Snapshot
    }
    typealias Verify = @MainActor @Sendable (Data, OfflineQueueWork.Reanalysis, ObservationReanalysisSource) async throws -> ObservationAudioPreparation.Verified
    var verify: Verify = { data, identity, source in
        try await DetachedWork.value(category: .inferenceRequestPreparation) {
            let work = try ObservationSourceReservationWork.decode(data)
            guard work.identity == identity, case let .audio(preparation) = work.preparation,
                  preparation.action == .submit else { throw MerianError.invalidResponse }
            return try preparation.verified(source: source)
        }
    }

    func read(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer,
              isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> Saved {
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        let source = try ObservationReanalysisSource.captureForAudio(observationID: identity.observationID,
            analysisID: identity.sourceAnalysisID, ownerID: identity.ownerID, container: container)
        let original = try ObservationSourceReservationStore.read(identity, container: container, isCurrent: isCurrent)
        guard original.work.identity == identity, case .audio = original.work.preparation else { throw MerianError.invalidResponse }
        let proof = try await verify(Data(original.metadata.utf8), identity, source)
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        try proof.validate(container: container)
        let snapshot = try ObservationSourceReservationStore.read(identity, container: container, isCurrent: isCurrent)
        guard snapshot == original, snapshot.work.preparation == .audio(proof.preparation),
              proof.preparation.identity == identity else { throw ObservationHistoryError.resultConflict }
        return Saved(source: source, proof: proof, snapshot: snapshot)
    }
}

/// Explicit reader retains the existing preparation slot and account lease through actual task exit.
@MainActor
struct ObservationAudioSourceResumeReader {
    let ownership: ObservationReanalysisPreparationOwner
    let account: ObservationHistoryCloudClient
    var store = ObservationAudioSourceResumeStore()

    func read(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer,
              isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationAudioSourceResumeStore.Saved {
        let saved = try await ownership.perform(identity) { tokenCurrent in
            let lease = try account.begin(identity.ownerID)
            defer { account.finish(lease) }
            guard lease.session.userID == identity.ownerID else { throw ObservationHistoryError.accountChanged }
            return try await store.read(identity, container: container, isCurrent: {
                tokenCurrent() && account.isCurrent(lease) && isCurrent()
            })
        }
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        try saved.proof.validate(container: container)
        guard try ObservationSourceReservationStore.read(identity, container: container, isCurrent: isCurrent) == saved.snapshot else {
            throw ObservationHistoryError.resultConflict
        }
        return saved
    }
}

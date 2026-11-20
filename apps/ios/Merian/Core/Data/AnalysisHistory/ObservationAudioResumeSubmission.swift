import Foundation
import SwiftData

/// Explicit saved-child preparation/binding. Each account phase is retained; no nested owner entry or queue start.
@MainActor
struct ObservationAudioResumeSubmission {
    struct Ready: Sendable {
        let proof: ObservationAudioPreparation.Verified
        let snapshot: ObservationAudioExecutionStore.Snapshot
    }
    let producer: ObservationAudioPreparationProducer
    let authorize: @MainActor @Sendable (UUID, @escaping ObservationAudioSubmissionBinding.Validate) async throws -> IdentificationDispatchAuthorization

    func resume(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer,
                isCurrent: @escaping @MainActor @Sendable () -> Bool,
                save: @escaping @MainActor @Sendable (ModelContext) throws -> Void = { try $0.save() }) async throws -> Ready {
        let saved = try await producer.ownership.perform(identity) { tokenCurrent in
            let lease = try producer.account.begin(identity.ownerID)
            defer { producer.account.finish(lease) }
            return try await ObservationAudioResumeStore.read(identity, container: container, isCurrent: {
                tokenCurrent() && producer.account.isCurrent(lease) && isCurrent()
            })
        }
        func validate() throws {
            try Task.checkCancellation()
            guard isCurrent() else { throw ObservationHistoryError.accountChanged }
            try saved.proof.validate(container: container)
        }
        try validate()
        let snapshot: ObservationAudioExecutionStore.Snapshot
        // Re-read after the retained reader exits: another explicit operation may have advanced binding.
        switch try ObservationAudioExecutionStore.admissionState(saved.proof, container: container, isCurrent: isCurrent) {
        case let .bound(existing): snapshot = existing
        case .preparation:
            let phase = try await producer.prepare(saved.proof.preparation, source: saved.source, bytes: nil,
                container: container, isCurrent: isCurrent)
            try validate()
            guard phase == .admissionPending else { throw ObservationHistoryError.resultConflict }
            let binding = ObservationAudioSubmissionBinding(ownership: producer.ownership, account: producer.account, authorize: authorize)
            snapshot = try await binding.bind(saved.proof, container: container, isCurrent: isCurrent, save: save)
        case .unprepared: throw ObservationHistoryError.unavailable
        }
        try validate()
        guard try ObservationAudioExecutionStore.read(saved.proof, container: container, isCurrent: isCurrent) == snapshot else {
            throw ObservationHistoryError.resultConflict
        }
        return Ready(proof: saved.proof, snapshot: snapshot)
    }
}

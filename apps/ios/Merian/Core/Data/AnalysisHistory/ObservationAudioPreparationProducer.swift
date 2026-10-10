import Foundation
import SwiftData

/// Explicit preparation/recovery retaining the original submission intent. Uses the queue's shared owner; no automatic discovery or dispatch.
@MainActor
struct ObservationAudioPreparationProducer {
    let files: ObservationReanalysisFileStore
    let ownership: ObservationReanalysisPreparationOwner
    let account: ObservationHistoryCloudClient

    /// `bytes == nil` requests complete-cohort recovery only; it never repairs missing evidence.
    /// The caller retains the original preparation/child identity across every attempt.
    func prepare(_ preparation: ObservationAudioPreparation, source: ObservationReanalysisSource, bytes: Data?,
                 container: ModelContainer, isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationAudioPreparation.Phase {
        let result = try await ownership.perform(preparation.identity) { tokenCurrent in
            let lease = try account.begin(preparation.identity.ownerID)
            defer { account.finish(lease) }
            let current: @MainActor @Sendable () -> Bool = { tokenCurrent() && account.isCurrent(lease) && isCurrent() }
            let validate: @MainActor @Sendable () throws -> Void = {
                try Task.checkCancellation()
                guard current() else { throw ObservationHistoryError.accountChanged }
                try source.validate(container: container)
            }
            try validate()
            let proof = try await DetachedWork.value(category: .inferenceRequestPreparation) { try preparation.verified(source: source) }
            try validate()
            let phase = try bytes == nil
                ? ObservationAudioPreparationStore.read(proof, container: container, isCurrent: current)
                : ObservationAudioPreparationStore.begin(proof, container: container, isCurrent: current)
            if phase == preparation.preparedPhase {
                let validateReady: @MainActor @Sendable () throws -> Void = {
                    try validate()
                    try ObservationAudioPreparationStore.validate(proof, container: container, isCurrent: current, expectedPhase: preparation.preparedPhase)
                }
                let ready = try await files.recoverAudio(preparation: preparation, validateBeforeRead: validateReady) {
                    try validateReady()
                    return preparation.preparedPhase
                }
                try validate()
                return ready
            }
            let before: @MainActor @Sendable () throws -> Void = {
                try validate()
                try ObservationAudioPreparationStore.validate(proof, container: container, isCurrent: current)
            }
            let commit: @MainActor @Sendable () throws -> ObservationAudioPreparation.Phase = {
                try validate()
                try ObservationAudioPreparationStore.validate(proof, container: container, isCurrent: current, makeReady: true)
                return preparation.preparedPhase
            }
            let prepared: ObservationAudioPreparation.Phase
            if let bytes {
                prepared = try await files.persistAudio(preparation: preparation, bytes: bytes, validateBeforeWrite: before, commit: commit)
            } else {
                prepared = try await files.recoverAudio(preparation: preparation, validateBeforeRead: before, commit: commit)
            }
            try validate()
            return prepared
        }
        // Durable success survives; private presentation does not cross an account/generation transition.
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        try source.validate(container: container)
        return result
    }
}

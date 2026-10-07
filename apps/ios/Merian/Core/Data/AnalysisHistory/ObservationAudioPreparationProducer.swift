import Foundation
import SwiftData

/// Explicit held preparation/recovery. Uses the queue's shared owner; no automatic discovery or dispatch.
@MainActor
struct ObservationAudioPreparationProducer {
    let files: ObservationReanalysisFileStore
    let ownership: ObservationReanalysisPreparationOwner
    let account: ObservationHistoryCloudClient

    /// `bytes == nil` requests complete-cohort recovery only; it never repairs missing evidence.
    /// The caller retains the original preparation/child identity across every attempt.
    func prepare(_ preparation: ObservationAudioPreparation, source: ObservationReanalysisSource, bytes: Data?,
                 container: ModelContainer, isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationAudioPreparation.Phase {
        let lease = try account.begin(preparation.identity.ownerID)
        defer { account.finish(lease) }
        let validate: @MainActor @Sendable () throws -> Void = {
            try Task.checkCancellation()
            guard account.isCurrent(lease), isCurrent() else { throw ObservationHistoryError.accountChanged }
            try source.validate(container: container)
        }
        try validate()
        let result = try await ownership.perform(preparation.identity) { tokenCurrent in
            try validate()
            guard tokenCurrent() else { throw ObservationHistoryError.accountChanged }
            let current: @MainActor @Sendable () -> Bool = { tokenCurrent() && account.isCurrent(lease) && isCurrent() }
            let proof = try await DetachedWork.value(category: .inferenceRequestPreparation) { try preparation.verified(source: source) }
            try validate()
            let phase = try ObservationAudioPreparationStore.begin(proof, container: container, isCurrent: current)
            if phase == .ready {
                let validateReady: @MainActor @Sendable () throws -> Void = {
                    try validate()
                    try ObservationAudioPreparationStore.validate(proof, container: container, isCurrent: current, expectedPhase: .ready)
                }
                return try await files.recoverAudio(preparation: preparation, validateBeforeRead: validateReady) {
                    try validateReady()
                    return ObservationAudioPreparation.Phase.ready
                }
            }
            let before: @MainActor @Sendable () throws -> Void = {
                try validate()
                try ObservationAudioPreparationStore.validate(proof, container: container, isCurrent: current)
            }
            let commit: @MainActor @Sendable () throws -> ObservationAudioPreparation.Phase = {
                try validate()
                try ObservationAudioPreparationStore.validate(proof, container: container, isCurrent: current, makeReady: true)
                return .ready
            }
            if let bytes {
                return try await files.persistAudio(preparation: preparation, bytes: bytes, validateBeforeWrite: before, commit: commit)
            }
            return try await files.recoverAudio(preparation: preparation, validateBeforeRead: before, commit: commit)
        }
        // Durable success survives; private presentation does not cross an account/generation transition.
        try validate()
        return result
    }
}

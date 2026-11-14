import Foundation
import SwiftData

/// Explicit held video preparation/recovery; no automatic discovery, admission or dispatch.
@MainActor
struct ObservationVideoPreparationProducer {
    let files: ObservationReanalysisFileStore
    let ownership: ObservationReanalysisPreparationOwner
    let account: ObservationHistoryCloudClient

    /// Explicit held-only discard, followed by one awaited receipt-authorized cleanup attempt.
    /// Throwing saves never start cleanup; exact receipt replay recovers commit-then-throw.
    func discard(_ preparation: ObservationVideoPreparation, source: ObservationReanalysisSource,
                 container: ModelContainer, cleanup: ObservationReanalysisErasureOwner,
                 isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationReanalysisErasureReceipt {
        let receipt = try await ownership.perform(preparation.identity) { tokenCurrent in
            let lease = try account.begin(preparation.identity.ownerID)
            defer { account.finish(lease) }
            let current: @MainActor @Sendable () -> Bool = { tokenCurrent() && account.isCurrent(lease) && isCurrent() }
            try Task.checkCancellation()
            guard current() else { throw ObservationHistoryError.accountChanged }
            let proof = try await DetachedWork.value(category: .inferenceRequestPreparation) { try preparation.verified(source: source) }
            try Task.checkCancellation()
            guard current() else { throw ObservationHistoryError.accountChanged }
            let receipt = try ObservationVideoPreparationStore.discard(proof, container: container, isCurrent: current)
            await cleanup.erase(receipt, container: container, isCurrent: current)
            try Task.checkCancellation()
            guard current() else { throw ObservationHistoryError.accountChanged }
            return receipt
        }
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        return receipt
    }

    /// `cohort == nil` requests complete-cohort recovery only; it never repairs missing evidence.
    /// The caller retains the original preparation/child identity across every attempt.
    func prepare(_ preparation: ObservationVideoPreparation, source: ObservationReanalysisSource, cohort: ObservationVideoCohort?,
                 container: ModelContainer, isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationVideoPreparation.Phase {
        guard cohort == nil || cohort?.request == preparation.request else { throw MerianError.invalidResponse }
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
            let phase = try cohort == nil
                ? ObservationVideoPreparationStore.read(proof, container: container, isCurrent: current)
                : ObservationVideoPreparationStore.begin(proof, container: container, isCurrent: current)
            if phase == .ready {
                let validateReady: @MainActor @Sendable () throws -> Void = {
                    try validate()
                    try ObservationVideoPreparationStore.validate(proof, container: container, isCurrent: current, expectedPhase: .ready)
                }
                let ready: ObservationVideoPreparation.Phase = try await files.recoverVideo(preparation: preparation, validateBeforeRead: validateReady) {
                    try validateReady()
                    return .ready
                }
                try validate()
                return ready
            }
            let before: @MainActor @Sendable () throws -> Void = {
                try validate()
                try ObservationVideoPreparationStore.validate(proof, container: container, isCurrent: current)
            }
            let commit: @MainActor @Sendable () throws -> ObservationVideoPreparation.Phase = {
                try validate()
                try ObservationVideoPreparationStore.validate(proof, container: container, isCurrent: current, makeReady: true)
                return .ready
            }
            let prepared: ObservationVideoPreparation.Phase
            if let cohort {
                prepared = try await cohort.persist(preparation: preparation, store: files, validateBeforeWrite: before, commit: commit)
            } else {
                prepared = try await files.recoverVideo(preparation: preparation, validateBeforeRead: before, commit: commit)
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

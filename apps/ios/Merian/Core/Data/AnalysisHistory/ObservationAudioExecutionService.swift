import Foundation
import SwiftData

/// One explicit invocation under the queue-retained owner. No timer or automatic adoption.
@MainActor
struct ObservationAudioExecutionService {
    typealias Store = ObservationAudioExecutionStore
    typealias Validate = @MainActor @Sendable () throws -> Void
    typealias Cleanup = @MainActor (ObservationReanalysisErasureReceipt) async -> Void
    enum Outcome: Equatable { case completed, held, unavailable }
    struct Dependencies {
        let read: (ObservationAudioPreparation, @escaping Validate, @escaping Validate) async throws -> Data
        let upload: (ObservationAudioEvidenceUpload, UUID, @escaping Validate) async throws -> ObservationAudioEvidenceUploadReceipt
        let authorize: (UUID, @escaping Validate) async throws -> IdentificationDispatchAuthorization
        let analyze: (Store.DispatchPermit, IdentificationDispatchAuthorization, @escaping Validate, @escaping Validate) async throws -> ObservationAnalysisReceipt
        let outcome: (Store.Claim, @escaping Validate, @escaping Validate) async throws -> Data?
    }
    let dependencies: Dependencies
    /// A throwing consumption save never produces a provider capability, even when committed.
    var consumeSave: (ModelContext) throws -> Void = { try $0.save() }

    func run(_ entry: Store.Snapshot, proof: ObservationAudioPreparation.Verified,
             container: ModelContainer, scope: ObservationAudioExecutionOwner.Scope, cleanup: Cleanup) async -> Outcome {
        guard scope.matchesEntry(entry, container: ObjectIdentifier(container)) else { return .unavailable }
        do {
            try requireDispatch(scope)
            var saved = try Store.readForInterruption(proof, container: container, scope: scope)
            guard saved == entry else { return .unavailable }
            if saved.work.state == .running {
                saved = try Store.interruptRunning(saved, proof: proof, container: container, scope: scope)
            }
            let claim: Store.Claim
            if saved.work.consumedAttempt != nil {
                claim = try Store.claim(saved, purpose: .recovery, proof: proof, container: container, isCurrent: scope.mayDispatch)
                return try await recover(claim, proof: proof, container: container, scope: scope, cleanup: cleanup)
            }
            if saved.work.state == .held {
                let expected = saved
                let validate: Validate = {
                    try requireDispatch(scope)
                    guard try Store.read(proof, container: container, isCurrent: scope.mayDispatch) == expected else {
                        throw MerianError.invalidResponse
                    }
                }
                try validate()
                let authorization = try await dependencies.authorize(saved.work.intent.ownerID, validate)
                try validate()
                claim = try Store.resumeUndispatched(saved, proof: proof, authorization: authorization,
                    container: container, isCurrent: scope.mayDispatch)
            } else {
                claim = try Store.claim(saved, purpose: .initial, proof: proof, container: container, isCurrent: scope.mayDispatch)
            }
            return try await dispatch(claim, proof: proof, container: container, scope: scope, cleanup: cleanup)
        } catch {
            return interrupt(proof, container: container, scope: scope)
        }
    }

    private func dispatch(_ claim: Store.Claim, proof: ObservationAudioPreparation.Verified,
                          container: ModelContainer, scope: ObservationAudioExecutionOwner.Scope, cleanup: Cleanup) async throws -> Outcome {
        let validate = dispatchValidation(claim, proof: proof, container: container, scope: scope)
        try validate()
        let preparation = proof.preparation, identity = preparation.identity
        let bytes = try await dependencies.read(preparation, validate, validate)
        try validate()
        let upload = try ObservationAudioEvidenceUpload(observationID: identity.observationID, analysisID: identity.analysisID,
            mediaID: preparation.audio.mediaID, bytes: bytes)
        let receipt = try await dependencies.upload(upload, identity.ownerID, validate)
        try validate()
        guard receipt.observationID == identity.observationID, receipt.analysisID == identity.analysisID,
              receipt.reference == preparation.audio else { throw MerianError.invalidResponse }
        let authorization = try await dependencies.authorize(identity.ownerID, validate)
        try validate()
        guard authorization.recipient == .gemini else { throw MerianError.aiConsentRequired }
        try authorization.validate()
        let permit = try Store.consume(claim, proof: proof, container: container, isCurrent: scope.mayDispatch, save: consumeSave)
        let before: Validate = {
            try requireDispatch(scope)
            try Store.validateDispatch(permit, proof: proof, container: container, isCurrent: scope.mayDispatch)
        }
        try before()
        let result = try await dependencies.analyze(permit, authorization, before, settlementValidation(scope))
        try settlementValidation(scope)()
        guard result.observationID == identity.observationID, result.analysisID == identity.analysisID else { throw MerianError.invalidResponse }
        guard result.state == .complete else { return interrupt(proof, container: container, scope: scope) }
        return try await recover(permit.claim, proof: proof, container: container, scope: scope, cleanup: cleanup)
    }

    private func recover(_ claim: Store.Claim, proof: ObservationAudioPreparation.Verified,
                         container: ModelContainer, scope: ObservationAudioExecutionOwner.Scope, cleanup: Cleanup) async throws -> Outcome {
        let before = dispatchValidation(claim, proof: proof, container: container, scope: scope)
        try before()
        let bytes = try await dependencies.outcome(claim, before, settlementValidation(scope))
        try settlementValidation(scope)()
        guard let bytes else { return interrupt(proof, container: container, scope: scope) }
        let receipt = try Store.complete(claim, resultBytes: bytes, proof: proof, container: container, isCurrent: scope.maySettleKnownReceipt)
        await cleanup(receipt)
        return .completed
    }

    private func interrupt(_ proof: ObservationAudioPreparation.Verified, container: ModelContainer,
                           scope: ObservationAudioExecutionOwner.Scope) -> Outcome {
        do {
            let saved = try Store.readForInterruption(proof, container: container, scope: scope)
            if saved.work.state == .held { return .held }
            guard saved.work.state == .running else { return .unavailable }
            _ = try Store.interruptRunning(saved, proof: proof, container: container, scope: scope)
            return .held
        } catch { return .unavailable }
    }

    private func dispatchValidation(_ claim: Store.Claim, proof: ObservationAudioPreparation.Verified,
                                    container: ModelContainer, scope: ObservationAudioExecutionOwner.Scope) -> Validate {
        {
            try requireDispatch(scope)
            try Store.validate(claim, proof: proof, container: container, isCurrent: scope.mayDispatch)
        }
    }
    private func settlementValidation(_ scope: ObservationAudioExecutionOwner.Scope) -> Validate {
        { guard scope.maySettleKnownReceipt() else { throw MerianError.invalidResponse } }
    }
    private func requireDispatch(_ scope: ObservationAudioExecutionOwner.Scope) throws {
        try Task.checkCancellation()
        guard scope.mayDispatch() else { throw MerianError.invalidResponse }
    }
}

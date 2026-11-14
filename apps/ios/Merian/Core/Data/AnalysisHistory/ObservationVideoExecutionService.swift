import Foundation
import SwiftData

/// One explicit retained operation. Consumed work has only exact result recovery authority.
@MainActor
struct ObservationVideoExecutionService {
    typealias Store = ObservationVideoExecutionStore
    typealias Validate = @MainActor @Sendable () throws -> Void
    typealias Cleanup = @MainActor (ObservationReanalysisErasureReceipt) async -> Void
    enum Outcome: Equatable { case completed, held, unavailable }
    struct Dependencies {
        let authorize: (UUID, @escaping Validate) async throws -> IdentificationDispatchAuthorization
        let analyze: (Store.DispatchPermit, IdentificationDispatchAuthorization, @escaping Validate, @escaping Validate) async throws -> ObservationAnalysisReceipt
        let outcome: (Store.Snapshot, @escaping Validate, @escaping Validate) async throws -> Data?
    }
    let dependencies: Dependencies
    var consumeSave: (ModelContext) throws -> Void = { try $0.save() }

    func run(_ entry: Store.Snapshot, proof: ObservationVideoPreparation.Verified,
             container: ModelContainer, scope: ObservationVideoExecutionOwner.Scope, cleanup: Cleanup) async -> Outcome {
        guard scope.matchesEntry(entry, container: ObjectIdentifier(container)) else { return .unavailable }
        do {
            try requireDispatch(scope)
            guard try current(proof, container, scope) == entry else { return .unavailable }
            if entry.work.consumed {
                return try await recover(entry, proof, container, scope, cleanup)
            }
            guard entry.work.phase == .idle else { return interrupt(proof, container, scope) }
            let claim = try Store.claim(entry, proof: proof, container: container,
                isCurrent: scope.mayDispatch, attemptID: scope.attemptID)
            let validate: Validate = {
                try requireDispatch(scope)
                guard try current(proof, container, scope) == claim.snapshot else { throw MerianError.invalidResponse }
            }
            try validate()
            let authorization = try await dependencies.authorize(entry.work.preparation.identity.ownerID, validate)
            try validate()
            let permit = try Store.consume(claim, proof: proof, authorization: authorization,
                container: container, isCurrent: scope.mayDispatch, save: consumeSave)
            let before: Validate = {
                try requireDispatch(scope)
                try Store.validateDispatch(permit, proof: proof, container: container, isCurrent: scope.mayDispatch)
            }
            try before()
            let reply = try await dependencies.analyze(permit, authorization, before, settlement(scope))
            try settlement(scope)()
            let identity = entry.work.preparation.identity
            guard reply.observationID == identity.observationID, reply.analysisID == identity.analysisID,
                  reply.state == .complete else { return interrupt(proof, container, scope) }
            return try await recover(permit.snapshot, proof, container, scope, cleanup)
        } catch { return interrupt(proof, container, scope) }
    }

    private func recover(_ expected: Store.Snapshot, _ proof: ObservationVideoPreparation.Verified,
                         _ container: ModelContainer, _ scope: ObservationVideoExecutionOwner.Scope,
                         _ cleanup: Cleanup) async throws -> Outcome {
        guard expected.work.consumed else { throw MerianError.invalidResponse }
        // A complete state receipt has no result. Cancellation cannot start a fresh recovery read.
        let before: Validate = {
            try requireDispatch(scope)
            guard try current(proof, container, scope) == expected else { throw MerianError.invalidResponse }
        }
        try before()
        let bytes = try await dependencies.outcome(expected, before, settlement(scope))
        try settlement(scope)()
        guard let bytes else { return interrupt(proof, container, scope) }
        let receipt = try Store.complete(expected, resultBytes: bytes, proof: proof, container: container,
            isCurrent: scope.maySettleKnownReceipt)
        await cleanup(receipt)
        return .completed
    }

    private func current(_ proof: ObservationVideoPreparation.Verified, _ container: ModelContainer,
                         _ scope: ObservationVideoExecutionOwner.Scope) throws -> Store.Snapshot {
        if let saved = try? Store.readForInterruption(proof: proof, container: container, scope: scope) { return saved }
        let saved = try Store.readSyncedForSettlement(proof: proof, container: container, isCurrent: scope.maySettleKnownReceipt)
        guard scope.permitsInterruption(saved, container: ObjectIdentifier(container)) else { throw MerianError.invalidResponse }
        return saved
    }
    private func interrupt(_ proof: ObservationVideoPreparation.Verified, _ container: ModelContainer,
                           _ scope: ObservationVideoExecutionOwner.Scope) -> Outcome {
        do {
            let saved = try Store.readForInterruption(proof: proof, container: container, scope: scope)
            if saved.work.phase == .held { return .held }
            guard saved.work.phase == .running else { return .unavailable }
            _ = try Store.interruptRunning(saved, proof: proof, container: container, scope: scope)
            return .held
        } catch { return .unavailable }
    }
    private func settlement(_ scope: ObservationVideoExecutionOwner.Scope) -> Validate {
        { guard scope.maySettleKnownReceipt() else { throw MerianError.invalidResponse } }
    }
    private func requireDispatch(_ scope: ObservationVideoExecutionOwner.Scope) throws {
        try Task.checkCancellation()
        guard scope.mayDispatch() else { throw MerianError.invalidResponse }
    }
}

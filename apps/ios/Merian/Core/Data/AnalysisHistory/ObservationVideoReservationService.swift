import Foundation
import SwiftData

/// One initial saved video reservation attempt. Uncertain work has no dispatch recovery here.
@MainActor
struct ObservationVideoReservationService {
    typealias Store = ObservationVideoSourceReservationStore
    typealias Validate = @MainActor @Sendable () throws -> Void
    enum Outcome: Equatable { case observed, held, unavailable }
    let verifyFiles: (ObservationVideoPreparation, @escaping Validate) async throws -> Void
    let reserve: (ObservationVideoSourceReservationRequest, UUID, @escaping Validate, @escaping Validate) async throws -> ObservationVideoSourceReservationReply
    var claimSave: (ModelContext) throws -> Void = { try $0.save() }
    var settlementSave: (ModelContext) throws -> Void = { try $0.save() }

    static func live(files: ObservationReanalysisFileStore, transport: ObservationSourceReservationTransport) -> Self {
        .init(verifyFiles: { preparation, validate in
            _ = try await files.readVideo(preparation: preparation, validateBeforeRead: validate, validateBeforeReturn: validate)
        }, reserve: { try await transport.reserve($0, ownerID: $1, validateAttempt: $2, validateResponse: $3) })
    }

    func run(_ entry: Store.Snapshot, proof: ObservationVideoPreparation.Verified,
             container: ModelContainer, scope: ObservationVideoReservationOwner.Scope) async -> Outcome {
        guard scope.matchesEntry(entry, container: ObjectIdentifier(container)) else { return .unavailable }
        let claim: Store.Claim
        do {
            try Task.checkCancellation()
            guard scope.mayDispatch() else { return .unavailable }
            claim = try Store.claim(entry, proof: proof, container: container, isCurrent: scope.mayDispatch, save: claimSave)
        } catch { return .unavailable }
        let before: Validate = {
            try Task.checkCancellation()
            guard scope.mayDispatch() else { throw CancellationError() }
            try Store.validate(claim, proof: proof, container: container, isCurrent: scope.mayDispatch)
        }
        let settlement: Validate = {
            guard scope.maySettleKnownReceipt() else { throw ObservationHistoryError.accountChanged }
        }
        let answer: ObservationVideoReservationSettlement
        do {
            try before()
            try await verifyFiles(entry.work.preparation, before)
            try before()
            answer = .reply(try await reserve(entry.work.request, entry.work.preparation.identity.ownerID, before, settlement))
        } catch let conflict as ObservationVideoSourceReservationConflict {
            answer = .conflict(conflict)
        } catch {
            // Unknown failure can hold only this attempt. Cancellation may leave running intact.
            do {
                _ = try Store.hold(claim, proof: proof, container: container, isCurrent: scope.mayDispatch)
                return .held
            } catch { return .unavailable }
        }
        // Persistence errors never turn a known answer into an unknown network failure.
        do {
            try settlement()
            _ = try Store.settle(claim, settlement: answer, proof: proof, container: container,
                isCurrent: scope.maySettleKnownReceipt, save: settlementSave)
            switch answer { case .reply: return .observed; case .conflict: return .held }
        } catch { return .unavailable }
    }
}

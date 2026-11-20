import Foundation
import SwiftData

/// One explicit source-reservation attempt. No upload, funding, inference or automatic recovery.
@MainActor
struct ObservationSourceReservationService {
    typealias Store = ObservationSourceReservationStore
    typealias Validate = @MainActor @Sendable () throws -> Void
    enum Outcome: Equatable { case observed, held, unavailable }
    let reserve: (ObservationSourceReservationRequest, UUID, @escaping Validate, @escaping Validate) async throws -> ObservationSourceReservationReply
    var claimSave: (ModelContext) throws -> Void = { try $0.save() }

    static func live(transport: ObservationSourceReservationTransport) -> Self {
        .init(reserve: { try await transport.reserve($0, ownerID: $1, validateAttempt: $2, validateResponse: $3) })
    }

    func run(_ entry: Store.Snapshot, admission: Store.Admission, proof: Store.Proof,
             container: ModelContainer, scope: ObservationSourceReservationOwner.Scope) async -> Outcome {
        guard scope.matchesEntry(entry, admission: admission, container: ObjectIdentifier(container)) else { return .unavailable }
        let claim: Store.Claim
        do {
            try Task.checkCancellation()
            guard scope.mayDispatch() else { return .unavailable }
            claim = try Store.claim(entry, admission: admission, proof: proof, container: container,
                isCurrent: scope.mayDispatch, save: claimSave)
        } catch { return .unavailable }
        let before: Validate = {
            try Task.checkCancellation()
            guard scope.mayDispatch() else { throw CancellationError() }
            try Store.validate(claim, proof: proof, container: container, isCurrent: scope.mayDispatch)
        }
        let settlement: Validate = {
            guard scope.maySettleKnownReceipt() else { throw ObservationHistoryError.accountChanged }
        }
        do {
            try before()
            let reply = try await reserve(entry.work.request, entry.identity.ownerID, before, settlement)
            try settlement()
            _ = try Store.settle(claim, reply: reply, proof: proof, container: container, isCurrent: scope.maySettleKnownReceipt)
            return .observed
        } catch {
            // An exact typed conflict settles despite dispatch cancellation. Unknown cancellation
            // may leave the original running claim. Only a later explicit action,
            // after this retained task exits, can claim the exact candidate again.
            do {
                _ = try Store.hold(claim, proof: proof, container: container, isCurrent: scope.maySettleKnownReceipt,
                    conflict: error as? ObservationSourceReservationConflict)
                return .held
            } catch { return .unavailable }
        }
    }
}

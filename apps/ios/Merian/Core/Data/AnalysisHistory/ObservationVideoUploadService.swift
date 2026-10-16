import Foundation
import SwiftData

/// Explicit bounded cohort delivery. Upload readiness does not authorize local erasure or inference.
@MainActor
struct ObservationVideoUploadService {
    typealias Store = ObservationVideoUploadLifecycleStore
    typealias Validate = @MainActor @Sendable () throws -> Void
    enum Outcome: Equatable { case ready, held, unavailable }
    let prepare: (ObservationVideoUploadLifecycle, UUID, @escaping Validate) async throws -> ObservationVideoEvidenceWireRequest
    let upload: (ObservationVideoEvidenceWireRequest, UUID, ObservationVideoEvidenceReceipt?, @escaping Validate, @escaping Validate) async throws -> ObservationVideoEvidenceReceipt
    var claimSave: (ModelContext) throws -> Void = { try $0.save() }
    var settlementSave: (ModelContext) throws -> Void = { try $0.save() }

    static func live(files: ObservationReanalysisFileStore, transport: ObservationVideoEvidenceTransport) -> Self {
        .init(prepare: { work, mediaID, validate in
            let saved = try await files.readVideo(preparation: work.staged.reservation.preparation,
                validateBeforeRead: validate, validateBeforeReturn: validate)
            try validate()
            guard let item = saved.first(where: { $0.artifact.mediaID == mediaID }) else { throw MerianError.invalidResponse }
            let task = Task.detached(priority: .utility) {
                try ObservationVideoEvidenceWireRequest(candidate: work.staged.reservation.request, mediaID: mediaID, bytes: item.bytes)
            }
            let wire = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            try validate()
            return wire
        }, upload: { try await transport.upload($0, ownerID: $1, previous: $2, validateAttempt: $3, validateResponse: $4) })
    }

    func run(_ entry: Store.Snapshot, proof: ObservationVideoPreparation.Verified,
             container: ModelContainer, scope: ObservationVideoUploadOwner.Scope) async -> Outcome {
        guard scope.matchesEntry(entry, container: ObjectIdentifier(container)) else { return .unavailable }
        var current = entry
        // Each accepted receipt makes the target ready, so at most the original item count can dispatch.
        for _ in entry.work.staged.request.inventory.items {
            let claim: Store.Claim
            do {
                try Task.checkCancellation()
                guard scope.mayDispatch() else { return .held }
                claim = try Store.claim(current, proof: proof, container: container, isCurrent: scope.mayDispatch, save: claimSave)
            } catch { return .unavailable }
            let before: Validate = {
                try Task.checkCancellation()
                guard scope.mayDispatch() else { throw CancellationError() }
                try Store.validate(claim, proof: proof, container: container, isCurrent: scope.mayDispatch)
            }
            let settlement: Validate = {
                guard scope.maySettleKnownReceipt() else { throw ObservationHistoryError.accountChanged }
            }
            let receipt: ObservationVideoEvidenceReceipt
            do {
                try before()
                guard let attempt = claim.snapshot.work.attempts.last else { throw MerianError.invalidResponse }
                let wire = try await prepare(claim.snapshot.work, attempt.mediaID, before)
                try before()
                guard wire.candidate == current.work.staged.reservation.request,
                      wire.request == current.work.staged.request, wire.mediaID == attempt.mediaID else { throw MerianError.invalidResponse }
                receipt = try await upload(wire, proof.preparation.identity.ownerID, current.work.receipt, before, settlement)
            } catch {
                do {
                    _ = try Store.hold(claim, proof: proof, container: container, isCurrent: scope.mayDispatch)
                    return .held
                } catch { return .unavailable }
            }
            // A failed known-result save never falls into the unknown network path.
            do {
                try settlement()
                current = try Store.settle(claim, receipt: receipt, proof: proof, container: container,
                    isCurrent: scope.maySettleKnownReceipt, save: settlementSave)
            } catch { return .unavailable }
            if current.work.receipt?.state == .ready { return .ready }
            guard scope.mayDispatch(), !Task.isCancelled else { return .held }
        }
        return .unavailable
    }
}

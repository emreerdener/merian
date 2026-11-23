import Foundation
import SwiftData

/// Advances one explicit candidate using the existing reservation and upload account scopes.
/// Only normal, durably observed returns may hand off; a throwing save never falls through.
@MainActor
struct ObservationCompositionSubmissionService {
    typealias Validate = ObservationCompositionUploadService.Validate
    let reservation: ObservationCompositionReservationService
    let upload: ObservationCompositionUploadService
    let authorize: (UUID, @escaping Validate) async throws -> IdentificationDispatchAuthorization
    var uploadStageSave: (ModelContext) throws -> Void = { try $0.save() }
    var executionStageSave: (ModelContext) throws -> Void = { try $0.save() }

    func reserve(_ entry: CompositionSourceReservationStore.Snapshot,
                 proof: ObservationCompositionPreparation.Verified, container: ModelContainer,
                 scope: ObservationCompositionReservationOwner.Scope) async -> CompositionUploadLifecycleStore.Snapshot? {
        guard await reservation.run(entry, proof: proof, container: container, scope: scope) == .observed else { return nil }
        do {
            try Task.checkCancellation()
            guard scope.mayDispatch() else { return nil }
            let saved = try CompositionSourceReservationStore.read(proof: proof, container: container, isCurrent: scope.mayDispatch)
            guard saved.work.request == entry.work.request, saved.work.preparation == entry.work.preparation,
                  saved.work.phase == .observed, saved.work.reply?.state == .reserved else { return nil }
            _ = try ObservationCompositionUploadStore.stage(saved, proof: proof, container: container,
                isCurrent: scope.mayDispatch, save: uploadStageSave)
            return try CompositionUploadLifecycleStore.read(proof: proof, container: container, isCurrent: scope.mayDispatch)
        } catch { return nil }
    }

    func deliver(_ entry: CompositionUploadLifecycleStore.Snapshot,
                 proof: ObservationCompositionPreparation.Verified, container: ModelContainer,
                 scope: ObservationCompositionUploadOwner.Scope) async -> ObservationCompositionExecutionStore.Snapshot? {
        guard scope.matchesEntry(entry, container: ObjectIdentifier(container)) else { return nil }
        do {
            try Task.checkCancellation()
            guard scope.mayDispatch(),
                  try CompositionUploadLifecycleStore.read(proof: proof, container: container, isCurrent: scope.mayDispatch) == entry else { return nil }
            // A later explicit action may bind an already-ready upload without uploading again.
            if entry.work.receipt?.state != .ready {
                guard await upload.run(entry, proof: proof, container: container, scope: scope) == .ready else { return nil }
            }
            try Task.checkCancellation()
            guard scope.mayDispatch() else { return nil }
            let ready = try CompositionUploadLifecycleStore.read(proof: proof, container: container, isCurrent: scope.mayDispatch)
            guard ready.work.stagedData == entry.work.stagedData, ready.work.receipt?.state == .ready else { return nil }
            let validate: Validate = {
                try Task.checkCancellation()
                guard scope.mayDispatch(),
                      try CompositionUploadLifecycleStore.read(proof: proof, container: container, isCurrent: scope.mayDispatch) == ready else {
                    throw ObservationHistoryError.accountChanged
                }
            }
            try validate()
            let authorization = try await authorize(proof.preparation.identity.ownerID, validate)
            try validate()
            return try ObservationCompositionExecutionStore.stage(ready, proof: proof, authorization: authorization,
                container: container, isCurrent: scope.mayDispatch, save: executionStageSave)
        } catch { return nil }
    }
}

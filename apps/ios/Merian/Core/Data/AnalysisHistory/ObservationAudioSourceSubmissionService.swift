import Foundation
import SwiftData

/// Reservation and explicit binding run inside the existing retained source owner.
/// A returned snapshot permits the queue handoff, never provider execution by itself.
@MainActor
struct ObservationAudioSourceSubmissionService {
    typealias Store = ObservationSourceReservationStore
    typealias Validate = ObservationSourceReservationService.Validate
    let source: ObservationSourceReservationService
    let authorize: @MainActor @Sendable (UUID, @escaping Validate) async throws -> IdentificationDispatchAuthorization
    var bindingSave: (ModelContext) throws -> Void = { try $0.save() }

    static func live(client: MerianNetworkClient) -> Self {
        .init(source: .live(transport: client.sourceReservationTransport()), authorize: { owner, validate in
            try await client.prepareBoundObservationReanalysisAuthorization(processor: .gemini,
                expectedAuthUserID: owner, validateAttempt: validate)
        })
    }

    /// The caller supplies a validated stored snapshot. Reserved recovery is binding-only.
    static func admission(for snapshot: Store.Snapshot) -> Store.Admission? {
        guard case .audio = snapshot.work.preparation else { return nil }
        switch snapshot.work.state {
        case .staged: return .initial
        case .running, .unknown, .observed: return .explicitRecovery
        case .conflict: return nil
        }
    }

    func run(_ entry: Store.Snapshot, admission: Store.Admission,
             proof: ObservationAudioPreparation.Verified, container: ModelContainer,
             scope: ObservationSourceReservationOwner.Scope) async -> ObservationAudioExecutionStore.Snapshot? {
        do {
            guard Self.admission(for: entry) == admission,
                  scope.matchesEntry(entry, admission: admission, container: ObjectIdentifier(container)),
                  entry.work.preparation == .audio(proof.preparation) else { return nil }
            try Task.checkCancellation()
            guard scope.mayDispatch(), try Store.read(entry.identity, container: container, isCurrent: scope.mayDispatch) == entry else { return nil }
            var saved = entry
            if entry.work.reply?.state != .reserved {
                guard await source.run(entry, admission: admission, proof: .audio(proof), container: container, scope: scope) == .observed else { return nil }
                try Task.checkCancellation()
                guard scope.mayDispatch() else { return nil }
                saved = try Store.read(entry.identity, container: container, isCurrent: scope.mayDispatch)
                guard saved.work.generation == entry.work.generation + 1,
                      saved.work.request == entry.work.request, saved.work.preparation == entry.work.preparation else { return nil }
            }
            guard saved.work.state == .observed, saved.work.reply?.state == .reserved else { return nil }
            let reserved = saved
            let validate: Validate = {
                try Task.checkCancellation()
                guard scope.mayDispatch(), try Store.read(entry.identity, container: container, isCurrent: scope.mayDispatch) == reserved else {
                    throw ObservationHistoryError.accountChanged
                }
                try proof.validate(container: container)
            }
            try validate()
            let candidate = try await DetachedWork.value(category: .inferenceRequestPreparation) {
                try ObservationAudioExecutionIntent(reserved: reserved.work)
            }
            try validate()
            let authorization = try await authorize(entry.identity.ownerID, validate)
            try validate()
            let bound = try ObservationAudioExecutionStore.bindReserved(candidate, source: reserved, proof: proof,
                authorization: authorization, container: container, isCurrent: scope.mayDispatch, save: bindingSave)
            try Task.checkCancellation()
            guard scope.mayDispatch() else { return nil }
            return bound
        } catch {
            // Never reread a binding after a throwing save. A later explicit resume owns recovery.
            return nil
        }
    }
}

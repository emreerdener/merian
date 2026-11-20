import Foundation
import SwiftData

/// Explicit saved-child continuation only. Reading or reopening never repeats uncertain work.
@MainActor
struct ObservationVideoResumeSubmission {
    enum Route: Sendable {
        case reservation(ObservationVideoSourceReservationStore.Snapshot)
        case upload(ObservationVideoUploadLifecycleStore.Snapshot)
        case execution(ObservationVideoExecutionStore.Snapshot)
    }
    struct Ready: Sendable {
        let proof: ObservationVideoPreparation.Verified
        let route: Route
    }
    let producer: ObservationVideoPreparationProducer
    var reservationSave: @MainActor @Sendable (ModelContext) throws -> Void = { try $0.save() }
    var uploadSave: @MainActor @Sendable (ModelContext) throws -> Void = { try $0.save() }

    func resume(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer,
                isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> Ready? {
        let reader = ObservationVideoResumeReader(ownership: producer.ownership, account: producer.account)
        var saved = try await reader.read(identity, container: container, isCurrent: isCurrent)
        if case .preparation = saved.state {
            // Complete-cohort recovery only. Missing bytes cannot create new media or a new child.
            _ = try await producer.prepare(saved.proof.preparation, source: saved.source, cohort: nil,
                container: container, isCurrent: isCurrent)
            saved = try await reader.read(identity, container: container, isCurrent: isCurrent)
        }
        let original = saved
        let result: Ready? = try await producer.ownership.perform(identity) { tokenCurrent in
            let lease = try producer.account.begin(identity.ownerID)
            defer { producer.account.finish(lease) }
            let current: @MainActor @Sendable () -> Bool = {
                tokenCurrent() && lease.session.userID == identity.ownerID && producer.account.isCurrent(lease) && isCurrent()
            }
            try ObservationVideoResumeStore.validate(original, container: container, isCurrent: current)
            let proof = original.proof
            switch original.state {
            case .preparation(.pending): return nil
            case .preparation(.ready):
                let request = try await DetachedWork.value(category: .inferenceRequestPreparation) {
                    try ObservationVideoSourceReservationRequest(video: proof.preparation.request)
                }
                try ObservationVideoResumeStore.validate(original, container: container, isCurrent: current)
                let snapshot = try ObservationVideoSourceReservationStore.stage(request, proof: proof,
                    container: container, isCurrent: current, save: reservationSave)
                return Ready(proof: proof, route: .reservation(snapshot))
            case let .reservation(snapshot):
                if snapshot.work.phase == .staged { return Ready(proof: proof, route: .reservation(snapshot)) }
                guard snapshot.work.phase == .observed, snapshot.work.reply?.state == .reserved else { return nil }
                _ = try ObservationVideoUploadStore.stage(snapshot, proof: proof, container: container,
                    isCurrent: current, save: uploadSave)
                let upload = try ObservationVideoUploadLifecycleStore.read(proof: proof, container: container, isCurrent: current)
                return Ready(proof: proof, route: .upload(upload))
            case let .upload(snapshot):
                guard snapshot.work.receipt?.state == .ready || snapshot.work.nextMediaID != nil else { return nil }
                return Ready(proof: proof, route: .upload(snapshot))
            case let .execution(snapshot):
                guard snapshot.work.phase == .idle || snapshot.work.consumed else { return nil }
                return Ready(proof: proof, route: .execution(snapshot))
            }
        }
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        if let result { try Self.validate(result, container: container, isCurrent: isCurrent) }
        return result
    }

    static func validate(_ ready: Ready, container: ModelContainer, isCurrent: () -> Bool) throws {
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        switch ready.route {
        case let .reservation(snapshot):
            guard snapshot.work.phase == .staged,
                  try ObservationVideoSourceReservationStore.read(proof: ready.proof, container: container,
                    isCurrent: isCurrent) == snapshot else { throw ObservationHistoryError.resultConflict }
        case let .upload(snapshot):
            guard snapshot.work.receipt?.state == .ready || snapshot.work.nextMediaID != nil,
                  try ObservationVideoUploadLifecycleStore.read(proof: ready.proof, container: container,
                    isCurrent: isCurrent) == snapshot else { throw ObservationHistoryError.resultConflict }
        case let .execution(snapshot):
            let current: ObservationVideoExecutionStore.Snapshot
            do { current = try ObservationVideoExecutionStore.read(proof: ready.proof, container: container, isCurrent: isCurrent) } catch ObservationReanalysisPersistence.IntegrityError.conflict {
                current = try ObservationVideoExecutionStore.readSyncedForSettlement(proof: ready.proof,
                    container: container, isCurrent: isCurrent)
            }
            guard current == snapshot, current.work.phase == .idle || current.work.consumed else {
                throw ObservationHistoryError.resultConflict
            }
        }
    }
}

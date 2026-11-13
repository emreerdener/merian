import Foundation
import SwiftData

/// Existing child only. Reading a phase never grants a claim, upload, execution or cleanup capability.
@MainActor
struct ObservationVideoResumeStore {
    enum State: Sendable {
        case preparation(ObservationVideoPreparation.Phase)
        case reservation(ObservationVideoSourceReservationStore.Snapshot)
        case upload(ObservationVideoUploadLifecycleStore.Snapshot)
        case execution(ObservationVideoExecutionStore.Snapshot)
    }
    enum Kind: Sendable { case preparation, reservation, upload, execution }
    struct Decoded: Sendable {
        let proof: ObservationVideoPreparation.Verified
        let kind: Kind
    }
    struct Saved: Sendable {
        let source: ObservationReanalysisSource
        let proof: ObservationVideoPreparation.Verified
        let state: State
        fileprivate let metadata: Data
        fileprivate let kind: Kind
    }
    typealias Verify = @MainActor @Sendable (Data, OfflineQueueWork.Reanalysis, ObservationReanalysisSource) async throws -> Decoded
    var verify: Verify = { data, identity, source in
        try await DetachedWork.value(category: .inferenceRequestPreparation) {
            try decode(data, identity: identity, source: source)
        }
    }

    func read(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer,
              isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> Saved {
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        let source = try ObservationReanalysisSource.captureForVideo(observationID: identity.observationID,
            analysisID: identity.sourceAnalysisID, ownerID: identity.ownerID, container: container)
        let original = try Self.metadata(identity, source: source, container: container, isCurrent: isCurrent)
        let decoded = try await verify(original, identity, source)
        let proof = decoded.proof
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        guard proof.preparation.identity == identity,
              try Self.metadata(identity, source: source, container: container, isCurrent: isCurrent) == original else {
            throw ObservationHistoryError.resultConflict
        }
        try proof.validate(container: container)
        let state = try Self.state(proof, kind: decoded.kind, container: container, isCurrent: isCurrent)
        return Saved(source: source, proof: proof, state: state, metadata: original, kind: decoded.kind)
    }

    static func validate(_ saved: Saved, container: ModelContainer, isCurrent: () -> Bool) throws {
        try Task.checkCancellation()
        guard try metadata(saved.proof.preparation.identity, source: saved.source,
            container: container, isCurrent: isCurrent) == saved.metadata else { throw ObservationHistoryError.resultConflict }
        try saved.proof.validate(container: container)
        _ = try state(saved.proof, kind: saved.kind, container: container, isCurrent: isCurrent)
    }

    private static func metadata(_ identity: OfflineQueueWork.Reanalysis, source: ObservationReanalysisSource,
                                 container: ModelContainer, isCurrent: () -> Bool) throws -> Data {
        try ObservationReanalysisPersistence.transaction(identity, container: container, isCurrent: isCurrent,
            save: { _ in throw ObservationHistoryError.resultConflict }) { context in
                try source.validate(context: context)
                guard let (_, job) = try ObservationReanalysisPersistence.pair(identity, context: context),
                      let text = job.metadataJSON, !text.isEmpty,
                      text.utf8.count <= ObservationVideoExecutionWork.maximumBytes else { throw ObservationHistoryError.unavailable }
                return Data(text.utf8)
            }
    }

    nonisolated static func decode(_ data: Data, identity: OfflineQueueWork.Reanalysis,
                                   source: ObservationReanalysisSource) throws -> Decoded {
        guard !data.isEmpty, data.count <= ObservationVideoExecutionWork.maximumBytes,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MerianError.invalidResponse }
        let preparation: ObservationVideoPreparation, kind: Kind
        switch object["kind"] as? String {
        case "video_preparation": kind = .preparation; preparation = try ObservationVideoPreparation.decode(data).preparation
        case ObservationVideoSourceReservationWork.kind: kind = .reservation; preparation = try ObservationVideoSourceReservationWork.decode(data).preparation
        case ObservationVideoUploadWork.kind: kind = .upload; preparation = try ObservationVideoUploadLifecycle.decode(data).staged.reservation.preparation
        case ObservationVideoExecutionWork.kind: kind = .execution; preparation = try ObservationVideoExecutionWork.decode(data).preparation
        default: throw MerianError.invalidResponse
        }
        guard preparation.identity == identity else { throw ObservationHistoryError.resultConflict }
        return try Decoded(proof: preparation.verified(source: source), kind: kind)
    }

    private static func state(_ proof: ObservationVideoPreparation.Verified, kind: Kind,
                              container: ModelContainer, isCurrent: () -> Bool) throws -> State {
        // Route only by the saved envelope; every phase still uses its existing strict store.
        switch kind {
        case .preparation:
            return .preparation(try ObservationVideoPreparationStore.read(proof, container: container, isCurrent: isCurrent))
        case .reservation:
            return .reservation(try ObservationVideoSourceReservationStore.read(proof: proof, container: container, isCurrent: isCurrent))
        case .upload:
            return .upload(try ObservationVideoUploadLifecycleStore.read(proof: proof, container: container, isCurrent: isCurrent))
        case .execution:
            do {
                return .execution(try ObservationVideoExecutionStore.read(proof: proof, container: container, isCurrent: isCurrent))
            } catch ObservationReanalysisPersistence.IntegrityError.conflict {
                // A synced exact result may coexist with consumed work until receipt-bound completion.
                return .execution(try ObservationVideoExecutionStore.readSyncedForSettlement(proof: proof,
                    container: container, isCurrent: isCurrent))
            }
        }
    }
}

/// Reuses the preparation slot and account lease. Cancellation retains both through actual reader exit.
@MainActor
struct ObservationVideoResumeReader {
    let ownership: ObservationReanalysisPreparationOwner
    let account: ObservationHistoryCloudClient
    var store = ObservationVideoResumeStore()

    func read(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer,
              isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationVideoResumeStore.Saved {
        let saved = try await ownership.perform(identity) { tokenCurrent in
            let lease = try account.begin(identity.ownerID)
            defer { account.finish(lease) }
            guard lease.session.userID == identity.ownerID else { throw ObservationHistoryError.accountChanged }
            return try await store.read(identity, container: container, isCurrent: {
                tokenCurrent() && account.isCurrent(lease) && isCurrent()
            })
        }
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        try ObservationVideoResumeStore.validate(saved, container: container, isCurrent: isCurrent)
        return saved
    }
}

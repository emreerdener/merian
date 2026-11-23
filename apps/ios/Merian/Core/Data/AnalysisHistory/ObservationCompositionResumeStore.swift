import Foundation
import SwiftData

/// Existing child only. Reading a phase never grants a claim, upload, execution or cleanup capability.
@MainActor
struct ObservationCompositionResumeStore {
    enum State: Sendable {
        case preparation(ObservationCompositionPreparation.Phase)
        case reservation(CompositionSourceReservationStore.Snapshot)
        case upload(CompositionUploadLifecycleStore.Snapshot)
        case execution(ObservationCompositionExecutionStore.Snapshot)
    }
    enum Kind: Sendable { case preparation, reservation, upload, execution }
    struct Decoded: Sendable {
        let proof: ObservationCompositionPreparation.Verified
        let kind: Kind
    }
    struct Saved: Sendable {
        let source: ObservationReanalysisSource
        let proof: ObservationCompositionPreparation.Verified
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
        let source = try ObservationReanalysisSource.capture(observationID: identity.observationID,
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

    /// Bounded local projection only; every action reopens through the leased asynchronous reader.
    static func status(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer,
                       isCurrent: () -> Bool) throws -> ObservationReanalysisOperationStatus.Summary {
        let source = try ObservationReanalysisSource.capture(observationID: identity.observationID,
            analysisID: identity.sourceAnalysisID, ownerID: identity.ownerID, container: container)
        let bytes = try metadata(identity, source: source, container: container, isCurrent: isCurrent)
        let decoded = try decode(bytes, identity: identity, source: source)
        let saved = try state(decoded.proof, kind: decoded.kind, container: container, isCurrent: isCurrent)
        var row = ObservationReanalysisOperationStatus.Summary(id: identity.analysisID,
            sourceAnalysisID: identity.sourceAnalysisID, phase: .reconciliationRequired, isComposition: true)
        switch saved {
        case .preparation:
            row = .init(id: identity.analysisID, sourceAnalysisID: identity.sourceAnalysisID,
                phase: .preparingEvidence, isComposition: true, canContinue: true)
        case let .reservation(snapshot):
            row.canContinue = snapshot.work.phase == .staged || (snapshot.work.phase == .observed && snapshot.work.reply?.state == .reserved)
        case let .upload(snapshot):
            row.canContinue = snapshot.work.receipt?.state == .ready || snapshot.work.nextMediaID != nil
        case let .execution(snapshot):
            row.canContinue = snapshot.work.phase == .idle
            row.canCheckOutcome = snapshot.work.consumed
        }
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        return row
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
                      text.utf8.count <= ObservationCompositionExecutionWork.maximumBytes else { throw ObservationHistoryError.unavailable }
                return Data(text.utf8)
            }
    }

    nonisolated static func decode(_ data: Data, identity: OfflineQueueWork.Reanalysis,
                                   source: ObservationReanalysisSource) throws -> Decoded {
        guard !data.isEmpty, data.count <= ObservationCompositionExecutionWork.maximumBytes,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MerianError.invalidResponse }
        let preparation: ObservationCompositionPreparation, kind: Kind
        switch object["kind"] as? String {
        case "composition_preparation": kind = .preparation; preparation = try ObservationCompositionPreparation.decode(data).preparation
        case CompositionSourceReservationWork.kind: kind = .reservation; preparation = try CompositionSourceReservationWork.decode(data).preparation
        case ObservationCompositionUploadWork.kind: kind = .upload; preparation = try ObservationCompositionUploadLifecycle.decode(data).staged.reservation.preparation
        case ObservationCompositionExecutionWork.kind: kind = .execution; preparation = try ObservationCompositionExecutionWork.decode(data).preparation
        default: throw MerianError.invalidResponse
        }
        guard preparation.identity == identity else { throw ObservationHistoryError.resultConflict }
        return try Decoded(proof: preparation.verified(source: source), kind: kind)
    }

    private static func state(_ proof: ObservationCompositionPreparation.Verified, kind: Kind,
                              container: ModelContainer, isCurrent: () -> Bool) throws -> State {
        // Route only by the saved envelope; every phase still uses its existing strict store.
        switch kind {
        case .preparation:
            return .preparation(try ObservationCompositionPreparationStore.read(proof, container: container, isCurrent: isCurrent))
        case .reservation:
            return .reservation(try CompositionSourceReservationStore.read(proof: proof, container: container, isCurrent: isCurrent))
        case .upload:
            return .upload(try CompositionUploadLifecycleStore.read(proof: proof, container: container, isCurrent: isCurrent))
        case .execution:
            do {
                return .execution(try ObservationCompositionExecutionStore.read(proof: proof, container: container, isCurrent: isCurrent))
            } catch ObservationReanalysisPersistence.IntegrityError.conflict {
                // A synced exact result may coexist with consumed work until receipt-bound completion.
                return .execution(try ObservationCompositionExecutionStore.readSyncedForSettlement(proof: proof,
                    container: container, isCurrent: isCurrent))
            }
        }
    }
}

/// Reuses the preparation slot and account lease. Cancellation retains both through actual reader exit.
@MainActor
struct ObservationCompositionResumeReader {
    let ownership: ObservationReanalysisPreparationOwner
    let account: ObservationHistoryCloudClient
    var store = ObservationCompositionResumeStore()

    func read(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer,
              isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationCompositionResumeStore.Saved {
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
        try ObservationCompositionResumeStore.validate(saved, container: container, isCurrent: isCurrent)
        return saved
    }
}

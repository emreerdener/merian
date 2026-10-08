import Foundation
import SwiftData

/// Read-only exact-child recovery. No discovery, files, consent, claim or provider capability.
@MainActor
enum ObservationAudioResumeStore {
    enum State: Sendable { case preparation(ObservationAudioPreparation.Phase), bound(ObservationAudioExecutionStore.Snapshot) }
    struct Saved: Sendable {
        let source: ObservationReanalysisSource
        let proof: ObservationAudioPreparation.Verified
        let state: State
    }

    static func read(_ identity: OfflineQueueWork.Reanalysis, container: ModelContainer,
                     isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> Saved {
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        // capture owns its own transaction; never nest the shared persistence lock.
        let source = try ObservationReanalysisSource.captureForAudio(observationID: identity.observationID,
            analysisID: identity.sourceAnalysisID, ownerID: identity.ownerID, container: container)
        let metadata = try ObservationReanalysisPersistence.transaction(identity, container: container, isCurrent: isCurrent,
            save: { _ in throw ObservationHistoryError.resultConflict }) { context in
                try source.validate(context: context)
                guard let (_, job) = try ObservationReanalysisPersistence.pair(identity, context: context),
                      let text = job.metadataJSON, text.utf8.count <= 1_400_000 else { throw ObservationHistoryError.unavailable }
                return Data(text.utf8)
            }
        let proof = try await DetachedWork.value(category: .inferenceRequestPreparation) {
            try decode(metadata, identity: identity, source: source)
        }
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        // Fresh shared strict admission validation catches phase/claim changes, deletion and malformed rows.
        let state: State
        switch try ObservationAudioExecutionStore.admissionState(proof, container: container, isCurrent: isCurrent) {
        case let .preparation(phase): state = .preparation(phase)
        case let .bound(snapshot): state = .bound(snapshot)
        case .unprepared: throw ObservationHistoryError.unavailable
        }
        return Saved(source: source, proof: proof, state: state)
    }

    nonisolated private static func decode(_ data: Data, identity: OfflineQueueWork.Reanalysis,
                                           source: ObservationReanalysisSource) throws -> ObservationAudioPreparation.Verified {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MerianError.invalidResponse }
        let preparation: ObservationAudioPreparation
        switch object["kind"] as? String {
        case "audio_preparation": preparation = try ObservationAudioPreparation.decode(data).preparation
        case "audio_execution":
            let work = try ObservationAudioExecutionIntent.Work.decode(data)
            preparation = try ObservationAudioPreparation(identity: identity, evidence: work.intent.request.evidence, source: source, action: .submit)
            guard work.intent.matches(preparation) else { throw MerianError.invalidResponse }
        default: throw MerianError.invalidResponse
        }
        guard preparation.identity == identity, preparation.action == .submit else { throw MerianError.invalidResponse }
        return try preparation.verified(source: source)
    }
}

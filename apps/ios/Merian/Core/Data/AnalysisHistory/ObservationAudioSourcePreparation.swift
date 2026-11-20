import Foundation
import SwiftData

/// Explicit Capture preparation/staging. Saved source and execution records stay distinct.
@MainActor
struct ObservationAudioSourcePreparation {
    enum Ready: Equatable, Sendable {
        case source(ObservationSourceReservationStore.Snapshot)
        case execution(ObservationAudioExecutionStore.Snapshot)
    }
    private enum State { case prepare, ready(Ready) }
    let producer: ObservationAudioPreparationProducer

    func prepare(_ proof: ObservationAudioPreparation.Verified, source: ObservationReanalysisSource, bytes: Data,
                 container: ModelContainer, isCurrent: @escaping @MainActor @Sendable () -> Bool,
                 save: @escaping @MainActor @Sendable (ModelContext) throws -> Void = { try $0.save() }) async throws -> Ready {
        let existing: Ready? = try await retained(proof, container: container, isCurrent: isCurrent) { current in
            switch try state(proof, container: container, isCurrent: current) {
            case let .ready(saved): return saved
            case .prepare: return nil
            }
        }
        if let existing { return try validate(existing, proof: proof, container: container, isCurrent: isCurrent) }
        let phase = try await producer.prepare(proof.preparation, source: source, bytes: bytes,
            container: container, isCurrent: isCurrent)
        try Task.checkCancellation()
        guard isCurrent(), phase == .admissionPending else { throw ObservationHistoryError.unavailable }
        let saved: Ready = try await retained(proof, container: container, isCurrent: isCurrent) { current in
            // Recheck after file preparation: another explicit caller may have advanced the same child.
            if case let .ready(saved) = try state(proof, container: container, isCurrent: current) { return saved }
            let candidate = try await DetachedWork.value(category: .inferenceRequestPreparation) {
                try ObservationSourceReservationRequest(audio: ObservationAudioExecutionIntent(preparation: proof.preparation).request)
            }
            try Task.checkCancellation()
            guard current() else { throw ObservationHistoryError.accountChanged }
            return .source(try ObservationSourceReservationStore.stageAudio(request: candidate, proof: .audio(proof),
                container: container, isCurrent: current, save: save))
        }
        return try validate(saved, proof: proof, container: container, isCurrent: isCurrent)
    }

    private func retained<T: Sendable>(_ proof: ObservationAudioPreparation.Verified, container: ModelContainer,
                                       isCurrent: @escaping @MainActor @Sendable () -> Bool,
                                       operation: @escaping @MainActor @Sendable (@escaping @MainActor @Sendable () -> Bool) async throws -> T) async throws -> T {
        try await producer.ownership.perform(proof.preparation.identity) { tokenCurrent in
            let lease = try producer.account.begin(proof.preparation.identity.ownerID)
            defer { producer.account.finish(lease) }
            guard lease.session.userID == proof.preparation.identity.ownerID else { throw ObservationHistoryError.accountChanged }
            let current: @MainActor @Sendable () -> Bool = { tokenCurrent() && producer.account.isCurrent(lease) && isCurrent() }
            try Task.checkCancellation()
            guard current() else { throw ObservationHistoryError.accountChanged }
            try proof.validate(container: container)
            return try await operation(current)
        }
    }

    private func validate(_ expected: Ready, proof: ObservationAudioPreparation.Verified, container: ModelContainer,
                          isCurrent: @escaping @MainActor @Sendable () -> Bool) throws -> Ready {
        try Task.checkCancellation()
        guard isCurrent(), case let .ready(saved) = try state(proof, container: container, isCurrent: isCurrent),
              saved == expected else { throw ObservationHistoryError.resultConflict }
        return saved
    }

    /// Header chooses a strict reader only. A decode failure is never absence or legacy fallback.
    private func state(_ proof: ObservationAudioPreparation.Verified, container: ModelContainer,
                       isCurrent: @escaping @MainActor @Sendable () -> Bool) throws -> State {
        let isSource = try ObservationReanalysisPersistence.transaction(proof.preparation.identity, container: container,
            isCurrent: isCurrent, save: { _ in throw ObservationHistoryError.resultConflict }) { context in
                try proof.validate(context: context)
                guard let (_, job) = try ObservationReanalysisPersistence.pair(proof.preparation.identity, context: context) else { return false }
                guard let text = job.metadataJSON, text.utf8.count <= ObservationSourceReservationWork.maximumBytes,
                      let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { throw MerianError.invalidResponse }
                return object["phase"] as? String == "source_reservation"
            }
        if isSource {
            let saved = try ObservationSourceReservationStore.read(proof.preparation.identity, container: container, isCurrent: isCurrent)
            guard saved.work.preparation == .audio(proof.preparation) else { throw ObservationHistoryError.resultConflict }
            return .ready(.source(saved))
        }
        switch try ObservationAudioExecutionStore.admissionState(proof, container: container, isCurrent: isCurrent) {
        case let .bound(saved): return .ready(.execution(saved))
        case .unprepared, .preparation: return .prepare
        }
    }
}

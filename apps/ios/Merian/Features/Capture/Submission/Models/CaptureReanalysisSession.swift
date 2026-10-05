import Foundation
import SwiftData

/// One explicitly chosen historical source. No selection or current-scan fallback is available here.
@MainActor
final class CaptureReanalysisSession {
    let source: ObservationReanalysisSource
    let generation: UUID
    private(set) var plan: ObservationReanalysisPreparationPlan?
    private var isPreparing = false
    private var submittedCapture: CaptureSubmissionAdmissionSnapshot?

    init(source: ObservationReanalysisSource, generation: UUID) {
        self.source = source
        self.generation = generation
    }

    /// Freeze before the first asynchronous producer call. An ambiguous result cannot mint a successor.
    /// Once frozen, editing or discarding requires explicit durable reconciliation by the caller.
    func preparation(capture: StagedCapture, generation: UUID) throws -> ObservationReanalysisPreparationPlan {
        guard generation == self.generation else { throw ObservationHistoryError.accountChanged }
        let snapshot = CaptureSubmissionAdmissionSnapshot(capture)
        if let plan {
            guard submittedCapture == snapshot else { throw ObservationHistoryError.resultConflict }
            return plan
        }
        let prepared = try CaptureReanalysisPreparation.plan(source: source, capture: capture)
        submittedCapture = snapshot
        plan = prepared
        return prepared
    }

    /// Dedicated held-child submission; never invokes ordinary scan admission or complimentary funding.
    func stage(capture: StagedCapture, generation: UUID, container: ModelContainer,
               producer: ObservationReanalysisProducer,
               isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationReanalysisPersistence.DraftState {
        guard !isPreparing else { throw ObservationHistoryError.unavailable }
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        let plan = try preparation(capture: capture, generation: generation)
        isPreparing = true
        defer { isPreparing = false }
        let result = try await producer.stage(plan, container: container, isCurrent: isCurrent)
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        return result
    }

}

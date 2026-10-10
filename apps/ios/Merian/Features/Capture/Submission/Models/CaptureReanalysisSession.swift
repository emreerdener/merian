import Foundation
import SwiftData

/// One explicitly chosen historical source. No selection or current-scan fallback is available here.
@MainActor
final class CaptureReanalysisSession {
    let source: ObservationReanalysisSource
    let generation: UUID
    private(set) var plan: ObservationReanalysisPreparationPlan?
    private var isPreparing = false
    private(set) var isDiscarded = false
    private var submittedCapture: CaptureSubmissionAdmissionSnapshot?
    private var preparationAction: ObservationReanalysisPreparationIntent.Action?

    init(source: ObservationReanalysisSource, generation: UUID) {
        self.source = source
        self.generation = generation
    }

    /// Freeze before the first asynchronous producer call. An ambiguous result cannot mint a successor.
    /// Once frozen, editing or discarding requires explicit durable reconciliation by the caller.
    func preparation(capture: StagedCapture, generation: UUID) throws -> ObservationReanalysisPreparationPlan {
        guard !isDiscarded else { throw ObservationHistoryError.unavailable }
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
               action: ObservationReanalysisPreparationIntent.Action = .hold,
               isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationReanalysisPersistence.DraftState {
        guard !isPreparing else { throw ObservationHistoryError.unavailable }
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        let plan = try preparation(capture: capture, generation: generation)
        guard preparationAction == nil || preparationAction == action else { throw ObservationHistoryError.resultConflict }
        preparationAction = action
        isPreparing = true
        defer { isPreparing = false }
        let result = try await producer.stage(plan, container: container, action: action, isCurrent: isCurrent)
        try Task.checkCancellation()
        guard isCurrent() else { throw ObservationHistoryError.accountChanged }
        return result
    }

    /// UI may release this session only after durable retirement succeeds. Account teardown is separate.
    @discardableResult
    func discard(generation: UUID, container: ModelContainer, account: ObservationHistoryCloudClient,
                 isCurrent: @escaping @MainActor @Sendable () -> Bool) throws -> ObservationReanalysisErasureReceipt? {
        guard !isPreparing else { throw ObservationHistoryError.unavailable }
        guard generation == self.generation, isCurrent() else { throw ObservationHistoryError.accountChanged }
        let lease = try account.begin(source.ownerID)
        defer { account.finish(lease) }
        let current = { lease.session.userID == self.source.ownerID && account.isCurrent(lease) && isCurrent() }
        try Task.checkCancellation()
        guard current() else { throw ObservationHistoryError.accountChanged }
        guard let plan else { isDiscarded = true; return nil }
        let receipt = try ObservationReanalysisPersistence.discardPreparation(source: source, analysisID: plan.analysisID,
            container: container, isCurrent: current)
        // Keep the plan as a terminal identity; this session must never mint or stage another child.
        isDiscarded = true
        return receipt
    }

}

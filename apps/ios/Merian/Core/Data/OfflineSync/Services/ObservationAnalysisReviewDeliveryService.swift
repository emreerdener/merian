import Foundation
import Supabase
import SwiftData

/// One immutable operation per call; scheduling and foreground admission are separate owners.
@MainActor
struct ObservationAnalysisReviewDeliveryService {
    typealias Store = ObservationAnalysisReviewPersistence
    typealias Validator = @MainActor @Sendable () throws -> Void
    enum Outcome: Equatable { case completed, waiting, needsAttention, notDue }
    let cloud: ObservationHistoryCloudClient
    let submit: (ObservationAnalysisReviewRequest, UUID, @escaping Validator) async throws -> ObservationAnalysisReviewReceipt
    var now: () -> Date = Date.init
    var save: (ModelContext) throws -> Void = { try $0.save() }

    static func live(cloud: ObservationHistoryCloudClient, client: MerianNetworkClient) -> Self {
        Self(cloud: cloud, submit: { request, owner, validate in
            try await client.reviewObservationAnalysis(request, ownerID: owner, validateAttempt: validate)
        })
    }

    func deliver(_ intent: ObservationAnalysisReviewIntent, container: ModelContainer,
                 isCurrent: @escaping @MainActor @Sendable () -> Bool) async throws -> Outcome {
        try Task.checkCancellation()
        guard isCurrent() else { throw Store.IntegrityError.accountChanged }
        let lease = try cloud.begin(intent.ownerID)
        defer { cloud.finish(lease) }
        let current: @MainActor @Sendable () -> Bool = {
            !Task.isCancelled && isCurrent() && lease.session.userID == intent.ownerID && cloud.isCurrent(lease)
        }
        guard var claim = try Store.claim(intent, at: now(), container: container, isCurrent: current, save: save) else { return .notDue }
        if !claim.intent.hasReceipt {
            let dispatchClaim = claim
            let validate: Validator = {
                try Task.checkCancellation()
                try Store.requireDispatch(dispatchClaim, at: now(), container: container, isCurrent: current)
            }
            let receipt: ObservationAnalysisReviewReceipt
            do {
                try validate()
                // No current-state preflight: this exact operation may already have committed remotely.
                receipt = try await submit(intent.request, intent.ownerID, validate)
            } catch {
                return try deferFailure(error, claim: dispatchClaim, container: container, current: current)
            }
            try Task.checkCancellation()
            guard current() else { throw Store.IntegrityError.accountChanged }
            // Save failures escape without transport classification. The exact request remains recoverable.
            let received = try Store.acknowledge(receipt, claim: dispatchClaim, at: now(), container: container, isCurrent: current, save: save)
            // Acknowledgement invalidated dispatchClaim. Never use it for later failure writes.
            guard let receivedClaim = try Store.claim(received, at: now(), container: container, isCurrent: current, save: save) else { return .notDue }
            claim = receivedClaim
        }
        do {
            _ = try await ObservationAnalysisReviewReconciliation(cloud: cloud, now: now, save: save)
                .reconcile(claim, container: container, isCurrent: current)
            return .completed
        } catch {
            return try deferFailure(error, claim: claim, container: container, current: current)
        }
    }

    private func deferFailure(_ error: Error, claim: Store.Claim, container: ModelContainer,
                              current: () -> Bool) throws -> Outcome {
        try Task.checkCancellation()
        guard current() else { throw Store.IntegrityError.accountChanged }
        if error is CancellationError || error is SupabaseAuthTransitionError { throw error }
        let attention: Bool
        if let rpc = error as? PostgrestError {
            attention = ObservationAnalysisReviewDeliveryPolicy.permanentRPC(code: rpc.code, message: rpc.message)
        } else {
            attention = ObservationAnalysisReviewDeliveryPolicy.requiresAttention(error)
        }
        // A missing or replaced claim rejects this write. Never recreate work or overwrite its successor.
        try Store.retry(claim, at: now(), needsAttention: attention, container: container, isCurrent: current, save: save)
        return attention ? .needsAttention : .waiting
    }
}

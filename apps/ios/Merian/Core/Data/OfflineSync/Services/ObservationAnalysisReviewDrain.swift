import Foundation
import SwiftData

/// A bounded, sequential pass. The queue owns opportunities; delivery owns durable phase transitions.
@MainActor
struct ObservationAnalysisReviewDrain {
    typealias Store = ObservationAnalysisReviewPersistence
    let cloud: ObservationHistoryCloudClient
    let deliver: (ObservationAnalysisReviewIntent, ModelContainer, @escaping @MainActor @Sendable () -> Bool) async throws -> ObservationAnalysisReviewDeliveryService.Outcome
    var candidates: (ModelContainer, UUID) throws -> [(ObservationAnalysisReviewIntent, Date)] = { try Store.candidates(container: $0, ownerID: $1) }
    var now: () -> Date = Date.init

    func run(ownerID: UUID, container: ModelContainer, isCurrent: @escaping @MainActor @Sendable () -> Bool,
             didStart: () -> Void, requestRetry: () -> Void) async {
        guard isCurrent(), !Task.isCancelled else { return }
        let lease: AccountBoundWorkLease
        do { lease = try cloud.begin(ownerID) } catch {
            if isCurrent(), !Task.isCancelled, needsFallback(error) { requestRetry() }
            return
        }
        defer { cloud.finish(lease) }
        let current: @MainActor @Sendable () -> Bool = {
            !Task.isCancelled && isCurrent() && lease.session.userID == ownerID && cloud.isCurrent(lease)
        }
        guard current() else { return }
        didStart()
        do {
            let due = try candidates(container, ownerID).filter { $0.1 <= now() }.prefix(8)
            for (intent, _) in due {
                guard current(), intent.ownerID == ownerID else { return }
                do {
                    _ = try await deliver(intent, container, current)
                } catch Store.IntegrityError.accountChanged { return
                } catch ObservationHistoryError.accountChanged { return
                } catch is CancellationError { return
                } catch is SupabaseAuthTransitionError { return
                } catch {
                    guard current() else { return }
                    if needsFallback(error) { requestRetry(); return }
                    // A stale/deleted claim cannot starve independent later observations.
                }
                guard current() else { return }
            }
        } catch {
            if current(), needsFallback(error) { requestRetry() }
        }
    }

    private func needsFallback(_ error: Error) -> Bool {
        if error is CancellationError || error is SupabaseAuthTransitionError || error is Store.IntegrityError { return false }
        if let history = error as? ObservationHistoryError,
           history == .accountChanged || history == .deleted || history == .unavailable { return false }
        return true
    }
}

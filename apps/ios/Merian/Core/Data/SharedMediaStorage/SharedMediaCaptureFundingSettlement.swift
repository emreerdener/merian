import Foundation

/// Funding effects for a result already committed through Capture custody.
/// The writer creates the handoff only while its scan/account operation is held.
/// Neither this handoff nor settlement authorizes queue cleanup or media release.
@MainActor
enum SharedMediaCaptureFundingSettlement {
    /// Repository callers cannot replace production effects with an arbitrary
    /// acknowledgement closure. The only override is gated at construction.
    @MainActor
    final class Delivery {
        private let testOverride: ((SharedMediaCaptureResultWriter.FundingHandoff) throws -> Void)?
        private var lease: AccountBoundWorkLease?

        init(testOverride: ((SharedMediaCaptureResultWriter.FundingHandoff) throws -> Void)? = nil) throws {
            if testOverride != nil {
                #if DEBUG
                guard TestExecutionCoordinator.isRunningTests else { throw SharedMediaStorageFailure.closed }
                #else
                throw SharedMediaStorageFailure.closed
                #endif
            }
            self.testOverride = testOverride
        }

        func apply(_ handoff: SharedMediaCaptureResultWriter.FundingHandoff) throws {
            guard lease == nil else { throw SharedMediaStorageFailure.conflict }
            if let testOverride { try testOverride(handoff) } else {
                lease = try SharedMediaCaptureFundingSettlement.apply(handoff)
            }
        }

        func reconcileAfterPersistence() {
            guard let lease else { return }
            self.lease = nil
            SharedMediaCaptureFundingSettlement.reconcile(after: lease)
        }
    }

    static func apply(_ handoff: SharedMediaCaptureResultWriter.FundingHandoff) throws -> AccountBoundWorkLease {
        try handoff.validate()
        let value = handoff.settlement
        let auth = SupabaseManager.shared
        let entitlements = EntitlementManager.shared
        guard !auth.isAuthTransitionInProgress, entitlements.activeAccountID == value.accountId,
              entitlements.acceptsScanSnapshot(value.entitlementAfter, for: value.accountId) else {
            throw SharedMediaStorageFailure.closed
        }
        let lease = try auth.beginUnownedAccountBoundWork(expectedUserID: value.accountId)
        do { try handoff.validate() } catch { auth.finishAccountBoundWork(lease); throw error }
        // These existing operations are per-scan idempotent. In particular a
        // lost acknowledgement may replay without consuming another credit.
        _ = entitlements.applyScanSnapshot(value.entitlementAfter, for: value.accountId)
        UsageManager.shared.reconcileServerPlanUsed(value.planUsed, scanId: value.scanId)
        entitlements.recordCompletedFunding(planUsed: value.planUsed,
            creditConsumed: value.creditConsumed, scanId: value.scanId)
        return lease
    }

    /// Called after the native operation has released its scan/root fences.
    static func reconcile(after lease: AccountBoundWorkLease) {
        OfflineQueueManager.shared.inferenceFundingReconciliationOwner.enqueue(lease: lease)
    }
}

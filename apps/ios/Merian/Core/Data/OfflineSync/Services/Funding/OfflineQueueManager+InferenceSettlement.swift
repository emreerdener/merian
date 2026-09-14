import Foundation

// MARK: - Accepted Inference Funding Settlement

extension OfflineQueueManager {
    /// Applies account-sensitive result metadata only after the exact inference
    /// owner has durably finalized. The account-work lease is acquired before
    /// any mutation, closing Auth admission against the complete settlement and
    /// its coalesced queue-reconciliation follow-up.
    @discardableResult
    func commitInferenceResponseSettlement(
        _ settlement: InferenceResponseSettlement
    ) -> Bool {
        guard !SupabaseManager.shared.isAuthTransitionInProgress,
              EntitlementManager.shared.activeAccountID == settlement.accountId,
              EntitlementManager.shared
              .acceptsScanSnapshot(
                  settlement.entitlementAfter,
                  for: settlement.accountId
              ),
              let lease = try? SupabaseManager.shared
              .beginUnownedAccountBoundWork(
                  expectedUserID: settlement.accountId
              ) else {
            return false
        }

        _ = EntitlementManager.shared.applyScanSnapshot(
            settlement.entitlementAfter,
            for: settlement.accountId
        )
        UsageManager.shared.reconcileServerPlanUsed(
            settlement.planUsed,
            scanId: settlement.scanId
        )
        EntitlementManager.shared.recordCompletedFunding(
            planUsed: settlement.planUsed,
            creditConsumed: settlement.creditConsumed,
            scanId: settlement.scanId
        )
        inferenceFundingReconciliationOwner.enqueue(lease: lease)
        return true
    }

    /// Auth admission calls this after closing ordinary account-work admission.
    /// Cancellation is cooperative, so awaiting the retained task and its lease
    /// is required before the source session may be replaced.
    func cancelAndAwaitInferenceFundingSettlementForAuthTransition() async {
        await inferenceFundingReconciliationOwner.cancelAndAwait()
    }
}

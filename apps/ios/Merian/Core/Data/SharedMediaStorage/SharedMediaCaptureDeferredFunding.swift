import Foundation

/// One qualified admission refresh before an execution attempt. Server status
/// and entitlement reads cannot release an absent or changed local blocker.
@MainActor
enum SharedMediaCaptureDeferredFunding {
    static func prepare(_ candidate: SharedMediaCaptureExecutionRecovery.Candidate,
                        owner: SharedMediaNativeOriginalOwner, network: MerianNetworkClient,
                        scope: InferenceCompletionAccountScope,
                        canUseNetwork: @MainActor () -> Bool) async throws -> Bool {
        let funding = try await owner.capturePreparationFunding(candidate)
        try scope.validate()
        if funding.allowsDispatch { return true }
        guard candidate.dispatch == nil, funding.accountId == scope.ownerID,
              EntitlementManager.shared.activeAccountID == scope.ownerID, canUseNetwork() else {
            throw SharedMediaStorageFailure.closed
        }
        let before = try await owner.captureFundingOwnership(funding)
        try scope.validate()
        guard canUseNetwork() else { throw SharedMediaStorageFailure.unavailable }
        let requirements = Dictionary(uniqueKeysWithValues: funding.blockerScanIds.map { ($0, 0) })
        let responses = try await network.checkScanStatuses(requirements)
        try scope.validate()
        guard canUseNetwork(), try await owner.captureFundingOwnership(funding) == before else {
            throw SharedMediaStorageFailure.stale
        }
        try scope.validate()
        for id in funding.blockerScanIds {
            guard let entry = before[id], let response = responses[id] else { continue }
            EntitlementManager.shared.applyComplimentaryState(response.complimentaryState, scanId: id,
                terminalized: entry.terminal || response.isFound || response.jobStatus == .failed || response.jobStatus == .complete)
        }
        // A fresh balance read is required before reusing released capacity.
        let ids = Set(before.keys)
        if EntitlementManager.shared.needsLegacyFundingRefresh(eligibleLegacyScanIDs: ids) {
            guard canUseNetwork() else { throw SharedMediaStorageFailure.unavailable }
            let refreshed = await EntitlementManager.shared.refreshCurrentSession()
            try scope.validate()
            guard refreshed, canUseNetwork(), try await owner.captureFundingOwnership(funding) == before else {
                throw SharedMediaStorageFailure.stale
            }
            try scope.validate()
            EntitlementManager.shared.confirmTerminalSettlementsAfterEntitlementRefresh(eligibleLegacyScanIDs: ids)
        }
        let proofs = before.mapValues(\.proof)
        guard let evidence = EntitlementManager.shared.captureFundingEvidence(ownershipProofs: proofs),
              let decision = CaptureDeferredFundingDecision(original: funding, evidence: evidence) else { return false }
        _ = try await owner.resolveCaptureFunding(candidate, decision: decision, requireEvidence: {
            try scope.validate()
            guard EntitlementManager.shared.captureFundingEvidence(ownershipProofs: proofs) == evidence else {
                throw SharedMediaStorageFailure.stale
            }
        })
        try scope.validate()
        EntitlementManager.shared.restoreQualifiedCaptureFunding(decision.effective)
        if decision.effective.source == .immediateFlash { UsageManager.shared.consumeScan(scanId: funding.scanId) } else {
            UsageManager.shared.refundScan(scanId: funding.scanId)
        }
        return true
    }
}

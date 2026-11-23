import Foundation

/// Production adapters for the single retained account-lifetime worker.
@MainActor
enum SharedMediaCaptureExecutionLifetime {
    static func make(owner: SharedMediaNativeOriginalOwner,
                     account: PhotoOriginalPreparationOwner.AccountAccess,
                     network: MerianNetworkClient,
                     isCurrent: @escaping @MainActor () -> Bool,
                     canUseNetwork: @escaping @MainActor () -> Bool,
                     didComplete: @escaping @MainActor () -> Void = {}) -> SharedMediaCaptureExecutionDrain {
        SharedMediaCaptureExecutionDrain(dependencies: .init(begin: {
            guard isCurrent() else { throw SharedMediaStorageFailure.closed }
            let lease = try account.begin()
            let scope = InferenceCompletionAccountScope(ownerID: account.ownerID,
                isCurrent: { isCurrent() && lease.session.userID == account.ownerID && account.isCurrent(lease) },
                release: { account.finish(lease) })
            do { try scope.validate(); return scope } catch { scope.finish(); throw error }
        }, page: { cursor, scope in
            try await requireReady(owner, scope: scope)
            try await owner.restoreCaptureAdmissionFunding()
            try scope.validate()
            return try await owner.captureExecutionRecoveryPage(after: cursor)
        }, claim: { candidate, now, scope in
            try await requireReady(owner, scope: scope)
            return try await owner.beginAppCaptureExecution(candidate, now: now)
        }, execute: { candidate, scope in
            try await requireReady(owner, scope: scope)
            guard candidate.dispatch == nil, canUseNetwork() else { throw SharedMediaStorageFailure.closed }
            try await restoreFunding(candidate, owner: owner, scope: scope)
            _ = try await owner.stageAppCaptureSubmission(scanID: candidate.scanID,
                generation: candidate.generation, transport: network.captureStageTransport())
            try scope.validate()
            guard canUseNetwork() else { throw SharedMediaStorageFailure.unavailable }
            _ = try await owner.executeAppCapture(candidate, network: network, account: scope)
            try scope.validate(); didComplete()
        }, postpone: { candidate, due, scope in
            try await requireReady(owner, scope: scope)
            return try await owner.postponeAppCaptureExecution(candidate, until: due).due != nil
        }, recover: { candidate, scope in
            try await requireReady(owner, scope: scope)
            guard candidate.dispatch != nil, canUseNetwork() else { throw SharedMediaStorageFailure.closed }
            try await restoreFunding(candidate, owner: owner, scope: scope)
            // No upload, preparation, funding admission or new dispatch here.
            _ = try await owner.executeAppCapture(candidate, network: network, account: scope)
            try scope.validate(); didComplete()
        }, prepareFunding: { candidate, scope in
            try await requireReady(owner, scope: scope)
            return try await SharedMediaCaptureDeferredFunding.prepare(candidate, owner: owner,
                network: network, scope: scope, canUseNetwork: canUseNetwork)
        }, isCurrent: isCurrent, canUseNetwork: canUseNetwork))
    }

    private static func restoreFunding(_ candidate: SharedMediaCaptureExecutionRecovery.Candidate,
                                       owner: SharedMediaNativeOriginalOwner,
                                       scope: InferenceCompletionAccountScope) async throws {
        let funding = try await owner.capturePreparationFunding(candidate)
        try scope.validate()
        guard funding.accountId == scope.ownerID, funding.allowsDispatch,
              EntitlementManager.shared.activeAccountID == scope.ownerID else { throw SharedMediaStorageFailure.closed }
        EntitlementManager.shared.restoreFundingReservation(funding)
        if funding.source == .immediateFlash { UsageManager.shared.consumeScan(scanId: funding.scanId) }
    }

    private static func requireReady(_ owner: SharedMediaNativeOriginalOwner,
                                     scope: InferenceCompletionAccountScope) async throws {
        try scope.validate()
        if owner.requiresCaptureRecovery { try await owner.resumeAppCaptureRoot() }
        try scope.validate()
        guard owner.isReadyForCaptureSettlement else { throw SharedMediaStorageFailure.closed }
    }
}

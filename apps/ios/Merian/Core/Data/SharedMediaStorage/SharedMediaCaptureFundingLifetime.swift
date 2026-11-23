import Foundation

/// Connects a qualified native owner to local receipt recovery. The host opens
/// the owner before registering this worker, so a failed initial open can join
/// native shutdown without waiting on the worker that requested that open.
@MainActor
enum SharedMediaCaptureFundingLifetime {
    static func make(owner: SharedMediaNativeOriginalOwner,
                     account: PhotoOriginalPreparationOwner.AccountAccess,
                     isCurrent: @escaping @MainActor () -> Bool,
                     didRecover: @escaping @MainActor () -> Void = {}) -> SharedMediaCaptureFundingDrain {
        SharedMediaCaptureFundingDrain(dependencies: .init(begin: {
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
            let page = try await owner.captureFundingRecoveryPage(after: cursor)
            try scope.validate()
            return page
        }, recover: { candidate, scope in
            try await requireReady(owner, scope: scope)
            try await owner.recoverAppCaptureFunding(scanID: candidate.scanID,
                submissionGeneration: candidate.generation, account: scope)
            try scope.validate()
            didRecover()
        }, postpone: { candidate, due, scope in
            try await requireReady(owner, scope: scope)
            try await owner.postponeAppCaptureFunding(candidate, until: due)
            try scope.validate()
        }, isCurrent: isCurrent))
    }

    private static func requireReady(_ owner: SharedMediaNativeOriginalOwner,
                                     scope: InferenceCompletionAccountScope) async throws {
        try scope.validate()
        // Requalify this same retained owner after an interrupted operation;
        // recovery cannot create a replacement lifetime or adopt another root.
        if owner.requiresCaptureRecovery { try await owner.resumeAppCaptureRoot() }
        try scope.validate()
        guard owner.isReadyForCaptureSettlement else { throw SharedMediaStorageFailure.closed }
    }
}

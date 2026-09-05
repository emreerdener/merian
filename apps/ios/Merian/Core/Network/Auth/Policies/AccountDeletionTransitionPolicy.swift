import Foundation

@MainActor
enum AccountDeletionTransitionPolicy {
    nonisolated static func canRestoreDeferredBarrierSession(
        markerIsPending: Bool,
        sourceSession: AuthTransitionSession?,
        cachedUserID: UUID?,
        cachedUserIsAnonymous: Bool,
        cachedSessionIsExpired: Bool
    ) -> Bool {
        guard markerIsPending,
              !cachedSessionIsExpired,
              let sourceSession,
              let cachedUserID else {
            return false
        }
        return sourceSession.userID == cachedUserID
            && sourceSession.isAnonymous == cachedUserIsAnonymous
    }

    static func isDefinitiveIntakeRejection(_ error: Error) -> Bool {
        guard case let MerianError.httpError(statusCode, _) = error,
              statusCode == 409 else {
            return false
        }
        // This is the only public safe-delete rejection emitted after the
        // authenticated handler has proved that durable intake did not win.
        // Auth/gateway 4xx responses cannot exclude an earlier lost-response
        // commit and therefore remain fenced for recovery.
        return EdgeFunctionErrorPolicy.stableCode(from: error)
            == "purchase_continuity_pending"
    }

    static func isAcceptedExpiredRecovery(_ error: Error) -> Bool {
        guard case let MerianError.httpError(statusCode, _) = error,
              statusCode == 410 else {
            return false
        }
        return EdgeFunctionErrorPolicy.stableCode(from: error)
            == "account_deletion_recovery_expired"
    }

    static func isUnknownRecovery(_ error: Error) -> Bool {
        guard case let MerianError.httpError(statusCode, _) = error,
              statusCode == 404 else {
            return false
        }
        return EdgeFunctionErrorPolicy.stableCode(from: error)
            == "account_deletion_recovery_invalid"
    }
}

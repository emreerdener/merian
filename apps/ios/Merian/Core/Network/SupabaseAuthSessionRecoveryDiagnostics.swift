import Foundation
import os

/// Maps provider-neutral recovery outcomes onto the live privacy-safe Auth log.
@MainActor
enum SupabaseAuthSessionRecoveryDiagnostics {
    static func report(
        _ diagnostic: AuthSessionRecoveryDiagnostic,
        error: Error?
    ) {
        let errorKind = error.map { MerianLog.errorKind($0) } ?? "unavailable"
        switch diagnostic {
        case .ordinaryRefreshSucceeded:
            MerianLog.auth.debug(
                "Supabase session refreshed after auth failure."
            )
        case .ordinaryRefreshFailed:
            MerianLog.auth.debug(
                "Supabase session refresh after auth failure failed; kind=\(errorKind, privacy: .public)"
            )
        case .transitionOwnedRefreshSucceeded:
            MerianLog.auth.debug(
                "Refreshed the exact session owned by an authentication transition."
            )
        case .transitionOwnedRefreshFailed:
            MerianLog.auth.debug(
                "Transition-owned session refresh failed; kind=\(errorKind, privacy: .public)."
            )
        case .anonymousResetBlockedByPurchaseHandoff:
            MerianLog.auth.error(
                "Refused to rotate an anonymous session while purchase continuity is pending."
            )
        case .anonymousResetPurchaseIdentityNotReady:
            MerianLog.auth.debug(
                "Anonymous session regenerated, but purchase identity is not ready for request replay."
            )
        case .anonymousResetSucceeded:
            MerianLog.auth.debug(
                "Anonymous session regenerated after auth failure."
            )
        case .anonymousResetFailed:
            MerianLog.auth.debug(
                "Signed-out session regeneration after auth failure failed; kind=\(errorKind, privacy: .public)"
            )
        case .localClearBlockedByPurchaseHandoff:
            MerianLog.auth.error(
                "Preserved the exact local auth session because purchase continuity is pending."
            )
        case .localSDKSignOutFailed:
            MerianLog.auth.debug(
                "Local Supabase sign-out after auth failure failed; kind=\(errorKind, privacy: .public)"
            )
        case .localSessionCleared:
            MerianLog.auth.debug(
                "Cleared local Supabase session after auth failure."
            )
        }
    }
}

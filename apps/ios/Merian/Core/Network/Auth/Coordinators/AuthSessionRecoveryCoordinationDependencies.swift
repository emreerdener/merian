import Foundation

enum AuthSessionRecoveryEntryPolicy: Equatable {
    case requireActiveCaller
    case completeMutatedOAuthSession

    func permitsEntry(isCancelled: Bool) -> Bool {
        self == .completeMutatedOAuthSession || !isCancelled
    }
}

enum AuthSessionLocalClearOutcome: Equatable {
    case cleared
    case rejected
    case blockedByPurchaseHandoff
}

/// Provider-neutral capabilities for one SDK session observed during Auth
/// recovery. The live facade captures its provider value inside these closures.
struct AuthSessionRecoverySession {
    let identity: AuthTransitionSession
    let adopt: @MainActor (AuthTransitionToken) -> Bool
    let publish: @MainActor () -> Void
    let schedulePublicAuthorIdentityRefresh: @MainActor () -> Void
    let ensurePurchaseIdentityReady: @MainActor (
        AuthTransitionToken
    ) async -> Void
    let purchaseIdentityIsReady: @MainActor () -> Bool
    let beginEntitlementSession: @MainActor (
        AuthTransitionToken
    ) async -> Bool
    let isPublishedAtCapturedGeneration: @MainActor () -> Bool
}

struct AuthSessionRecoveryStateBoundary {
    let isSigningOut: @MainActor () -> Bool
    let hasPendingPurchaseIdentityHandoff: @MainActor () -> Bool
    let clearLocalRecoveryState: @MainActor () -> Void
}

struct AuthSessionRecoveryTransitionBoundary {
    let beginRecovery: @MainActor () -> AuthTransitionToken?
    let finish: @MainActor (AuthTransitionToken) -> Void
    let owns: @MainActor (AuthTransitionToken) -> Bool
    let expectedSession: @MainActor (
        AuthTransitionToken
    ) -> AuthTransitionSession?
    let awaitAccountWorkQuiescence: @MainActor () async -> Bool
    let currentSessionMatches: @MainActor (
        AuthTransitionToken
    ) -> Bool
    let updatePhase: @MainActor (
        AuthTransitionToken,
        AuthTransitionPhase
    ) -> Void
    let adoptSignedOutSession: @MainActor (
        AuthTransitionToken
    ) -> Void
}

struct AuthSessionRecoveryOperationBoundary {
    let refreshSDKSession: @MainActor () async throws
        -> AuthSessionRecoverySession
    let loadSDKSession: @MainActor () async throws
        -> AuthSessionRecoverySession
    let resetAnonymousSession: @MainActor (
        AuthTransitionToken
    ) async -> Bool
    let performLocalSDKSignOut: @MainActor () async throws -> Void
    let finishPurchaseIdentitySignOut: @MainActor () async -> Void
}

enum AuthSessionRecoveryDiagnostic: Equatable {
    case ordinaryRefreshSucceeded
    case ordinaryRefreshFailed
    case transitionOwnedRefreshSucceeded
    case transitionOwnedRefreshFailed
    case anonymousResetBlockedByPurchaseHandoff
    case anonymousResetPurchaseIdentityNotReady
    case anonymousResetSucceeded
    case anonymousResetFailed
    case localClearBlockedByPurchaseHandoff
    case localSDKSignOutFailed
    case localSessionCleared
}

struct AuthSessionRecoveryDependencies {
    let state: AuthSessionRecoveryStateBoundary
    let transition: AuthSessionRecoveryTransitionBoundary
    let operations: AuthSessionRecoveryOperationBoundary
    let diagnose: @MainActor (
        AuthSessionRecoveryDiagnostic,
        Error?
    ) -> Void
}

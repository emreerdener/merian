import Foundation

struct AuthSessionLifecycleStateBoundary {
    let accountDeletionCleanupPending: @MainActor () -> Bool
    let hasActiveTransition: @MainActor () -> Bool
    let isSigningOut: @MainActor () -> Bool
    let isUserSignOutTransitionInProgress: @MainActor () -> Bool
    let publishedSession: @MainActor () -> AuthTransitionSession?
    let publishSDKSession: @MainActor (AuthTransitionSession) -> Bool
    let clearPublishedSession: @MainActor () -> Void
    let clearPurchasePrincipalBinding: @MainActor () -> Void
    let clearLinkedUser: @MainActor () -> Void
    let beginPurchaseIdentityResolution: @MainActor () -> Void
    let beginAccountSession: @MainActor (
        UUID?,
        AuthSessionLifecycleOrigin
    ) -> Void
    let observeConsentSession: @MainActor (UUID?) -> Void
    let schedulePublicAuthorIdentityRefresh: @MainActor (
        AuthTransitionSession
    ) -> Void
    let clearPublicAuthorIdentityRefreshMarker: @MainActor () -> Void
    let cancelPublicAuthorIdentityRefresh: @MainActor () -> Void
    let cancelAppleCredentialRevocation: @MainActor () -> Void
    let cancelGhostProfileMerge: @MainActor () -> Void
    let isCurrentPublishedSession: @MainActor (
        AuthTransitionSession,
        UInt64
    ) -> Bool
    let isCurrentLifecycleSession: @MainActor (
        AuthTransitionSession?,
        UInt64
    ) -> Bool
}

struct AuthSessionLifecycleDurabilityBoundary {
    let hasPendingGhostProfileMerge: @MainActor () throws -> Bool
    let setAnalyticsSuppressedForGhostHandoff: @MainActor (Bool) -> Void
    let hasPendingPurchaseIdentityHandoff: @MainActor () throws -> Bool
    let setPurchaseIdentityHandoffPending: @MainActor (Bool) -> Void
}

struct AuthSessionLifecycleIdentityBoundary {
    let isTestExecution: @MainActor () -> Bool
    let isPurchaseIdentityHandoffPending: @MainActor () -> Bool
    let completePendingPurchaseIdentityHandoff: @MainActor (
        AuthTransitionSession,
        UInt64
    ) async -> Void
    let ensureTelemetryLinked: @MainActor (
        AuthTransitionSession
    ) async -> Bool
    let abandonRestoredSourceHandoffs: @MainActor (
        AuthTransitionSession
    ) async -> Void
    let clearEntitlementSession: @MainActor () -> Void
    let beginEntitlementSession: @MainActor (
        AuthTransitionSession
    ) async -> Void
    let handleSupabaseSignOut: @MainActor () async -> Void
    let scheduleHistoricalSync: @MainActor (
        AuthTransitionSession,
        UInt64
    ) -> Void
}

struct AuthSessionLifecycleDependencies {
    let state: AuthSessionLifecycleStateBoundary
    let durability: AuthSessionLifecycleDurabilityBoundary
    let identity: AuthSessionLifecycleIdentityBoundary
    let diagnose: @MainActor (
        AuthSessionLifecycleDiagnostic,
        Error?
    ) -> Void
}

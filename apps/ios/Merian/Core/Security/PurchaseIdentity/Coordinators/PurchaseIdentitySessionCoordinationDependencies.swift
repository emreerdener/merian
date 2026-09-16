import Foundation

struct PurchaseIdentitySessionStateBoundary {
    let isTestExecution: @MainActor () -> Bool
    let accountDeletionCleanupPending: @MainActor () -> Bool
    let isSigningOut: @MainActor () -> Bool
    let isAuthenticated: @MainActor () -> Bool
    let isUserSignOutTransitionInProgress: @MainActor () -> Bool
    let currentPublishedSession: @MainActor ()
        -> PurchaseIdentitySessionContext?
    let isCurrentPublishedSession: @MainActor (
        PurchaseIdentitySessionContext
    ) -> Bool
    let beginAccountWork: @MainActor (
        UUID
    ) -> PurchaseIdentityAccountWorkLease?
    let loadSDKSession: @MainActor () async throws
        -> PurchaseIdentitySessionSnapshot
}

struct PurchaseIdentitySessionProviderBoundary {
    let beginResolution: @MainActor () -> Void
    let resolve: @MainActor (
        String?,
        Bool
    ) async throws -> PurchasePrincipalBinding
    let applyStableBinding: @MainActor (
        PurchasePrincipalBinding,
        UUID,
        String
    ) async -> Void
    let currentState: @MainActor () -> PurchaseIdentityProviderState
}

struct PurchaseIdentitySessionHandoffBoundary {
    let loadPending: @MainActor () throws -> Bool
    let setPending: @MainActor (Bool) -> Void
    let completePending: @MainActor (
        PurchaseIdentitySessionContext
    ) async -> Bool
    let abandonRestoredSource: @MainActor (
        PurchaseIdentitySessionContext
    ) async -> Void
}

extension PurchaseIdentitySessionHandoffBoundary {
    /// Keeps the provider's synchronous mutation fence aligned with the
    /// device-durable handoff journals before any identity work proceeds.
    @MainActor
    func loadAndPublishPendingState() throws -> Bool {
        let pending = try loadPending()
        setPending(pending)
        return pending
    }
}

struct PurchaseIdentityEntitlementBoundary {
    let isReady: @MainActor (UUID) -> Bool
    let beginSession: @MainActor (UUID) async -> Bool
}

struct PurchaseIdentitySessionDependencies {
    let state: PurchaseIdentitySessionStateBoundary
    let provider: PurchaseIdentitySessionProviderBoundary
    let handoff: PurchaseIdentitySessionHandoffBoundary
    let entitlement: PurchaseIdentityEntitlementBoundary
    let reportHandoffStateFailure: @MainActor (Error) -> Void
    let reportDeferredForHandoff: @MainActor () -> Void
    let reportResolutionFailure: @MainActor (Error) -> Void
}

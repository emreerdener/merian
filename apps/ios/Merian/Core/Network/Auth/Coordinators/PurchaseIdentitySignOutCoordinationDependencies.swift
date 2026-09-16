import Foundation

struct PurchaseIdentitySignOutSourceContext {
    let session: AuthTransitionSession
    let authGeneration: UInt64
    let binding: PurchasePrincipalBinding
    let purchaseProviderIsReady: Bool
}

struct PurchaseIdentitySignOutSessionSnapshot {
    let identity: AuthTransitionSession
    let ensureTelemetryLinked: @MainActor (
        AuthTransitionToken
    ) async -> Void
}

struct PurchaseIdentitySignOutSessionBoundary {
    let beginTransition: @MainActor (AuthTransitionKind)
        -> AuthTransitionToken?
    let finishTransition: @MainActor (AuthTransitionToken) -> Void
    let updateTransition: @MainActor (
        AuthTransitionToken,
        AuthTransitionPhase
    ) -> Void
    let ownsTransition: @MainActor (AuthTransitionToken) -> Bool
    let awaitAccountBoundWorkQuiescence: @MainActor () async -> Bool
    let loadSDKSession: @MainActor () async throws
        -> PurchaseIdentitySignOutSessionSnapshot
    let fallbackPublishedSession: @MainActor ()
        -> PurchaseIdentitySignOutSessionSnapshot?
    let hasKnownLinkedIdentity: @MainActor () -> Bool
    let initializeAnonymousSession: @MainActor (
        AuthTransitionToken
    ) async -> AuthTransitionSession?
    let performLocalSignOut: @MainActor (
        AuthTransitionToken
    ) async -> Void
    let resolveLinkedSourceContext: @MainActor (
        PurchaseIdentitySignOutSessionSnapshot,
        AuthTransitionToken
    ) async -> PurchaseIdentitySignOutSourceContext?
    let currentSessionMatchesTransition: @MainActor (
        AuthTransitionToken
    ) -> Bool
}

struct PurchaseIdentitySignOutJournalBoundary {
    let loadLegacyHandoff: @MainActor () throws
        -> PendingSignOutPurchaseHandoff?
    let loadStableRotation: @MainActor () throws
        -> PendingPurchasePrincipalAuthRotation?
    let setHandoffPending: @MainActor (Bool) -> Void
    let completePendingHandoff: @MainActor (
        String?,
        AuthTransitionToken
    ) async -> Bool
    let abandonStableRotationIfSourceRestored: @MainActor (
        UUID,
        AuthTransitionToken
    ) async -> Void
    let abandonLegacyHandoffIfSourceRestored: @MainActor (
        String,
        AuthTransitionToken
    ) async -> Void
    let prepareStableRotation: @MainActor (
        PurchaseIdentitySignOutSourceContext,
        AuthTransitionToken
    ) async throws -> Void
    let prepareLegacyHandoff: @MainActor (
        String,
        AuthTransitionToken
    ) async throws -> Void
    let restoreSourceIdentityAfterFailedSignOut: @MainActor (
        UUID,
        AuthTransitionToken
    ) async -> Void
}

struct PurchaseIdentitySignOutDiagnostics {
    let reportUnreadableJournal: @MainActor () -> Void
    let reportUnverifiedLinkedSession: @MainActor () -> Void
    let reportUnrelatedStableRotation: @MainActor () -> Void
    let reportUnrelatedLegacyHandoff: @MainActor () -> Void
    let reportTransitionFailure: @MainActor (Error) -> Void
}

struct PurchaseSignOutDependencies {
    let session: PurchaseIdentitySignOutSessionBoundary
    let journal: PurchaseIdentitySignOutJournalBoundary
    let diagnostics: PurchaseIdentitySignOutDiagnostics
}

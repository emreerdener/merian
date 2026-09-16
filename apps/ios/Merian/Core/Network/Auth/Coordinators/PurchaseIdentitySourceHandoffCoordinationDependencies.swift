import Foundation

struct SourceHandoffSessionBoundary {
    let currentAuthGeneration: @MainActor () -> UInt64
    let currentPublishedUserID: @MainActor () -> UUID?
    let currentSDKUserID: @MainActor () -> UUID?
    let ownsTransition: @MainActor (AuthTransitionToken) -> Bool
    let currentSessionMatchesTransition: @MainActor (
        AuthTransitionToken
    ) -> Bool
    let beginUnownedAccountWork: @MainActor (
        UUID
    ) -> AccountBoundWorkLease?
    let isAccountWorkCurrent: @MainActor (
        AccountBoundWorkLease
    ) -> Bool
    let finishAccountWork: @MainActor (AccountBoundWorkLease) -> Void
    let loadSDKSession: @MainActor () async throws
        -> AuthTransitionSession
    let adoptSourceSession: @MainActor (
        UUID,
        AuthTransitionToken
    ) -> Bool
    let publishRestoredSource: @MainActor (UUID) -> Bool
    let restoredSourceIsCurrent: @MainActor (
        UUID,
        AuthTransitionToken
    ) -> Bool
}

struct SourceHandoffJournalBoundary {
    let loadLegacyHandoff: @MainActor () throws
        -> PendingSignOutPurchaseHandoff?
    let loadStableRotation: @MainActor () throws
        -> PendingPurchasePrincipalAuthRotation?
    let clearLegacyHandoff: @MainActor () throws -> Void
    let clearStableRotation: @MainActor () throws -> Void
    let setHandoffPending: @MainActor (Bool) -> Void
}

struct SourceHandoffOperationBoundary {
    let prepareStableRotation: @MainActor (
        UUID,
        PurchasePrincipalBinding
    ) async throws -> Void
    let prepareLegacyHandoff: @MainActor (UUID) async throws -> Void
    let cancelStableRotation: @MainActor (
        ServerPrincipalRotation
    ) async throws -> Void
    let cancelLegacyHandoff: @MainActor (
        PendingSignOutPurchaseHandoff
    ) async throws -> Void
    let ensurePurchaseIdentityReady: @MainActor (
        UUID,
        AuthTransitionToken
    ) async -> Void
    let beginEntitlementSession: @MainActor (
        UUID,
        AuthTransitionToken
    ) async -> Void
}

struct SourceHandoffDiagnostics {
    let reportPendingStateFailure: @MainActor (Error) -> Void
    let reportLegacyPreparation: @MainActor () -> Void
    let reportLegacyAbandonment: @MainActor () -> Void
    let reportLegacyAbandonmentFailure: @MainActor (Error) -> Void
    let reportSourceRestoration: @MainActor () -> Void
}

struct SourceHandoffDependencies {
    let session: SourceHandoffSessionBoundary
    let journal: SourceHandoffJournalBoundary
    let operations: SourceHandoffOperationBoundary
    let diagnostics: SourceHandoffDiagnostics
}

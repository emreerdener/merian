import Foundation

struct PurchaseIdentityHandoffSessionSnapshot {
    let identity: AuthTransitionSession
    let linkLegacyProviderIdentity: @MainActor () async throws -> Void
    let ensureTelemetryLinked: @MainActor (
        AuthTransitionToken?
    ) async -> Void
}

struct PurchaseIdentityHandoffSessionBoundary {
    let currentPublishedAnonymousUserID: @MainActor () -> String?
    let currentAuthGeneration: @MainActor () -> UInt64
    let isLocalSignOutInProgress: @MainActor () -> Bool
    let currentSessionMatchesTransition: @MainActor (
        AuthTransitionToken
    ) -> Bool
    let beginUnownedAccountWork: @MainActor (
        UUID?
    ) -> AccountBoundWorkLease?
    let finishAccountWork: @MainActor (AccountBoundWorkLease) -> Void
    let loadSDKSession: @MainActor () async throws
        -> PurchaseIdentityHandoffSessionSnapshot
    let activeAnonymousSessionMatches: @MainActor (
        String,
        UInt64,
        AuthTransitionToken?
    ) -> Bool
}

struct PurchaseIdentityHandoffJournalBoundary {
    let loadLegacyHandoff: @MainActor () throws
        -> PendingSignOutPurchaseHandoff?
    let loadStableRotation: @MainActor () throws
        -> PendingPurchasePrincipalAuthRotation?
    let clearLegacyHandoff: @MainActor () throws -> Void
    let clearStableRotation: @MainActor () throws -> Void
    let setHandoffPending: @MainActor (Bool) -> Void
}

struct PurchaseIdentityHandoffOperationBoundary {
    let claimStableRotation: @MainActor (
        UUID,
        String,
        String
    ) async throws -> PurchasePrincipalBinding
    let applyStableBinding: @MainActor (
        PurchasePrincipalBinding,
        UUID
    ) async -> Void
    let stableProviderIdentityMatches: @MainActor (UUID) -> Bool
    let bindLegacyHandoff: @MainActor (
        PendingSignOutPurchaseHandoff,
        String
    ) async throws -> Void
    let synchronizeLegacyPurchases: @MainActor (UUID) async throws -> Void
    let completeLegacyHandoff: @MainActor (
        PendingSignOutPurchaseHandoff
    ) async throws -> Void
    let refreshEntitlement: @MainActor (
        UUID,
        AuthTransitionToken?
    ) async -> Bool
    let refreshCustomerInfo: @MainActor () async -> Void
    let recordLinkedUser: @MainActor (UUID) -> Void
    let abandonLegacyHandoffIfSourceRestored: @MainActor (
        String,
        AuthTransitionToken?
    ) async -> Void
    let shouldDiscardLegacyHandoff: @MainActor (Error) -> Bool
}

struct PurchaseIdentityHandoffDiagnostics {
    let reportJournalSelectionFailure: @MainActor (Error) -> Void
    let reportStableCompletionFailure: @MainActor (Error) -> Void
    let reportLegacyJournalFailure: @MainActor (Error) -> Void
    let reportLegacyCompletionFailure: @MainActor (Error) -> Void
    let reportStableCompletion: @MainActor () -> Void
    let reportLegacyCompletion: @MainActor () -> Void
}

struct PurchaseIdentityHandoffDependencies {
    let session: PurchaseIdentityHandoffSessionBoundary
    let journal: PurchaseIdentityHandoffJournalBoundary
    let operations: PurchaseIdentityHandoffOperationBoundary
    let diagnostics: PurchaseIdentityHandoffDiagnostics
}

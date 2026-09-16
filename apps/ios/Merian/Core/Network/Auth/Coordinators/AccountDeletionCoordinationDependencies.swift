import Foundation

struct AccountDeletionCachedSession: Equatable, Sendable {
    let identity: AuthTransitionSession
    let isExpired: Bool
}

struct AccountDeletionLocalStateBoundary {
    let state: @MainActor () -> AccountDeletionLocalRecoveryState?
    let isPending: @MainActor () -> Bool
    let recordCapabilityPreparationPending: @MainActor () -> Bool
    let recordCapabilityPreparedPending: @MainActor () -> Bool
    let recordIntakePending: @MainActor () -> Bool
    let recordCleanupPending: @MainActor () -> Bool
    let recordCapabilityRetirementPending: @MainActor () -> Bool
    let recordCapabilityRejectionRetirementPending: @MainActor () -> Bool
    let resolve: @MainActor () -> Bool
}

struct AccountDeletionSessionBoundary {
    let beginTransition: @MainActor (AuthTransitionKind)
        -> AuthTransitionToken?
    let finishTransition: @MainActor (AuthTransitionToken) -> Void
    let updateTransition: @MainActor (
        AuthTransitionToken,
        AuthTransitionPhase
    ) -> Void
    let ownsTransition: @MainActor (AuthTransitionToken) -> Bool
    let verifyExpectedSession: @MainActor (AuthTransitionToken) async throws
        -> Void
    let currentSessionMatchesTransition: @MainActor (
        AuthTransitionToken
    ) -> Bool
    let sourceSession: @MainActor (AuthTransitionToken)
        -> AuthTransitionSession?
    let loadCachedSession: @MainActor () async throws
        -> AccountDeletionCachedSession
    let currentCachedSession: @MainActor () -> AuthTransitionSession?
    let adoptCachedSession: @MainActor (
        AuthTransitionSession,
        AuthTransitionToken
    ) -> Bool
    let publishCachedSession: @MainActor (AuthTransitionSession) -> Void
    let performVerifiedLocalSignOut: @MainActor (
        AuthTransitionToken
    ) async -> Bool
}

struct AccountDeletionDiagnostics {
    let reportAcknowledgementPending: @MainActor (Error) -> Void
    let reportAcceptedCleanupPending: @MainActor () -> Void
    let reportRecoveryProofUnavailable: @MainActor () -> Void
    let reportCapabilityRecoveryPending: @MainActor (Error) -> Void
}

struct AccountDeletionCoordinationDependencies {
    let hasPendingPurchaseIdentityHandoff: @MainActor () -> Bool
    let localState: AccountDeletionLocalStateBoundary
    let session: AccountDeletionSessionBoundary
    let diagnostics: AccountDeletionDiagnostics
}

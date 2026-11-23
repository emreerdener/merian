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
    let cleanupMarker: @MainActor () -> AccountDeletionCleanupMarker?
    let prepareCleanupMarker: @MainActor (AccountDeletionLocalRecoveryState) -> Bool
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
    let verifyExpectedSession: @MainActor (AuthTransitionToken, AccountDeletionLocalCleanupStore.RecoveryScope) async throws
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
        AuthTransitionToken, AccountDeletionLocalCleanupStore.RecoveryScope
    ) async -> Bool
}

struct AccountDeletionDiagnostics {
    let reportAcknowledgementPending: @MainActor (Error) -> Void
    let reportAcceptedCleanupPending: @MainActor () -> Void
    let reportRecoveryProofUnavailable: @MainActor () -> Void
    let reportCapabilityRecoveryPending: @MainActor (Error) -> Void
}

struct AccountDeletionCoordinationDependencies {
    let validateLibrary: @MainActor (AnyObject?) -> Bool
    let acknowledgeLibraryPurge: @MainActor (AccountDeletionLocalCleanupStore.RecoveryScope) -> Bool
    let hasPendingPurchaseIdentityHandoff: @MainActor () -> Bool
    let localState: AccountDeletionLocalStateBoundary
    let session: AccountDeletionSessionBoundary
    let diagnostics: AccountDeletionDiagnostics

    /// Acceptance advances the durable marker before a scope captures its exact
    /// phase and operation identity. Nothing may suspend between these steps.
    @MainActor func acceptedCleanupScope(
        _ token: AuthTransitionToken, receipt: AccountDeletionReceipt,
        expectedState: AccountDeletionLocalRecoveryState?, expectedMarker: AccountDeletionCleanupMarker?,
        proof: PreparedDeletionRecoveryCapability, store: AccountDeletionRecoveryCapabilityStore
    ) -> AccountDeletionLocalCleanupStore.RecoveryScope? {
        guard receipt.success, receipt.status == .pending || receipt.status == .completed,
              session.currentSessionMatchesTransition(token), validateLibrary(nil),
              localState.state() == expectedState, localState.cleanupMarker() == expectedMarker, store.matchesExisting(proof),
              localState.recordCleanupPending() else { return nil }
        let result = scope(token, state: .capabilityCleanupPending, proof: proof, store: store)
        return result.isCurrent ? result : nil
    }

    @MainActor func scope(
        _ token: AuthTransitionToken, state: AccountDeletionLocalRecoveryState?,
        proof: PreparedDeletionRecoveryCapability?, store: AccountDeletionRecoveryCapabilityStore
    ) -> AccountDeletionLocalCleanupStore.RecoveryScope {
        var prepared = true
        if let state, [.cleanupPending, .capabilityCleanupPending, .capabilityRetirementPending].contains(state) {
            prepared = session.currentSessionMatchesTransition(token) && validateLibrary(nil) &&
                localState.state() == state && store.matchesExisting(proof) && localState.prepareCleanupMarker(state)
        }
        return .init(expectedState: state, expectedCapability: proof, capabilityStore: store, readState: localState.state,
            validateSession: { session.currentSessionMatchesTransition(token) }, validateLibrary: validateLibrary,
            expectedMarker: localState.cleanupMarker(), readMarker: localState.cleanupMarker, markerPrepared: prepared)
    }
}

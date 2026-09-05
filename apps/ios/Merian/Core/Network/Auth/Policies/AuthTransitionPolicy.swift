import Foundation

@MainActor
enum AuthTransitionPolicy {
    static func allowsAuthTransitionDuringAccountDeletionRecovery(
        recoveryState: AccountDeletionLocalRecoveryState,
        kind: AuthTransitionKind
    ) -> Bool {
        switch (recoveryState, kind) {
        case (.intakePending, .accountDeletion),
             (.capabilityPreparationPending, .accountDeletion),
             (.capabilityPreparedPending, .accountDeletion),
             (.capabilityIntakePending, .accountDeletion),
             (.cleanupPending, .accountDeletionCleanup),
             (.capabilityCleanupPending, .accountDeletionCleanup),
             (.capabilityRetirementPending, .accountDeletionCleanup),
             (.capabilityRejectionRetirementPending,
              .accountDeletionCleanup),
             (.capabilityLookupPending, .accountDeletionCleanup):
            return true
        default:
            return false
        }
    }

    static func allowsAuthenticatedRequest(
        activeTransition: AuthTransitionToken?,
        requestOwner: AuthTransitionToken?,
        accountDeletionCleanupPending: Bool
    ) -> Bool {
        if accountDeletionCleanupPending {
            // The only network call allowed behind the durable deletion fence
            // is an exact-owner replay of the idempotent intake. Accepted local
            // cleanup never owns `.accountDeletion` and therefore stays fully
            // offline.
            guard let activeTransition,
                  activeTransition.kind == .accountDeletion else {
                return false
            }
            return requestOwner == activeTransition
        }
        if let activeTransition {
            return requestOwner == activeTransition
        }
        return requestOwner == nil
    }

    static func shouldDeferAuthListenerSideEffects(
        hasActiveTransition: Bool,
        accountDeletionCleanupPending: Bool
    ) -> Bool {
        hasActiveTransition || accountDeletionCleanupPending
    }

    static func shouldAcceptAppleSignInCallback(
        activeTransitionID: UUID?,
        attemptTransitionID: UUID,
        controllerMatches: Bool
    ) -> Bool {
        controllerMatches && activeTransitionID == attemptTransitionID
    }

    static func shouldClearOAuthSessionAfterFailure(
        observedSessionMutation: Bool,
        sourceSession: AuthTransitionSession?,
        currentSession: AuthTransitionSession?
    ) -> Bool {
        observedSessionMutation || sourceSession != currentSession
    }

    static func allowsOAuthMetadataMutation(
        transitionIsCurrent: Bool,
        transitionExpectedUserID: UUID?,
        currentSessionUserID: UUID?,
        expectedUserID: UUID,
        updatedUserID: UUID? = nil
    ) -> Bool {
        transitionIsCurrent
            && transitionExpectedUserID == expectedUserID
            && currentSessionUserID == expectedUserID
            && (updatedUserID.map { $0 == expectedUserID } ?? true)
    }

    static func acceptsAuthenticationCallbackTarget(
        sourceSession: AuthTransitionSession?,
        targetSession: AuthTransitionSession
    ) -> Bool {
        guard let sourceSession else { return true }
        return !sourceSession.isAnonymous
            && sourceSession.userID == targetSession.userID
            && !targetSession.isAnonymous
    }

    static func authSessionAdoption(
        userId: UUID?,
        isExpired: Bool
    ) -> AuthSessionAdoption {
        guard let userId else { return .signedOut }
        if isExpired {
            return .awaitingRefresh(userId: userId)
        }
        return .authenticated(userId: userId)
    }

    static func shouldDeferExternalIdentityLink(
        purchaseIdentityHandoffPending: Bool
    ) -> Bool {
        purchaseIdentityHandoffPending
    }

    nonisolated static func shouldRestoreSourceIdentityAfterFailedSignOut(
        activeUserId: UUID?,
        activeUserIsAnonymous: Bool,
        sourceUserId: UUID,
        purchaseContinuityPending: Bool
    ) -> Bool {
        activeUserId == sourceUserId
            && !activeUserIsAnonymous
            && !purchaseContinuityPending
    }
}

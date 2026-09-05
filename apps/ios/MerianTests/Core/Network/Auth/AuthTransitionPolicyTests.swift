import Foundation
@testable import Merian
import XCTest

@MainActor
final class AuthTransitionPolicyTests: XCTestCase {
    func testAuthSessionAdoptionDistinguishesRefreshFromSignOut() {
        let userId = UUID()

        XCTAssertEqual(
            AuthTransitionPolicy.authSessionAdoption(
                userId: userId,
                isExpired: true
            ),
            .awaitingRefresh(userId: userId)
        )
        XCTAssertEqual(
            AuthTransitionPolicy.authSessionAdoption(
                userId: userId,
                isExpired: false
            ),
            .authenticated(userId: userId)
        )
        XCTAssertEqual(
            AuthTransitionPolicy.authSessionAdoption(
                userId: nil,
                isExpired: false
            ),
            .signedOut
        )
    }

    func testAppleCallbackRequiresMatchingControllerAndTransition() {
        let transitionID = UUID()

        XCTAssertTrue(
            AuthTransitionPolicy.shouldAcceptAppleSignInCallback(
                activeTransitionID: transitionID,
                attemptTransitionID: transitionID,
                controllerMatches: true
            )
        )
        XCTAssertFalse(
            AuthTransitionPolicy.shouldAcceptAppleSignInCallback(
                activeTransitionID: UUID(),
                attemptTransitionID: transitionID,
                controllerMatches: true
            )
        )
        XCTAssertFalse(
            AuthTransitionPolicy.shouldAcceptAppleSignInCallback(
                activeTransitionID: transitionID,
                attemptTransitionID: transitionID,
                controllerMatches: false
            )
        )
    }

    func testOAuthFailureClearsOnlyAChangedOrObservedSession() {
        let source = AuthTransitionSession(
            userID: UUID(),
            isAnonymous: true
        )
        XCTAssertFalse(
            AuthTransitionPolicy.shouldClearOAuthSessionAfterFailure(
                observedSessionMutation: false,
                sourceSession: source,
                currentSession: source
            )
        )
        XCTAssertTrue(
            AuthTransitionPolicy.shouldClearOAuthSessionAfterFailure(
                observedSessionMutation: true,
                sourceSession: source,
                currentSession: source
            )
        )
        XCTAssertTrue(
            AuthTransitionPolicy.shouldClearOAuthSessionAfterFailure(
                observedSessionMutation: false,
                sourceSession: source,
                currentSession: AuthTransitionSession(
                    userID: source.userID,
                    isAnonymous: false
                )
            )
        )
        XCTAssertTrue(
            AuthTransitionPolicy.shouldClearOAuthSessionAfterFailure(
                observedSessionMutation: false,
                sourceSession: source,
                currentSession: nil
            )
        )
    }

    func testOAuthMetadataMutationRequiresTheExactTransitionSessionBeforeAndAfterUpdate() {
        let expectedUserID = UUID()
        let otherUserID = UUID()

        XCTAssertTrue(
            AuthTransitionPolicy.allowsOAuthMetadataMutation(
                transitionIsCurrent: true,
                transitionExpectedUserID: expectedUserID,
                currentSessionUserID: expectedUserID,
                expectedUserID: expectedUserID,
                updatedUserID: expectedUserID
            )
        )
        for allowed in [
            AuthTransitionPolicy.allowsOAuthMetadataMutation(
                transitionIsCurrent: false,
                transitionExpectedUserID: expectedUserID,
                currentSessionUserID: expectedUserID,
                expectedUserID: expectedUserID
            ),
            AuthTransitionPolicy.allowsOAuthMetadataMutation(
                transitionIsCurrent: true,
                transitionExpectedUserID: otherUserID,
                currentSessionUserID: expectedUserID,
                expectedUserID: expectedUserID
            ),
            AuthTransitionPolicy.allowsOAuthMetadataMutation(
                transitionIsCurrent: true,
                transitionExpectedUserID: expectedUserID,
                currentSessionUserID: otherUserID,
                expectedUserID: expectedUserID
            ),
            AuthTransitionPolicy.allowsOAuthMetadataMutation(
                transitionIsCurrent: true,
                transitionExpectedUserID: expectedUserID,
                currentSessionUserID: expectedUserID,
                expectedUserID: expectedUserID,
                updatedUserID: otherUserID
            )
        ] {
            XCTAssertFalse(allowed)
        }
    }

    func testActiveTransitionOwnsListenerSideEffectsAndAuthenticatedRequests() {
        let active = AuthTransitionToken(
            id: UUID(),
            kind: .oauth(.apple)
        )
        let stale = AuthTransitionToken(
            id: UUID(),
            kind: .recovery
        )

        XCTAssertTrue(
            AuthTransitionPolicy.shouldDeferAuthListenerSideEffects(
                hasActiveTransition: true,
                accountDeletionCleanupPending: false
            )
        )
        XCTAssertTrue(
            AuthTransitionPolicy.shouldDeferAuthListenerSideEffects(
                hasActiveTransition: false,
                accountDeletionCleanupPending: true
            )
        )
        XCTAssertFalse(
            AuthTransitionPolicy.shouldDeferAuthListenerSideEffects(
                hasActiveTransition: false,
                accountDeletionCleanupPending: false
            )
        )
        XCTAssertTrue(
            AuthTransitionPolicy.allowsAuthenticatedRequest(
                activeTransition: active,
                requestOwner: active,
                accountDeletionCleanupPending: false
            )
        )
        XCTAssertFalse(
            AuthTransitionPolicy.allowsAuthenticatedRequest(
                activeTransition: active,
                requestOwner: nil,
                accountDeletionCleanupPending: false
            )
        )
        XCTAssertFalse(
            AuthTransitionPolicy.allowsAuthenticatedRequest(
                activeTransition: active,
                requestOwner: stale,
                accountDeletionCleanupPending: false
            )
        )
        XCTAssertFalse(
            AuthTransitionPolicy.allowsAuthenticatedRequest(
                activeTransition: nil,
                requestOwner: nil,
                accountDeletionCleanupPending: true
            )
        )
        let deletion = AuthTransitionToken(
            id: UUID(),
            kind: .accountDeletion
        )
        XCTAssertTrue(
            AuthTransitionPolicy.allowsAuthenticatedRequest(
                activeTransition: deletion,
                requestOwner: deletion,
                accountDeletionCleanupPending: true
            )
        )
        XCTAssertFalse(
            AuthTransitionPolicy.allowsAuthenticatedRequest(
                activeTransition: deletion,
                requestOwner: nil,
                accountDeletionCleanupPending: true
            )
        )
        let cleanup = AuthTransitionToken(
            id: UUID(),
            kind: .accountDeletionCleanup
        )
        XCTAssertFalse(
            AuthTransitionPolicy.allowsAuthenticatedRequest(
                activeTransition: cleanup,
                requestOwner: cleanup,
                accountDeletionCleanupPending: true
            )
        )
    }

    func testFallbackAuthenticationCallbackNeverReplacesAnAnonymousOrDifferentAccount() {
        let linkedUserID = UUID()
        let linked = AuthTransitionSession(
            userID: linkedUserID,
            isAnonymous: false
        )

        XCTAssertTrue(
            AuthTransitionPolicy.acceptsAuthenticationCallbackTarget(
                sourceSession: nil,
                targetSession: linked
            )
        )
        XCTAssertTrue(
            AuthTransitionPolicy.acceptsAuthenticationCallbackTarget(
                sourceSession: linked,
                targetSession: linked
            )
        )
        XCTAssertFalse(
            AuthTransitionPolicy.acceptsAuthenticationCallbackTarget(
                sourceSession: AuthTransitionSession(
                    userID: UUID(),
                    isAnonymous: true
                ),
                targetSession: linked
            )
        )
        XCTAssertFalse(
            AuthTransitionPolicy.acceptsAuthenticationCallbackTarget(
                sourceSession: linked,
                targetSession: AuthTransitionSession(
                    userID: UUID(),
                    isAnonymous: false
                )
            )
        )
    }

    func testEveryDeletionRecoveryPhaseAdmitsOnlyItsOwnedTransition() {
        let intakeStates: [AccountDeletionLocalRecoveryState] = [
            .intakePending,
            .capabilityPreparationPending,
            .capabilityPreparedPending,
            .capabilityIntakePending
        ]
        for state in intakeStates {
            XCTAssertTrue(
                AuthTransitionPolicy
                    .allowsAuthTransitionDuringAccountDeletionRecovery(
                        recoveryState: state,
                        kind: .accountDeletion
                    )
            )
            XCTAssertFalse(
                AuthTransitionPolicy
                    .allowsAuthTransitionDuringAccountDeletionRecovery(
                        recoveryState: state,
                        kind: .accountDeletionCleanup
                    )
            )
        }

        let cleanupStates: [AccountDeletionLocalRecoveryState] = [
            .cleanupPending,
            .capabilityCleanupPending,
            .capabilityRetirementPending,
            .capabilityRejectionRetirementPending,
            .capabilityLookupPending
        ]
        for state in cleanupStates {
            XCTAssertTrue(
                AuthTransitionPolicy
                    .allowsAuthTransitionDuringAccountDeletionRecovery(
                        recoveryState: state,
                        kind: .accountDeletionCleanup
                    )
            )
            XCTAssertFalse(
                AuthTransitionPolicy
                    .allowsAuthTransitionDuringAccountDeletionRecovery(
                        recoveryState: state,
                        kind: .accountDeletion
                    )
            )
        }

        XCTAssertFalse(
            AuthTransitionPolicy
                .allowsAuthTransitionDuringAccountDeletionRecovery(
                    recoveryState: .capabilityLookupPending,
                    kind: .oauth(.apple)
                )
        )
        XCTAssertFalse(
            AuthTransitionPolicy
                .allowsAuthTransitionDuringAccountDeletionRecovery(
                    recoveryState: .capabilityCleanupPending,
                    kind: .signOut
                )
        )
    }

    func testEveryExternalIdentityLinkWaitsForPurchaseHandoffBinding() {
        XCTAssertTrue(
            AuthTransitionPolicy.shouldDeferExternalIdentityLink(
                purchaseIdentityHandoffPending: true
            )
        )
        XCTAssertFalse(
            AuthTransitionPolicy.shouldDeferExternalIdentityLink(
                purchaseIdentityHandoffPending: false
            )
        )
    }

    func testFailedSignOutRestoresOnlyTheExactUnfencedSourceAccount() {
        let sourceUserID = UUID()

        XCTAssertTrue(
            AuthTransitionPolicy.shouldRestoreSourceIdentityAfterFailedSignOut(
                activeUserId: sourceUserID,
                activeUserIsAnonymous: false,
                sourceUserId: sourceUserID,
                purchaseContinuityPending: false
            )
        )
        XCTAssertFalse(
            AuthTransitionPolicy.shouldRestoreSourceIdentityAfterFailedSignOut(
                activeUserId: UUID(),
                activeUserIsAnonymous: false,
                sourceUserId: sourceUserID,
                purchaseContinuityPending: false
            )
        )
        XCTAssertFalse(
            AuthTransitionPolicy.shouldRestoreSourceIdentityAfterFailedSignOut(
                activeUserId: sourceUserID,
                activeUserIsAnonymous: true,
                sourceUserId: sourceUserID,
                purchaseContinuityPending: false
            )
        )
        XCTAssertFalse(
            AuthTransitionPolicy.shouldRestoreSourceIdentityAfterFailedSignOut(
                activeUserId: sourceUserID,
                activeUserIsAnonymous: false,
                sourceUserId: sourceUserID,
                purchaseContinuityPending: true
            )
        )
        XCTAssertFalse(
            AuthTransitionPolicy.shouldRestoreSourceIdentityAfterFailedSignOut(
                activeUserId: nil,
                activeUserIsAnonymous: false,
                sourceUserId: sourceUserID,
                purchaseContinuityPending: false
            )
        )
    }

    func testNilSessionAndOwnerlessPolicyBoundariesRemainExplicit() {
        let owner = AuthTransitionToken(
            id: UUID(),
            kind: .oauth(.apple)
        )
        let userID = UUID()
        let permanentSession = AuthTransitionSession(
            userID: userID,
            isAnonymous: false
        )

        XCTAssertEqual(
            AuthTransitionPolicy.authSessionAdoption(
                userId: nil,
                isExpired: true
            ),
            .signedOut
        )
        XCTAssertFalse(
            AuthTransitionPolicy.shouldAcceptAppleSignInCallback(
                activeTransitionID: nil,
                attemptTransitionID: owner.id,
                controllerMatches: true
            )
        )
        XCTAssertFalse(
            AuthTransitionPolicy.shouldClearOAuthSessionAfterFailure(
                observedSessionMutation: false,
                sourceSession: nil,
                currentSession: nil
            )
        )
        XCTAssertTrue(
            AuthTransitionPolicy.shouldClearOAuthSessionAfterFailure(
                observedSessionMutation: false,
                sourceSession: nil,
                currentSession: permanentSession
            )
        )
        XCTAssertTrue(
            AuthTransitionPolicy.allowsOAuthMetadataMutation(
                transitionIsCurrent: true,
                transitionExpectedUserID: userID,
                currentSessionUserID: userID,
                expectedUserID: userID
            )
        )
        XCTAssertFalse(
            AuthTransitionPolicy.allowsOAuthMetadataMutation(
                transitionIsCurrent: true,
                transitionExpectedUserID: nil,
                currentSessionUserID: userID,
                expectedUserID: userID
            )
        )
        XCTAssertFalse(
            AuthTransitionPolicy.acceptsAuthenticationCallbackTarget(
                sourceSession: AuthTransitionSession(
                    userID: userID,
                    isAnonymous: true
                ),
                targetSession: permanentSession
            )
        )
        XCTAssertFalse(
            AuthTransitionPolicy.acceptsAuthenticationCallbackTarget(
                sourceSession: permanentSession,
                targetSession: AuthTransitionSession(
                    userID: userID,
                    isAnonymous: true
                )
            )
        )
        XCTAssertTrue(
            AuthTransitionPolicy.shouldDeferAuthListenerSideEffects(
                hasActiveTransition: true,
                accountDeletionCleanupPending: true
            )
        )
        XCTAssertTrue(
            AuthTransitionPolicy.allowsAuthenticatedRequest(
                activeTransition: nil,
                requestOwner: nil,
                accountDeletionCleanupPending: false
            )
        )
        XCTAssertFalse(
            AuthTransitionPolicy.allowsAuthenticatedRequest(
                activeTransition: nil,
                requestOwner: owner,
                accountDeletionCleanupPending: false
            )
        )
        XCTAssertFalse(
            AuthTransitionPolicy.allowsAuthenticatedRequest(
                activeTransition: owner,
                requestOwner: owner,
                accountDeletionCleanupPending: true
            )
        )
    }
}

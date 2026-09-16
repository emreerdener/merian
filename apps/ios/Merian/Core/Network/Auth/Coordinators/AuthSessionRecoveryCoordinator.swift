import Foundation

/// Owns Auth-session refresh, anonymous replay recovery, and terminal local
/// cleanup sequencing. Live provider and persistence effects are injected by
/// the Auth facade.
@MainActor
struct AuthSessionRecoveryCoordinator {
    private let dependencies: AuthSessionRecoveryDependencies

    init(dependencies: AuthSessionRecoveryDependencies) {
        self.dependencies = dependencies
    }

    /// Refreshes the stable active session after a rejected authenticated
    /// request. This path owns and finishes its recovery transition.
    func refreshActiveSessionForRetry() async -> Bool {
        guard !Task.isCancelled,
              let transition = dependencies.transition.beginRecovery() else {
            return false
        }
        defer { dependencies.transition.finish(transition) }
        return await refreshActiveSession(ownedBy: transition)
    }

    /// Refreshes a request whose existing caller already owns the active Auth
    /// transition, without relinking purchase or author state.
    func refreshExpectedSessionForAuthenticatedRequest(
        ownedBy transition: AuthTransitionToken
    ) async -> Bool {
        guard !Task.isCancelled,
              dependencies.transition.owns(transition),
              let expected = dependencies.transition.expectedSession(
                transition
              ) else {
            return false
        }
        guard await dependencies.transition.awaitAccountWorkQuiescence(),
              !Task.isCancelled,
              dependencies.transition.owns(transition),
              dependencies.transition.expectedSession(transition)
                == expected else {
            return false
        }

        do {
            let session = try await dependencies.operations.refreshSDKSession()
            guard !Task.isCancelled,
                  dependencies.transition.owns(transition),
                  session.identity == expected,
                  session.adopt(transition),
                  dependencies.transition.currentSessionMatches(
                    transition
                  ) else {
                return false
            }
            session.publish()
            dependencies.diagnose(.transitionOwnedRefreshSucceeded, nil)
            return true
        } catch is CancellationError {
            return false
        } catch {
            dependencies.diagnose(.transitionOwnedRefreshFailed, error)
            return false
        }
    }

    /// Replaces a broken anonymous identity and restores purchase and
    /// entitlement readiness before request replay is allowed.
    func resetGhostSessionForRetry() async -> Bool {
        guard !Task.isCancelled,
              let transition = dependencies.transition.beginRecovery() else {
            return false
        }
        defer { dependencies.transition.finish(transition) }

        guard !dependencies.state.hasPendingPurchaseIdentityHandoff() else {
            dependencies.diagnose(
                .anonymousResetBlockedByPurchaseHandoff,
                nil
            )
            return false
        }
        guard await dependencies.operations.resetAnonymousSession(transition),
              !Task.isCancelled,
              dependencies.transition.owns(transition) else {
            return false
        }

        do {
            let session = try await dependencies.operations.loadSDKSession()
            try Task.checkCancellation()
            await session.ensurePurchaseIdentityReady(transition)
            try Task.checkCancellation()
            guard session.identity.isAnonymous,
                  dependencies.transition.currentSessionMatches(transition),
                  session.purchaseIdentityIsReady() else {
                dependencies.diagnose(
                    .anonymousResetPurchaseIdentityNotReady,
                    nil
                )
                return false
            }
            guard await session.beginEntitlementSession(transition) else {
                throw SupabaseAuthTransitionError
                    .signOutPurchaseContinuityPending
            }
            try Task.checkCancellation()
            guard dependencies.transition.currentSessionMatches(transition)
            else {
                return false
            }
            let verifiedSession = try await dependencies.operations
                .loadSDKSession()
            try Task.checkCancellation()
            guard verifiedSession.identity == session.identity,
                  session.isPublishedAtCapturedGeneration(),
                  dependencies.transition.currentSessionMatches(transition)
            else {
                return false
            }
            session.publish()
            dependencies.diagnose(.anonymousResetSucceeded, nil)
            return true
        } catch is CancellationError {
            return false
        } catch {
            dependencies.diagnose(.anonymousResetFailed, error)
            return false
        }
    }

    /// Begins and owns terminal local cleanup after an unrecoverable Auth
    /// failure.
    @discardableResult
    func clearLocalSessionAfterAuthFailure() async
        -> AuthSessionLocalClearOutcome {
        guard !Task.isCancelled,
              let transition = dependencies.transition.beginRecovery() else {
            return .rejected
        }
        defer { dependencies.transition.finish(transition) }
        return await clearLocalSessionAfterAuthFailure(ownedBy: transition)
    }

    /// Performs cleanup for a caller that already owns the active transition.
    /// Once SDK sign-out begins, the coordinator invokes every local and
    /// purchase-identity cleanup step even if cancellation arrives.
    @discardableResult
    func clearLocalSessionAfterAuthFailure(
        ownedBy transition: AuthTransitionToken,
        entryPolicy: AuthSessionRecoveryEntryPolicy = .requireActiveCaller
    ) async -> AuthSessionLocalClearOutcome {
        guard entryPolicy.permitsEntry(isCancelled: Task.isCancelled),
              dependencies.transition.owns(transition) else {
            return .rejected
        }
        let expectedSession = dependencies.transition.expectedSession(
            transition
        )
        guard await dependencies.transition.awaitAccountWorkQuiescence(),
              entryPolicy.permitsEntry(isCancelled: Task.isCancelled),
              dependencies.transition.owns(transition),
              dependencies.transition.expectedSession(transition)
                == expectedSession,
              dependencies.transition.currentSessionMatches(transition) else {
            return .rejected
        }
        guard !dependencies.state.hasPendingPurchaseIdentityHandoff() else {
            dependencies.diagnose(
                .localClearBlockedByPurchaseHandoff,
                nil
            )
            return .blockedByPurchaseHandoff
        }

        dependencies.transition.updatePhase(
            transition,
            .installingSession
        )
        dependencies.transition.adoptSignedOutSession(transition)
        do {
            try await dependencies.operations.performLocalSDKSignOut()
        } catch {
            dependencies.diagnose(.localSDKSignOutFailed, error)
        }

        dependencies.state.clearLocalRecoveryState()
        await dependencies.operations.finishPurchaseIdentitySignOut()
        dependencies.diagnose(.localSessionCleared, nil)
        return .cleared
    }

    private func refreshActiveSession(
        ownedBy transition: AuthTransitionToken
    ) async -> Bool {
        guard !Task.isCancelled,
              dependencies.transition.owns(transition),
              !dependencies.state.isSigningOut(),
              let expected = dependencies.transition.expectedSession(
                transition
              ) else {
            return false
        }
        guard await dependencies.transition.awaitAccountWorkQuiescence(),
              !Task.isCancelled,
              dependencies.transition.owns(transition),
              !dependencies.state.isSigningOut(),
              dependencies.transition.expectedSession(transition)
                == expected else {
            return false
        }

        do {
            let session = try await dependencies.operations.refreshSDKSession()
            guard !Task.isCancelled,
                  dependencies.transition.owns(transition),
                  !dependencies.state.isSigningOut(),
                  session.identity == expected,
                  session.adopt(transition),
                  dependencies.transition.currentSessionMatches(
                    transition
                  ) else {
                return false
            }
            session.publish()
            session.schedulePublicAuthorIdentityRefresh()
            await session.ensurePurchaseIdentityReady(transition)
            guard !Task.isCancelled,
                  dependencies.transition.currentSessionMatches(
                    transition
                  ) else {
                return false
            }
            dependencies.diagnose(.ordinaryRefreshSucceeded, nil)
            return true
        } catch is CancellationError {
            return false
        } catch {
            dependencies.diagnose(.ordinaryRefreshFailed, error)
            return false
        }
    }
}

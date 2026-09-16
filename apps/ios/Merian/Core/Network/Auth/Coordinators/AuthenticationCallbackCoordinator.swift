import Foundation

/// Owns fallback Auth callback admission, session-installation sequencing, and
/// mutation-aware recovery. Live SDK and persistence effects remain injected by
/// `SupabaseManager`.
@MainActor
struct AuthenticationCallbackCoordinator {
    private let dependencies: AuthenticationCallbackDependencies

    init(dependencies: AuthenticationCallbackDependencies) {
        self.dependencies = dependencies
    }

    func handle() async {
        guard !dependencies.transition.hasPendingPurchaseIdentityHandoff(),
              let transition = dependencies.transition.begin() else {
            dependencies.diagnostics.report(.transitionRejected, nil)
            return
        }
        defer { dependencies.transition.finish(transition) }

        let sourceSession = dependencies.transition.sourceSession(transition)
        guard sourceSession?.isAnonymous != true,
              dependencies.transition.currentSessionMatches(transition) else {
            dependencies.diagnostics.report(.sourceSessionRejected, nil)
            return
        }

        var didInstallSession = false
        do {
            try await dependencies.transition
                .verifyExpectedSessionIfPresent(transition)
            try Task.checkCancellation()
            dependencies.transition.updatePhase(
                transition,
                .installingSession
            )
            let session = try await OAuthSignInWorkflow.replacingSession(
                suspendAnalytics: {
                    dependencies.session.analyticsGeneration(transition)
                },
                installSession: {
                    try await dependencies.session.installAndAdopt(
                        transition
                    ) {
                        didInstallSession = true
                    }
                },
                currentSession: {
                    dependencies.session.current()
                },
                reconcileSession: { _, installed, disposition in
                    reconcileReplacement(
                        installedSession: installed,
                        disposition: disposition,
                        sourceSession: sourceSession,
                        ownedBy: transition
                    )
                }
            )
            try Task.checkCancellation()
            guard dependencies.transition.owns(transition),
                  !dependencies.transition.isSignOutInProgress(),
                  AuthTransitionPolicy.acceptsAuthenticationCallbackTarget(
                      sourceSession: sourceSession,
                      targetSession: session.identity
                  ),
                  dependencies.transition.currentSessionMatches(transition)
            else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }

            session.publish()
            dependencies.transition.updatePhase(
                transition,
                .bindingPurchases
            )
            await session.ensurePurchaseIdentityReady(transition)
            try Task.checkCancellation()
            guard dependencies.transition.currentSessionMatches(transition),
                  session.purchaseIdentityIsReady() else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }

            await session.beginEntitlementSession(transition)
            try Task.checkCancellation()
            try await dependencies.transition.verifyExpectedSession(
                transition
            )
            try Task.checkCancellation()
            dependencies.transition.updatePhase(transition, .finalizing)
            dependencies.completion.markAuthenticatedOAuth(
                !session.identity.isAnonymous
            )
        } catch {
            if AuthTransitionPolicy.shouldClearOAuthSessionAfterFailure(
                observedSessionMutation: didInstallSession,
                sourceSession: sourceSession,
                currentSession: dependencies.session.current()?.identity
            ) {
                await dependencies.completion.clearMutatedSession(transition)
            }
            dependencies.diagnostics.report(.completionFailed, error)
        }
    }

    private func reconcileReplacement(
        installedSession: AuthenticationCallbackSession?,
        disposition: OAuthSessionReplacementDisposition,
        sourceSession: AuthTransitionSession?,
        ownedBy transition: AuthTransitionToken
    ) {
        guard dependencies.transition.owns(transition) else { return }
        let resolvedSession = dependencies.session.current()
            ?? installedSession
        let activeSession: AuthenticationCallbackSession?
        switch disposition {
        case .installed, .failed:
            activeSession =
                !dependencies.transition.isSignOutInProgress()
                && resolvedSession?.isExpired == false
                ? resolvedSession
                : nil
        case .cancelled:
            activeSession =
                !dependencies.transition.isSignOutInProgress()
                && resolvedSession?.isExpired == false
                && resolvedSession?.identity == sourceSession
                ? resolvedSession
                : nil
        }

        if let activeSession {
            activeSession.publish()
        } else {
            dependencies.session.clearPublishedSession()
        }
    }
}

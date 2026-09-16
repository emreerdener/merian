import Foundation

/// Owns provider-neutral Auth-event projection and restored-session recovery
/// ordering. `AuthSessionLifecycleLiveProvider` owns the Supabase stream,
/// SDK-value adaptation, and listener task; the facade supplies live effects.
@MainActor
struct AuthSessionLifecycleCoordinator {
    private let dependencies: AuthSessionLifecycleDependencies

    init(dependencies: AuthSessionLifecycleDependencies) {
        self.dependencies = dependencies
    }

    func handle(_ event: AuthSessionLifecycleEvent) async {
        let deletionCleanupPending =
            dependencies.state.accountDeletionCleanupPending()
        if deletionCleanupPending {
            publishDeletionBarrier()
            dependencies.diagnose(
                .deferredForAccountDeletionCleanup,
                nil
            )
            return
        }

        if AuthTransitionPolicy.shouldDeferAuthListenerSideEffects(
            hasActiveTransition: dependencies.state.hasActiveTransition(),
            accountDeletionCleanupPending: deletionCleanupPending
        ) {
            dependencies.diagnose(.deferredForActiveTransition, nil)
            return
        }

        synchronizeDurableFences()

        switch event.adoption {
        case .authenticated(let userID):
            guard let session = event.session,
                  session.userID == userID else {
                dependencies.diagnose(.invalidEvent, nil)
                return
            }
            guard await handleAuthenticatedSession(
                session,
                event: event
            ) else { return }
        case .awaitingRefresh(let userID):
            guard event.session?.userID == userID else {
                dependencies.diagnose(.invalidEvent, nil)
                return
            }
            guard !dependencies.state.isSigningOut() else {
                dependencies.diagnose(
                    .refreshEventIgnoredDuringSignOut,
                    nil
                )
                return
            }
            publishAwaitingRefresh(userID, origin: event.origin)
            dependencies.diagnose(.cachedSessionAwaitingRefresh, nil)
        case .signedOut:
            guard event.session == nil else {
                dependencies.diagnose(.invalidEvent, nil)
                return
            }
            publishSignedOut(origin: event.origin)
            await dependencies.identity.handleSupabaseSignOut()
            guard !Task.isCancelled,
                  dependencies.state.isCurrentLifecycleSession(
                      nil,
                      event.authGeneration
                  ) else {
                return
            }
            finishSignedOutPublication()
        }

        dependencies.diagnose(.processed, nil)
    }

    private func synchronizeDurableFences() {
        do {
            let hasPendingMerge = try dependencies.durability
                .hasPendingGhostProfileMerge()
            dependencies.durability
                .setAnalyticsSuppressedForGhostHandoff(hasPendingMerge)
        } catch {
            dependencies.durability
                .setAnalyticsSuppressedForGhostHandoff(true)
            dependencies.diagnose(
                .ghostProfileMergeStateUnreadable,
                error
            )
        }

        do {
            let hasPendingHandoff = try dependencies.durability
                .hasPendingPurchaseIdentityHandoff()
            dependencies.durability.setPurchaseIdentityHandoffPending(
                hasPendingHandoff
            )
        } catch {
            dependencies.durability.setPurchaseIdentityHandoffPending(true)
            dependencies.diagnose(
                .purchaseHandoffStateUnreadable,
                error
            )
        }
    }

    private func publishDeletionBarrier() {
        dependencies.state.clearPublishedSession()
        dependencies.state.clearPurchasePrincipalBinding()
        dependencies.state.beginPurchaseIdentityResolution()
        dependencies.identity.clearEntitlementSession()
    }

    private func publishAwaitingRefresh(
        _ userID: UUID,
        origin: AuthSessionLifecycleOrigin
    ) {
        dependencies.state.clearPublishedSession()
        dependencies.state.clearPurchasePrincipalBinding()
        dependencies.state.beginPurchaseIdentityResolution()
        dependencies.state.beginAccountSession(userID, origin)
        dependencies.state.observeConsentSession(userID)
    }

    private func publishSignedOut(origin: AuthSessionLifecycleOrigin) {
        dependencies.state.clearPublishedSession()
        dependencies.state.clearPurchasePrincipalBinding()
        dependencies.state.beginAccountSession(nil, origin)
        dependencies.state.observeConsentSession(nil)
    }

    private func finishSignedOutPublication() {
        dependencies.state.clearLinkedUser()
        dependencies.state.clearPublicAuthorIdentityRefreshMarker()
        dependencies.state.cancelPublicAuthorIdentityRefresh()
        dependencies.state.cancelAppleCredentialRevocation()
        dependencies.state.cancelGhostProfileMerge()
    }

    private func handleAuthenticatedSession(
        _ session: AuthTransitionSession,
        event: AuthSessionLifecycleEvent
    ) async -> Bool {
        guard !dependencies.state.isSigningOut() else {
            dependencies.diagnose(
                .authenticatedEventIgnoredDuringSignOut,
                nil
            )
            return false
        }
        if dependencies.state.publishedSession() != session {
            dependencies.state.clearPurchasePrincipalBinding()
            dependencies.state.clearLinkedUser()
            dependencies.state.beginPurchaseIdentityResolution()
            dependencies.identity.clearEntitlementSession()
        }
        guard dependencies.state.publishSDKSession(session) else {
            dependencies.diagnose(.invalidEvent, nil)
            return false
        }
        dependencies.state.beginAccountSession(session.userID, event.origin)
        dependencies.state.observeConsentSession(session.userID)
        dependencies.state.schedulePublicAuthorIdentityRefresh(session)

        var didLinkExternalIdentity = false
        if !dependencies.identity.isTestExecution() {
            if session.isAnonymous,
               dependencies.identity.isPurchaseIdentityHandoffPending() {
                await dependencies.identity
                    .completePendingPurchaseIdentityHandoff(
                        session,
                        event.authGeneration
                    )
            } else {
                didLinkExternalIdentity = await dependencies.identity
                    .ensureTelemetryLinked(session)
            }

            if !session.isAnonymous,
               dependencies.identity.isPurchaseIdentityHandoffPending(),
               !dependencies.state.isUserSignOutTransitionInProgress() {
                await dependencies.identity
                    .abandonRestoredSourceHandoffs(session)
                if !dependencies.identity
                    .isPurchaseIdentityHandoffPending() {
                    didLinkExternalIdentity = await dependencies.identity
                        .ensureTelemetryLinked(session)
                }
            }
        }

        guard dependencies.state.isCurrentPublishedSession(
            session,
            event.authGeneration
        ) else { return false }

        if dependencies.identity.isPurchaseIdentityHandoffPending() {
            dependencies.identity.clearEntitlementSession()
        } else {
            await dependencies.identity.beginEntitlementSession(session)
        }

        guard dependencies.state.isCurrentPublishedSession(
            session,
            event.authGeneration
        ) else { return false }

        if didLinkExternalIdentity {
            dependencies.identity.scheduleHistoricalSync(
                session,
                event.authGeneration
            )
        }
        return true
    }
}

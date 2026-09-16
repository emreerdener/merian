import Foundation

/// Repairs purchase and entitlement readiness for the exact foreground Auth
/// session while one account-work lease prevents identity replacement.
@MainActor
struct PurchaseIdentityReadinessCoordinator {
    let sessionCoordinator: PurchaseIdentitySessionCoordinator
    let dependencies: PurchaseIdentitySessionDependencies

    func repair() async -> Bool {
        guard !dependencies.state.isTestExecution(),
              !dependencies.state.accountDeletionCleanupPending(),
              !dependencies.state.isSigningOut(),
              dependencies.state.isAuthenticated(),
              let context = dependencies.state.currentPublishedSession(),
              let lease = dependencies.state.beginAccountWork(
                  context.userID
              ) else {
            return false
        }
        defer { lease.finish() }

        let snapshot: PurchaseIdentitySessionSnapshot
        do {
            snapshot = try await dependencies.state.loadSDKSession()
        } catch {
            return false
        }
        guard !snapshot.isExpired,
              snapshot.matches(context),
              lease.isCurrent(),
              dependencies.state.isCurrentPublishedSession(context) else {
            return false
        }

        var handoffPending: Bool
        do {
            handoffPending = try dependencies.handoff
                .loadAndPublishPendingState()
        } catch {
            dependencies.handoff.setPending(true)
            return false
        }

        if context.isAnonymous, handoffPending {
            return await dependencies.handoff.completePending(context)
        }

        if !context.isAnonymous,
           handoffPending,
           !dependencies.state.isUserSignOutTransitionInProgress() {
            await dependencies.handoff.abandonRestoredSource(context)
            do {
                handoffPending = try dependencies.handoff
                    .loadAndPublishPendingState()
            } catch {
                dependencies.handoff.setPending(true)
                return false
            }
            guard !handoffPending else { return false }
        }

        let providerWasAlreadyReady =
            sessionCoordinator.activeBinding != nil
            && dependencies.provider.currentState().matches(context)
        if !providerWasAlreadyReady {
            _ = await sessionCoordinator.ensureIdentity(
                for: snapshot,
                context: context,
                isAdmissionCurrent: lease.isCurrent,
                dependencies: dependencies
            )
        }

        guard dependencies.state.isCurrentPublishedSession(context),
              sessionCoordinator.activeBinding != nil,
              dependencies.provider.currentState().matches(context) else {
            return false
        }

        let entitlementIsReady: Bool
        if dependencies.entitlement.isReady(context.userID) {
            entitlementIsReady = true
        } else {
            entitlementIsReady = await dependencies.entitlement.beginSession(
                context.userID
            )
        }
        guard entitlementIsReady, lease.isCurrent() else { return false }

        guard let verifiedSnapshot = try? await dependencies.state
            .loadSDKSession(),
            !verifiedSnapshot.isExpired,
            verifiedSnapshot.matches(context),
            dependencies.state.isCurrentPublishedSession(context),
            dependencies.provider.currentState().matches(context) else {
            return false
        }
        return true
    }
}

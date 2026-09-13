import Foundation

extension ConsentCloudSessionCoordinator.Dependencies {
    @MainActor
    static let live = Self(
        isRunningTests: {
            TestExecutionCoordinator.isRunningTests
        },
        isAuthenticated: {
            SupabaseManager.shared.isAuthenticated
        },
        initializeGhostSession: {
            await SupabaseManager.shared.initializeGhostSession() != nil
        },
        beginUnownedAccountBoundWork: {
            try SupabaseManager.shared.beginUnownedAccountBoundWork()
        },
        finishAccountBoundWork: { lease in
            SupabaseManager.shared.finishAccountBoundWork(lease)
        },
        isAccountBoundWorkLeaseCurrent: { lease in
            SupabaseManager.shared.isAccountBoundWorkLeaseCurrent(lease)
        },
        currentSession: {
            let user = try await SupabaseManager.shared.client.auth.session.user
            return AuthTransitionSession(
                userID: user.id,
                isAnonymous: user.isAnonymous
            )
        },
        currentSDKUserId: {
            SupabaseManager.shared.client.auth.currentSession?.user.id
        },
        currentObservedUserId: {
            SupabaseManager.shared.currentUser?.id
        },
        isAuthTransitionInProgress: {
            SupabaseManager.shared.isAuthTransitionInProgress
        },
        isAccountDeletionCleanupPending: {
            AccountDeletionLocalCleanupStore.isPending()
        },
        currentSessionMatchesAuthTransition: { transition in
            SupabaseManager.shared
                .currentSessionMatchesAuthTransition(transition)
        },
        reportReapprovalPersistenceFailure: { error in
            MerianLog.auth.error(
                "Required consent reapproval could not be persisted; the in-memory gate remains closed; kind=\(MerianLog.errorKind(error), privacy: .public)."
            )
        }
    )
}

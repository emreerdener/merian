import Foundation

@MainActor
final class ConsentCloudSessionCoordinator {
    struct Dependencies {
        let isRunningTests: @MainActor () -> Bool
        let isAuthenticated: @MainActor () -> Bool
        let initializeGhostSession: @MainActor () async -> Bool
        let beginUnownedAccountBoundWork: @MainActor () throws
            -> AccountBoundWorkLease
        let finishAccountBoundWork: @MainActor (AccountBoundWorkLease) -> Void
        let isAccountBoundWorkLeaseCurrent: @MainActor (
            AccountBoundWorkLease
        ) -> Bool
        let currentSession: @MainActor () async throws
            -> AuthTransitionSession
        let currentSDKUserId: @MainActor () -> UUID?
        let currentObservedUserId: @MainActor () -> UUID?
        let isAuthTransitionInProgress: @MainActor () -> Bool
        let isAccountDeletionCleanupPending: @MainActor () -> Bool
        let currentSessionMatchesAuthTransition: @MainActor (
            AuthTransitionToken
        ) -> Bool
        let reportReapprovalPersistenceFailure: @MainActor (Error) -> Void
    }

    private let ledgerRepository: ConsentLedgerRepository
    private let synchronizationCoordinator: ConsentSynchronizationCoordinator
    private let dependencies: Dependencies

    init(
        ledgerRepository: ConsentLedgerRepository,
        synchronizationCoordinator: ConsentSynchronizationCoordinator,
        dependencies: Dependencies
    ) {
        self.ledgerRepository = ledgerRepository
        self.synchronizationCoordinator = synchronizationCoordinator
        self.dependencies = dependencies
    }

    func rebindAndSynchronizeGhostEvidence(
        from ghostUserId: UUID,
        to permanentUserId: UUID,
        manager: ConsentManager
    ) async throws {
        manager.setAnalyticsSuppressedForGhostHandoff(true)
        try Task.checkCancellation()

        let session = try await dependencies.currentSession()
        try Task.checkCancellation()
        guard !session.isAnonymous,
              session.userID == permanentUserId,
              manager.currentSessionUserId == permanentUserId,
              dependencies.currentObservedUserId() == permanentUserId else {
            throw ConsentHandoffError.activeAccountChanged
        }
        manager.prepareForGhostEvidenceRebind()

        try ledgerRepository.rebindPendingAnalyticsRevocationJournal(
            from: ghostUserId,
            to: permanentUserId
        )
        do {
            try ledgerRepository.rebindLedger(
                from: ghostUserId,
                to: permanentUserId
            )
        } catch {
            throw ConsentHandoffError.ledgerPersistenceFailed
        }
        if ledgerRepository.hasPendingAnalyticsRevocationJournal {
            try ledgerRepository.recoverPendingAnalyticsRevocation()
        }
        manager.applyAnalyticsPermissionToSDK()

        try await manager.synchronize(for: permanentUserId)
        let finalSession = try await dependencies.currentSession()
        try Task.checkCancellation()
        guard !finalSession.isAnonymous,
              finalSession.userID == permanentUserId,
              manager.currentSessionUserId == permanentUserId,
              dependencies.currentObservedUserId() == permanentUserId else {
            throw ConsentHandoffError.activeAccountChanged
        }
    }

    func ensureCloudConsentForInference(
        manager: ConsentManager
    ) async throws {
        guard manager.hasCurrentRequiredConsent else {
            throw MerianError.aiConsentRequired
        }

        if !dependencies.isAuthenticated() {
            guard await dependencies.initializeGhostSession() else {
                throw SupabaseAuthTransitionError.signOutInProgress
            }
        }
        let accountWorkLease = try dependencies
            .beginUnownedAccountBoundWork()
        defer { dependencies.finishAccountBoundWork(accountWorkLease) }

        let adoptionGeneration = synchronizationCoordinator.generation
        let userId = accountWorkLease.session.userID
        try Task.checkCancellation()
        guard synchronizationCoordinator.generation == adoptionGeneration,
              dependencies.isAccountBoundWorkLeaseCurrent(accountWorkLease),
              manager.canAdoptCloudSession(userId) else {
            throw ConsentHandoffError.activeAccountChanged
        }
        let canBindUnownedRequiredConsent =
            manager.hasBindableUnownedRequiredConsent()
        manager.adoptCloudSession(userId)

        guard manager.hasCurrentRequiredConsent
                || canBindUnownedRequiredConsent else {
            throw MerianError.aiConsentRequired
        }

        try await manager.synchronize(for: userId)
        try Task.checkCancellation()
        guard synchronizationCoordinator.generation == adoptionGeneration,
              dependencies.isAccountBoundWorkLeaseCurrent(accountWorkLease)
        else {
            throw ConsentHandoffError.activeAccountChanged
        }
        guard manager.hasCloudReadyCurrentConsent(for: userId) else {
            do {
                try manager
                    .requireCurrentConsentReapprovalAfterServerRejection()
            } catch {
                dependencies.reportReapprovalPersistenceFailure(error)
            }
            throw MerianError.aiConsentRequired
        }
    }

    func synchronizeWithCurrentSession(
        manager: ConsentManager
    ) async throws {
        let accountWorkLease = try dependencies
            .beginUnownedAccountBoundWork()
        defer { dependencies.finishAccountBoundWork(accountWorkLease) }
        try await synchronizeWithCurrentSession(
            manager: manager,
            authorizationIsCurrent: {
                self.dependencies
                    .isAccountBoundWorkLeaseCurrent(accountWorkLease)
            }
        )
    }

    func synchronizeWithCurrentSession(
        manager: ConsentManager,
        ownedBy transition: AuthTransitionToken
    ) async throws {
        try await synchronizeWithCurrentSession(
            manager: manager,
            authorizationIsCurrent: {
                self.dependencies
                    .currentSessionMatchesAuthTransition(transition)
            }
        )
    }

    func scheduleSynchronization(
        manager: ConsentManager,
        createAnonymousSessionIfNeeded: Bool
    ) {
        guard !dependencies.isRunningTests() else { return }
        guard !dependencies.isAuthTransitionInProgress(),
              !dependencies.isAccountDeletionCleanupPending() else {
            return
        }
        synchronizationCoordinator.schedule { @MainActor [weak self, weak manager] in
            guard let self, let manager else { return }
            guard !Task.isCancelled else { return }
            if createAnonymousSessionIfNeeded {
                _ = await self.dependencies.initializeGhostSession()
            }
            guard !Task.isCancelled else { return }
            do {
                try await self.synchronizeWithCurrentSession(manager: manager)
            } catch is CancellationError {
                return
            } catch {
                // The synchronization path records retryable restoration
                // failures while identity and generation still match.
            }
        }
    }

    private func synchronizeWithCurrentSession(
        manager: ConsentManager,
        authorizationIsCurrent: @escaping @MainActor () -> Bool
    ) async throws {
        guard !dependencies.isRunningTests() else { return }
        try Task.checkCancellation()
        guard authorizationIsCurrent() else {
            throw ConsentHandoffError.activeAccountChanged
        }
        let adoptionGeneration = synchronizationCoordinator.generation
        do {
            let session = try await dependencies.currentSession()
            try Task.checkCancellation()
            guard authorizationIsCurrent(),
                  synchronizationCoordinator.generation
                    == adoptionGeneration,
                  dependencies.currentSDKUserId() == session.userID,
                  manager.canAdoptCloudSession(session.userID) else {
                throw ConsentHandoffError.activeAccountChanged
            }
            manager.adoptCloudSession(session.userID)
            try await manager.synchronize(for: session.userID)
            try Task.checkCancellation()
            guard authorizationIsCurrent(),
                  synchronizationCoordinator.generation
                    == adoptionGeneration,
                  dependencies.currentSDKUserId() == session.userID else {
                throw ConsentHandoffError.activeAccountChanged
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let userId = manager.currentSessionUserId {
                manager.handleConsentSynchronizationFailure(
                    error,
                    for: userId,
                    generation: adoptionGeneration
                )
            }
            throw error
        }
    }
}

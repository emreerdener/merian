import Foundation

/// Owns provider-bound Ghost merge preparation and completion task lifetime.
/// Supabase, RevenueCat, consent, Keychain, and logging effects arrive through
/// narrow dependencies supplied by the live Auth facade.
@MainActor
final class GhostProfileMergeCoordinator {
    private struct CompletionKey: Equatable {
        let targetUserID: UUID
        let transition: AuthTransitionToken?
    }

    private var task: Task<Bool, Never>?
    private var taskID: UUID?
    private var activeKey: CompletionKey?

    deinit {
        task?.cancel()
    }

    func prepare(
        sourceUserID: UUID,
        provider: AuthTransitionProvider,
        providerSubject: String,
        ownedBy transition: AuthTransitionToken,
        dependencies: GhostProfileMergeDependencies
    ) async throws -> PendingGhostProfileMerge {
        try Task.checkCancellation()
        guard transition.kind == .oauth(provider) else {
            throw SupabaseAuthTransitionError.guestMergeSessionChanged
        }
        let source = AuthTransitionSession(
            userID: sourceUserID,
            isAnonymous: true
        )
        guard exactSessionMatches(
            source,
            ownedBy: transition,
            dependencies: dependencies
        ) else {
            throw SupabaseAuthTransitionError.guestMergeSessionChanged
        }

        let preparation = try await dependencies.operations.prepare(
            provider.rawValue,
            providerSubject
        )
        guard exactSessionMatches(
            source,
            ownedBy: transition,
            dependencies: dependencies,
            requiresActiveTask: false
        ) else {
            throw SupabaseAuthTransitionError.guestMergeSessionChanged
        }

        let pending = PendingGhostProfileMerge(
            ghostUserId: sourceUserID.uuidString.lowercased(),
            provider: provider.rawValue,
            providerSubject: providerSubject,
            handoffId: preparation.handoffID,
            handoffSecret: preparation.handoffSecret,
            expiresAt: preparation.expiresAt
        )
        let existing = try loadQueue(dependencies: dependencies)
        let updated = GhostProfileMergePolicy.enqueuing(
            pending,
            in: existing
        )
        try persistQueue(updated, dependencies: dependencies)
        dependencies.setAnalyticsSuppressed(true)
        dependencies.diagnose(.secured, nil)
        try Task.checkCancellation()
        return pending
    }

    func hasPendingHandoffs(
        dependencies: GhostProfileMergeDependencies
    ) throws -> Bool {
        try !loadQueue(dependencies: dependencies).isEmpty
    }

    func clearHandoffs(
        for sourceUserID: UUID,
        dependencies: GhostProfileMergeDependencies
    ) throws {
        let remaining: [PendingGhostProfileMerge]
        do {
            remaining = try dependencies.queue.clearSource(
                sourceUserID.uuidString.lowercased()
            )
        } catch {
            throw SupabaseAuthTransitionError
                .guestMergeHandoffPersistenceFailed
        }
        dependencies.setAnalyticsSuppressed(!remaining.isEmpty)
    }

    func completePendingHandoffs(
        expectedTargetUserID: UUID? = nil,
        ownedBy transition: AuthTransitionToken? = nil,
        dependencies: GhostProfileMergeDependencies
    ) async -> Bool {
        guard !Task.isCancelled,
              let targetUserID = expectedTargetUserID
                ?? dependencies.session.currentPublishedSession()?.userID else {
            return false
        }
        let target = AuthTransitionSession(
            userID: targetUserID,
            isAnonymous: false
        )
        let accountWorkLease: AccountBoundWorkLease?
        if let transition {
            guard exactSessionMatches(
                target,
                ownedBy: transition,
                dependencies: dependencies
            ) else {
                return false
            }
            accountWorkLease = nil
        } else {
            guard let lease = dependencies.session
                .beginUnownedAccountWork(targetUserID) else {
                return false
            }
            accountWorkLease = lease
        }
        defer {
            if let accountWorkLease {
                dependencies.session.finishAccountWork(accountWorkLease)
            }
        }

        let key = CompletionKey(
            targetUserID: targetUserID,
            transition: transition
        )
        if let task {
            if activeKey == key {
                return await task.value
            }
            cancel()
        }

        let taskID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            return await self.performPendingHandoffs(
                target: target,
                ownedBy: transition,
                dependencies: dependencies
            )
        }
        self.taskID = taskID
        activeKey = key
        self.task = task

        let result = await task.value
        if self.taskID == taskID {
            self.task = nil
            self.taskID = nil
            activeKey = nil
        }
        return result
    }

    func completeTransfer(
        expectedTargetUserID: UUID,
        ownedBy transition: AuthTransitionToken?,
        dependencies: GhostProfileMergeDependencies
    ) async -> LibraryTransferResult {
        let completed = await completePendingHandoffs(
            expectedTargetUserID: expectedTargetUserID,
            ownedBy: transition,
            dependencies: dependencies
        )
        if completed { return .completed }
        do {
            let handoffs = try loadQueue(dependencies: dependencies)
            if handoffs.isEmpty { return .completed }
            return handoffs.contains { $0.requiresAttention == true }
                ? .needsAttention : .pending
        } catch {
            return .needsAttention
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        taskID = nil
        activeKey = nil
    }

    private func performPendingHandoffs(
        target: AuthTransitionSession,
        ownedBy transition: AuthTransitionToken?,
        dependencies: GhostProfileMergeDependencies
    ) async -> Bool {
        guard !Task.isCancelled,
              !dependencies.session.isSigningOut() else {
            return false
        }

        let pendingHandoffs: [PendingGhostProfileMerge]
        do {
            pendingHandoffs = try loadQueue(dependencies: dependencies)
        } catch {
            dependencies.setAnalyticsSuppressed(true)
            dependencies.diagnose(.queueUnreadable, error)
            return false
        }
        guard !pendingHandoffs.isEmpty else {
            dependencies.setAnalyticsSuppressed(false)
            return true
        }
        dependencies.setAnalyticsSuppressed(true)

        let loadedSession: AuthTransitionSession
        do {
            loadedSession = try await dependencies.session.loadSDKSession()
        } catch {
            dependencies.diagnose(.sessionUnavailable, error)
            return false
        }
        guard loadedSession == target,
              exactSessionMatches(
                  target,
                  ownedBy: transition,
                  dependencies: dependencies
              ) else {
            dependencies.diagnose(.unexpectedTarget, nil)
            return false
        }

        var allHandoffsResolved = true
        for var pending in pendingHandoffs {
            guard !Task.isCancelled,
                  !dependencies.session.isSigningOut() else {
                return false
            }
            guard let sourceUserID = UUID(
                uuidString: pending.ghostUserId
            ) else {
                allHandoffsResolved = false
                dependencies.diagnose(.invalidSource, nil)
                continue
            }

            guard pending.requiresAttention != true,
                  pending.destinationUserID == nil || pending.destinationUserID == target.userID else {
                allHandoffsResolved = false
                continue
            }
            do {
                // Pin the destination before the first server side effect. Never
                // replay a retained capability under a replacement account.
                pending.destinationUserID = target.userID
                var current = try loadQueue(dependencies: dependencies)
                guard let index = current.firstIndex(where: { $0.handoffId == pending.handoffId }) else {
                    allHandoffsResolved = false
                    continue
                }
                current[index] = pending
                try persistQueue(current, dependencies: dependencies)
                try await GhostProfileMergeWorkflow.finalizeHandoff(
                    completeServerHandoff: {
                        guard self.exactSessionMatches(
                            target,
                            ownedBy: transition,
                            dependencies: dependencies
                        ) else {
                            throw SupabaseAuthTransitionError
                                .guestMergeSessionChanged
                        }
                        try await dependencies.operations.complete(pending)
                        guard self.exactSessionMatches(
                            target,
                            ownedBy: transition,
                            dependencies: dependencies
                        ) else {
                            throw SupabaseAuthTransitionError
                                .guestMergeSessionChanged
                        }
                    },
                    synchronizeProviderPurchases: {
                        guard self.exactSessionMatches(
                            target,
                            ownedBy: transition,
                            dependencies: dependencies
                        ) else {
                            throw SupabaseAuthTransitionError
                                .guestMergeSessionChanged
                        }
                        try await dependencies.operations
                            .synchronizeProviderPurchases()
                    },
                    rebindAndSynchronizeLocalEvidence: {
                        guard self.exactSessionMatches(
                            target,
                            ownedBy: transition,
                            dependencies: dependencies
                        ) else {
                            throw SupabaseAuthTransitionError
                                .guestMergeSessionChanged
                        }
                        try await dependencies.operations
                            .rebindAndSynchronizeLocalEvidence(
                                sourceUserID,
                                target.userID
                            )
                    },
                    clearPendingHandoff: {
                        guard self.exactSessionMatches(
                            target,
                            ownedBy: transition,
                            dependencies: dependencies
                        ), dependencies.operations.targetEvidenceMatches(
                            target.userID
                        ) else {
                            throw SupabaseAuthTransitionError
                                .guestMergeSessionChanged
                        }
                        try self.clearHandoff(
                            pending.handoffId,
                            dependencies: dependencies
                        )
                    }
                )
                guard !Task.isCancelled,
                      exactSessionMatches(
                          target,
                          ownedBy: transition,
                          dependencies: dependencies
                      ) else {
                    return false
                }
                dependencies.diagnose(.completed, nil)
            } catch {
                guard !Task.isCancelled else { return false }
                if dependencies.operations.isTerminalHandoffError(error) {
                    // Invalid/expired proof is not evidence that the library moved.
                    allHandoffsResolved = false
                    do {
                        var current = try loadQueue(dependencies: dependencies)
                        if let index = current.firstIndex(where: { $0.handoffId == pending.handoffId }) {
                            current[index].requiresAttention = true
                            try persistQueue(current, dependencies: dependencies)
                        }
                        dependencies.diagnose(.terminalCleanupPending, error)
                    } catch {
                        dependencies.diagnose(.queueUnreadable, error)
                    }
                } else {
                    allHandoffsResolved = false
                    dependencies.diagnose(.retryPending, error)
                }
            }
        }

        guard !Task.isCancelled else { return false }
        let queueIsEmpty: Bool
        do {
            queueIsEmpty = try loadQueue(
                dependencies: dependencies
            ).isEmpty
        } catch {
            dependencies.setAnalyticsSuppressed(true)
            dependencies.diagnose(.queueUnreadable, error)
            return false
        }
        if allHandoffsResolved, queueIsEmpty {
            dependencies.setAnalyticsSuppressed(false)
        }
        return allHandoffsResolved && queueIsEmpty
    }

    private func exactSessionMatches(
        _ expected: AuthTransitionSession,
        ownedBy transition: AuthTransitionToken?,
        dependencies: GhostProfileMergeDependencies,
        requiresActiveTask: Bool = true
    ) -> Bool {
        guard !requiresActiveTask || !Task.isCancelled,
              !dependencies.session.isSigningOut(),
              dependencies.session.currentPublishedSession() == expected,
              dependencies.session.currentSDKSession() == expected else {
            return false
        }
        if let transition {
            return dependencies.session.currentSessionMatchesTransition(
                transition
            )
        }
        return true
    }

    private func loadQueue(
        dependencies: GhostProfileMergeDependencies
    ) throws -> [PendingGhostProfileMerge] {
        do {
            let snapshot = try dependencies.queue.load()
            if snapshot.legacyMigrationWasDeferred {
                dependencies.diagnose(.legacyMigrationDeferred, nil)
            }
            return snapshot.handoffs
        } catch {
            throw SupabaseAuthTransitionError
                .guestMergeHandoffPersistenceFailed
        }
    }

    private func persistQueue(
        _ handoffs: [PendingGhostProfileMerge],
        dependencies: GhostProfileMergeDependencies
    ) throws {
        do {
            try dependencies.queue.persist(handoffs)
        } catch {
            throw SupabaseAuthTransitionError
                .guestMergeHandoffPersistenceFailed
        }
    }

    private func clearHandoff(
        _ handoffID: String,
        dependencies: GhostProfileMergeDependencies
    ) throws {
        do {
            try dependencies.queue.clear(handoffID)
        } catch {
            throw SupabaseAuthTransitionError
                .guestMergeHandoffPersistenceFailed
        }
    }
}

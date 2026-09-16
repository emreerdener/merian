import Foundation

/// Owns restored-session public-author identity refresh as one keyed task.
/// Provider session reads, account-work leases, remote effects, app events,
/// and diagnostics remain injected by `SupabaseManager`.
@MainActor
final class PublicAuthorIdentityRefreshCoordinator {
    private var task: Task<Void, Never>?
    private var taskID: UUID?
    private var activeUserID: UUID?
    private var lastCompletedUserID: UUID?

    deinit {
        task?.cancel()
    }

    @discardableResult
    func scheduleIfNeeded(
        for session: AuthTransitionSession,
        dependencies: PublicAuthorIdentityRefreshDependencies
    ) -> Bool {
        guard !dependencies.session.isTestExecution(),
              !dependencies.session.hasActiveTransition(),
              !session.isAnonymous,
              dependencies.session.currentPublishedUserID()
                == session.userID,
              session.userID != lastCompletedUserID,
              session.userID != activeUserID else {
            return false
        }

        cancel()
        let taskID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performScheduledRefresh(
                expectedUserID: session.userID,
                taskID: taskID,
                dependencies: dependencies
            )
        }
        self.taskID = taskID
        activeUserID = session.userID
        self.task = task
        return true
    }

    @discardableResult
    func refresh(
        expectedUserID: UUID,
        ownedBy transition: AuthTransitionToken? = nil,
        dependencies: PublicAuthorIdentityRefreshDependencies
    ) async -> Bool {
        guard !Task.isCancelled else { return false }

        let accountWorkLease: AccountBoundWorkLease?
        if let transition {
            guard dependencies.session.transitionOwnsExpectedUser(
                transition,
                expectedUserID
            ) else {
                return false
            }
            accountWorkLease = nil
        } else {
            guard let lease = dependencies.session.beginUnownedAccountWork(
                expectedUserID
            ) else {
                return false
            }
            accountWorkLease = lease
        }
        defer {
            if let accountWorkLease {
                dependencies.session.finishAccountWork(accountWorkLease)
            }
        }

        guard !Task.isCancelled else { return false }
        do {
            try await dependencies.operations.refreshRemoteIdentity()
            guard !Task.isCancelled else { return false }
            if let transition {
                return dependencies.session.transitionOwnsExpectedUser(
                    transition,
                    expectedUserID
                )
            }
            return accountWorkLease.map(
                dependencies.session.accountWorkIsCurrent
            ) ?? false
        } catch {
            guard !Task.isCancelled else { return false }
            dependencies.diagnostics.reportRefreshFailure(error)
            return false
        }
    }

    func clearCompletedUser() {
        lastCompletedUserID = nil
    }

    func cancel() {
        task?.cancel()
        task = nil
        taskID = nil
        activeUserID = nil
    }

    private func performScheduledRefresh(
        expectedUserID: UUID,
        taskID: UUID,
        dependencies: PublicAuthorIdentityRefreshDependencies
    ) async {
        defer { clearTaskIfCurrent(taskID) }
        guard !Task.isCancelled else { return }
        guard let accountWorkLease = dependencies.session
            .beginUnownedAccountWork(expectedUserID) else {
            return
        }
        defer {
            dependencies.session.finishAccountWork(accountWorkLease)
        }

        guard !Task.isCancelled else { return }
        await dependencies.operations.completePendingGhostMerges(
            expectedUserID
        )
        guard !Task.isCancelled,
              dependencies.session.accountWorkIsCurrent(accountWorkLease)
        else {
            return
        }
        guard await refresh(
            expectedUserID: expectedUserID,
            dependencies: dependencies
        ) else {
            return
        }
        guard !Task.isCancelled,
              dependencies.session.accountWorkIsCurrent(accountWorkLease),
              dependencies.session.currentPublishedUserID() == expectedUserID
        else {
            return
        }

        lastCompletedUserID = expectedUserID
        dependencies.events.publishIdentityChanged(
            nil,
            expectedUserID.uuidString.lowercased()
        )
    }

    private func clearTaskIfCurrent(_ completedTaskID: UUID) {
        guard taskID == completedTaskID else { return }
        task = nil
        taskID = nil
        activeUserID = nil
    }
}

import Foundation

/// Serializes initial Auth-session resolution and anonymous session creation.
/// Live Supabase, purchase-identity, presentation, and logging effects arrive
/// through narrow dependencies supplied by the Auth facade.
@MainActor
final class AuthSessionBootstrapCoordinator {
    private var task: Task<AuthTransitionSession?, Never>?
    private var taskID: UUID?
    private var taskTransition: AuthTransitionToken?

    deinit {
        task?.cancel()
    }

    func initialize(
        ownedBy requestedTransition: AuthTransitionToken? = nil,
        dependencies: AuthSessionBootstrapDependencies
    ) async -> AuthTransitionSession? {
        guard !Task.isCancelled,
              !dependencies.state.isTestExecution(),
              !dependencies.state.isAccountDeletionCleanupPending() else {
            return nil
        }

        await dependencies.state.awaitSignOutCompletion()
        guard !Task.isCancelled else { return nil }

        if let task, let taskTransition {
            let activeTransition = dependencies.transition.activeTransition()
            let requestedOwnerMatches = requestedTransition == taskTransition
            let ownerlessBootstrapMatches = requestedTransition == nil
                && taskTransition.kind == .anonymousBootstrap
            guard activeTransition == taskTransition,
                  requestedOwnerMatches || ownerlessBootstrapMatches else {
                return nil
            }
            return await task.value
        }

        if requestedTransition == nil,
           let session = dependencies.operations.currentSDKSession(),
           !session.isExpired,
           dependencies.state.currentPublishedSession() == session.identity,
           dependencies.state.isAuthenticated(),
           let lease = dependencies.work.beginUnownedAccountWork(
                session.identity.userID
           ) {
            defer { dependencies.work.finishAccountWork(lease) }
            await session.ensurePurchaseIdentityReady(nil)
            guard !Task.isCancelled,
                  dependencies.work.isAccountWorkCurrent(lease) else {
                return nil
            }
            return session.identity
        }

        let transition: AuthTransitionToken
        let finishesTransition: Bool
        if let requestedTransition {
            guard dependencies.transition.allows(requestedTransition) else {
                return nil
            }
            transition = requestedTransition
            finishesTransition = false
        } else {
            guard let bootstrap = dependencies.transition
                .beginAnonymousBootstrap() else {
                return nil
            }
            transition = bootstrap
            finishesTransition = true
        }

        let taskID = UUID()
        let task: Task<AuthTransitionSession?, Never> = Task { @MainActor [weak self] in
            guard let self else { return nil }
            defer {
                if finishesTransition {
                    dependencies.transition.finish(transition)
                }
                if self.taskID == taskID {
                    self.task = nil
                    self.taskID = nil
                    self.taskTransition = nil
                }
            }
            return await self.performBootstrap(
                ownedBy: transition,
                dependencies: dependencies
            )
        }
        self.task = task
        self.taskID = taskID
        taskTransition = transition
        return await task.value
    }

    @discardableResult
    func cancel() -> Task<AuthTransitionSession?, Never>? {
        let cancelledTask = task
        cancelledTask?.cancel()
        task = nil
        taskID = nil
        taskTransition = nil
        return cancelledTask
    }

    private func performBootstrap(
        ownedBy transition: AuthTransitionToken,
        dependencies: AuthSessionBootstrapDependencies
    ) async -> AuthTransitionSession? {
        guard !Task.isCancelled,
              dependencies.transition.allows(transition),
              await dependencies.transition.awaitAccountWorkQuiescence(),
              !Task.isCancelled,
              dependencies.transition.allows(transition) else {
            return nil
        }

        do {
            let session = try await dependencies.operations.loadSDKSession()
            guard !Task.isCancelled,
                  dependencies.transition.allows(transition),
                  dependencies.transition.adopt(
                      session.identity,
                      transition
                  ) else {
                return nil
            }
            session.publish()
            dependencies.diagnose(.existingSessionResolved, nil)
            session.schedulePublicAuthorIdentityRefresh()
            await session.ensurePurchaseIdentityReady(transition)
            guard !Task.isCancelled,
                  session.isCurrentPublishedSession(transition) else {
                return nil
            }
            return session.identity
        } catch {
            guard dependencies.operations.isSessionMissingError(error) else {
                dependencies.diagnose(.existingIdentityPreserved, error)
                return nil
            }
        }

        guard !Task.isCancelled,
              dependencies.transition.allows(transition) else {
            return nil
        }
        do {
            let session = try await dependencies.operations
                .createAnonymousSession()
            guard !Task.isCancelled,
                  dependencies.transition.allows(transition),
                  dependencies.transition.adopt(
                      session.identity,
                      transition
                  ) else {
                return nil
            }
            session.publish()
            dependencies.diagnose(.anonymousSessionEstablished, nil)
            await session.ensurePurchaseIdentityReady(transition)
            guard !Task.isCancelled,
                  session.isCurrentPublishedSession(transition) else {
                return nil
            }
            return session.identity
        } catch {
            dependencies.diagnose(.anonymousSessionCreationFailed, error)
            return nil
        }
    }
}

import Foundation

/// Owns deferred, overlap-safe Apple credential revalidation. Provider SDK
/// notification and lookup details remain behind injected live boundaries.
@MainActor
final class AppleCredentialRevocationCoordinator {
    private struct Attempt: Equatable {
        let identity: AppleCredentialRevocationIdentity
        let contextGeneration: UInt64
    }

    private enum ResultAction {
        case preserveSession
        case clearSession(AppleCredentialRevocationDiagnostic)
    }

    private var task: Task<Void, Never>?
    private var taskID: UUID?
    private var activeAttempt: Attempt?
    private var applyingRevocationTaskID: UUID?
    private var contextGeneration: UInt64 = 0
    private var hasPendingNotification = false

    deinit {
        task?.cancel()
    }

    func handleRevocationNotification(
        dependencies: AppleCredentialRevocationDependencies
    ) {
        hasPendingNotification = true
        startPendingAttemptIfPossible(dependencies: dependencies)
    }

    /// Invalidates lookup work before an Auth transition or SDK lifecycle
    /// event mutates the published session. A notification already being
    /// handled is retained for the stable session that follows.
    func authContextWillChange() {
        contextGeneration &+= 1
        guard applyingRevocationTaskID == nil,
              task != nil || hasPendingNotification else {
            return
        }
        hasPendingNotification = true
        invalidateActiveTask()
    }

    /// Resumes a notification deferred by a transition or Auth lifecycle
    /// publication once the manager has installed its final session state.
    func resumeDeferredIfNeeded(
        dependencies: AppleCredentialRevocationDependencies
    ) {
        startPendingAttemptIfPossible(dependencies: dependencies)
    }

    func cancel() {
        contextGeneration &+= 1
        hasPendingNotification = false
        applyingRevocationTaskID = nil
        invalidateActiveTask()
    }

    private func startPendingAttemptIfPossible(
        dependencies: AppleCredentialRevocationDependencies
    ) {
        guard hasPendingNotification,
              !dependencies.session.hasActiveTransition() else {
            return
        }
        guard let identity = dependencies.session.currentIdentity() else {
            hasPendingNotification = false
            invalidateActiveTask()
            return
        }

        let attempt = Attempt(
            identity: identity,
            contextGeneration: contextGeneration
        )
        guard activeAttempt != attempt else {
            // Preserve one follow-up lookup when another notification arrives
            // during the exact same in-flight attempt.
            return
        }

        hasPendingNotification = false
        invalidateActiveTask()

        let taskID = UUID()
        self.taskID = taskID
        activeAttempt = attempt
        task = Task { @MainActor [weak self] in
            // This task is retained by the coordinator. Keep the coordinator
            // weak on both sides of provider suspension so owner release can
            // cancel without waiting for an SDK callback.
            guard self?.attemptIsCurrent(
                attempt,
                taskID: taskID,
                dependencies: dependencies
            ) == true else {
                self?.rejectAttemptIfCurrent(
                    taskID,
                    dependencies: dependencies
                )
                return
            }

            let result = await dependencies.operations.lookupCredentialState(
                attempt.identity.providerSubject
            )
            guard let action = self?.prepareResultAction(
                result,
                attempt: attempt,
                taskID: taskID,
                dependencies: dependencies
            ) else {
                return
            }

            if case .clearSession(let diagnostic) = action {
                let clearOutcome = await dependencies.operations
                    .clearLocalSessionIfCurrent(
                        attempt.identity
                    )
                switch clearOutcome {
                case .cleared:
                    dependencies.diagnose(diagnostic)
                case .contextChanged:
                    self?.rejectAttemptIfCurrent(
                        taskID,
                        dependencies: dependencies
                    )
                    return
                case .deferred:
                    guard let self else { return }
                    if self.attemptIsCurrent(
                        attempt,
                        taskID: taskID,
                        dependencies: dependencies
                    ) {
                        self.deferAttemptIfCurrent(taskID)
                    } else {
                        // A lifecycle resume can arrive while terminal clear is
                        // suspended, before this attempt publishes its deferred
                        // state. Revalidate the now-stable context instead of
                        // losing that wakeup.
                        self.rejectAttemptIfCurrent(
                            taskID,
                            dependencies: dependencies
                        )
                    }
                    return
                }
            }
            self?.finishAttemptIfCurrent(
                taskID,
                dependencies: dependencies
            )
        }
    }

    private func prepareResultAction(
        _ result: AppleCredentialRevocationLookupResult,
        attempt: Attempt,
        taskID: UUID,
        dependencies: AppleCredentialRevocationDependencies
    ) -> ResultAction? {
        guard attemptIsCurrent(
            attempt,
            taskID: taskID,
            dependencies: dependencies
        ) else {
            rejectAttemptIfCurrent(
                taskID,
                dependencies: dependencies
            )
            return nil
        }

        guard result.requiresLocalSessionClear else {
            dependencies.diagnose(.authorizedSessionPreserved)
            return .preserveSession
        }

        let diagnostic: AppleCredentialRevocationDiagnostic
        switch result {
        case .lookupFailed:
            diagnostic = .lookupFailedClearingLocalSession
        case .authorized:
            return .preserveSession
        case .revoked, .notFound, .transferred, .unknown:
            diagnostic = .unauthorizedCredentialClearingLocalSession
        }

        applyingRevocationTaskID = taskID
        return .clearSession(diagnostic)
    }

    private func attemptIsCurrent(
        _ attempt: Attempt,
        taskID: UUID,
        dependencies: AppleCredentialRevocationDependencies
    ) -> Bool {
        !Task.isCancelled
            && self.taskID == taskID
            && activeAttempt == attempt
            && contextGeneration == attempt.contextGeneration
            && !dependencies.session.hasActiveTransition()
            && dependencies.session.currentIdentity() == attempt.identity
    }

    private func retainNotificationIfCurrentTask(_ taskID: UUID) {
        guard self.taskID == taskID else { return }
        hasPendingNotification = true
    }

    private func rejectAttemptIfCurrent(
        _ rejectedTaskID: UUID,
        dependencies: AppleCredentialRevocationDependencies
    ) {
        retainNotificationIfCurrentTask(rejectedTaskID)
        finishAttemptIfCurrent(
            rejectedTaskID,
            dependencies: dependencies
        )
    }

    private func deferAttemptIfCurrent(_ deferredTaskID: UUID) {
        guard taskID == deferredTaskID else { return }
        hasPendingNotification = true
        task = nil
        taskID = nil
        activeAttempt = nil
        applyingRevocationTaskID = nil
    }

    private func finishAttemptIfCurrent(
        _ completedTaskID: UUID,
        dependencies: AppleCredentialRevocationDependencies
    ) {
        guard taskID == completedTaskID else { return }
        task = nil
        taskID = nil
        activeAttempt = nil
        applyingRevocationTaskID = nil
        startPendingAttemptIfPossible(dependencies: dependencies)
    }

    private func invalidateActiveTask() {
        task?.cancel()
        task = nil
        taskID = nil
        activeAttempt = nil
    }
}

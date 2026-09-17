import Foundation

struct AuthLocalSignOutPreparation {
    let awaitCancelledBootstrap: @MainActor () async -> Void
}

struct AuthLocalSignOutStateBoundary {
    let begin: @MainActor () -> AuthLocalSignOutPreparation
    let finish: @MainActor () -> Void
}

struct AuthLocalSignOutTransitionBoundary {
    let owns: @MainActor (AuthTransitionToken) -> Bool
    let awaitAccountWorkQuiescence: @MainActor () async -> Bool
    let updateForSessionInstallation:
        @MainActor (AuthTransitionToken) -> Void
    let adoptSignedOutSession: @MainActor (AuthTransitionToken) -> Void
}

struct AuthLocalSignOutOperationBoundary {
    let signOutSDKSession: @MainActor () async throws -> Void
    let finishExternalSignOut: @MainActor () async -> Void
}

enum AuthLocalSignOutDiagnostic: Equatable {
    case sdkSignOutFailed
    case completed
}

struct AuthLocalSignOutDependencies {
    let state: AuthLocalSignOutStateBoundary
    let transition: AuthLocalSignOutTransitionBoundary
    let operations: AuthLocalSignOutOperationBoundary
    let diagnose: @MainActor (AuthLocalSignOutDiagnostic, Error?) -> Void
}

/// Owns the retained local-sign-out task and its exact transition sequencing.
/// SDK, product, observable-state, persistence, and diagnostic effects remain
/// injected by the Auth facade.
@MainActor
final class AuthLocalSignOutCoordinator {
    private var task: Task<Void, Never>?
    private var taskID: UUID?

    var isRunning: Bool { task != nil }

    deinit {
        task?.cancel()
    }

    func waitForCompletion() async {
        let task = task
        await task?.value
    }

    func signOut(
        ownedBy transition: AuthTransitionToken,
        dependencies: AuthLocalSignOutDependencies
    ) async {
        guard dependencies.transition.owns(transition),
              await dependencies.transition.awaitAccountWorkQuiescence(),
              dependencies.transition.owns(transition) else {
            return
        }
        if let task {
            await task.value
            return
        }

        let preparation = dependencies.state.begin()
        dependencies.transition.updateForSessionInstallation(transition)
        dependencies.transition.adoptSignedOutSession(transition)

        let taskID = UUID()
        let task = Task { @MainActor [weak self] in
            defer {
                dependencies.state.finish()
                self?.clearTaskIfCurrent(taskID)
            }
            guard !Task.isCancelled,
                  self?.taskID == taskID else {
                return
            }

            await preparation.awaitCancelledBootstrap()
            guard !Task.isCancelled,
                  dependencies.transition.owns(transition) else {
                return
            }

            do {
                try await dependencies.operations.signOutSDKSession()
            } catch {
                dependencies.diagnose(.sdkSignOutFailed, error)
            }

            await dependencies.operations.finishExternalSignOut()
            dependencies.diagnose(.completed, nil)
        }
        self.taskID = taskID
        self.task = task
        await task.value
    }

    func cancel() {
        task?.cancel()
    }

    private func clearTaskIfCurrent(_ completedTaskID: UUID) {
        guard taskID == completedTaskID else { return }
        task = nil
        taskID = nil
    }
}

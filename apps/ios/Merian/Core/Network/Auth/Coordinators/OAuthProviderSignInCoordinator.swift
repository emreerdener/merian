import Foundation

/// Owns provider-presentation admission and Apple callback task lifetime while
/// delegating provider-neutral session installation to `OAuthSignInCoordinator`.
@MainActor
final class OAuthProviderSignInCoordinator {
    private struct PendingAppleAuthorization {
        let id: UUID
        let transition: AuthTransitionToken
        let sourceSession: AuthTransitionSession?
        let transitionBoundary: OAuthProviderSignInTransitionBoundary
        let completionBoundary: OAuthProviderSignInCompletionBoundary
        let diagnostics: OAuthProviderSignInDiagnostics
        let cancelAuthorization: @MainActor () -> Void
    }

    private var pendingAppleAuthorization: PendingAppleAuthorization?
    private var appleCompletionTask: Task<Void, Never>?
    private var appleCompletionTaskID: UUID?

    func signInWithGoogle(
        dependencies: OAuthProviderSignInDependencies
    ) async {
        guard let transition = dependencies.transition.begin(.google) else {
            dependencies.diagnostics.report(
                .transitionRejected(.google),
                nil
            )
            return
        }
        dependencies.transition.updateAwaitingProvider(transition)
        defer { dependencies.transition.finish(transition) }

        let sourceSession = dependencies.transition.sourceSession(transition)
        var didMutateSession = false
        do {
            let outcome = try await dependencies.authorization
                .authorizeWithGoogle()
            switch outcome {
            case .presentationUnavailable:
                dependencies.diagnostics.report(
                    .googlePresentationUnavailable,
                    nil
                )
                return
            case .missingIdentityToken:
                try await dependencies.transition
                    .verifyExpectedSessionIfPresent(transition)
                dependencies.diagnostics.report(
                    .googleMissingIdentityToken,
                    nil
                )
                return
            case .authorized(let authorization):
                try await dependencies.transition
                    .verifyExpectedSessionIfPresent(transition)
                try await dependencies.completion.complete(
                    authorization,
                    transition,
                    { didMutateSession = true }
                )
                dependencies.diagnostics.report(.completed(.google), nil)
            }
        } catch {
            await dependencies.completion.recoverAfterFailure(
                didMutateSession,
                sourceSession,
                transition
            )
            dependencies.diagnostics.report(
                .completionFailed(.google),
                error
            )
        }
    }

    func startAppleSignIn(
        dependencies: OAuthProviderSignInDependencies
    ) {
        guard let transition = dependencies.transition.begin(.apple) else {
            dependencies.diagnostics.report(
                .transitionRejected(.apple),
                nil
            )
            return
        }
        dependencies.transition.updateAwaitingProvider(transition)

        let attemptID = UUID()
        pendingAppleAuthorization = PendingAppleAuthorization(
            id: attemptID,
            transition: transition,
            sourceSession: dependencies.transition.sourceSession(transition),
            transitionBoundary: dependencies.transition,
            completionBoundary: dependencies.completion,
            diagnostics: dependencies.diagnostics,
            cancelAuthorization: dependencies.authorization
                .cancelAppleAuthorization
        )

        do {
            try dependencies.authorization.startAppleAuthorization(
                { [weak self] result in
                    self?.handleAppleAuthorization(
                        result,
                        attemptID: attemptID
                    )
                }
            )
        } catch {
            guard pendingAppleAuthorization?.id == attemptID else { return }
            pendingAppleAuthorization = nil
            dependencies.transition.finish(transition)
            dependencies.diagnostics.report(
                Self.appleDiagnostic(for: error, duringStart: true),
                error
            )
        }
    }

    func cancel() {
        if let pendingAppleAuthorization {
            self.pendingAppleAuthorization = nil
            pendingAppleAuthorization.cancelAuthorization()
            pendingAppleAuthorization.transitionBoundary.finish(
                pendingAppleAuthorization.transition
            )
        }
        let task = appleCompletionTask
        appleCompletionTask = nil
        appleCompletionTaskID = nil
        task?.cancel()
    }

    private func handleAppleAuthorization(
        _ result: Result<OAuthProviderAuthorization, Error>,
        attemptID: UUID
    ) {
        guard let attempt = pendingAppleAuthorization,
              attempt.id == attemptID else {
            return
        }
        guard AuthTransitionPolicy.shouldAcceptAppleSignInCallback(
            activeTransitionID: attempt.transitionBoundary.activeTransitionID(),
            attemptTransitionID: attempt.transition.id,
            controllerMatches: true
        ) else {
            pendingAppleAuthorization = nil
            attempt.transitionBoundary.finish(attempt.transition)
            attempt.diagnostics.report(.appleStaleCallback, nil)
            return
        }
        pendingAppleAuthorization = nil

        switch result {
        case .failure(let error):
            attempt.transitionBoundary.finish(attempt.transition)
            attempt.diagnostics.report(
                Self.appleDiagnostic(for: error, duringStart: false),
                error
            )
        case .success(let authorization):
            startAppleCompletion(
                authorization,
                attempt: attempt
            )
        }
    }

    private func startAppleCompletion(
        _ authorization: OAuthProviderAuthorization,
        attempt: PendingAppleAuthorization
    ) {
        appleCompletionTask?.cancel()
        let taskID = UUID()
        appleCompletionTaskID = taskID
        appleCompletionTask = Task { @MainActor [weak self] in
            await Self.completeAppleSignIn(
                authorization,
                attempt: attempt
            )
            self?.clearAppleCompletionTask(taskID)
        }
    }

    private static func completeAppleSignIn(
        _ authorization: OAuthProviderAuthorization,
        attempt: PendingAppleAuthorization
    ) async {
        defer { attempt.transitionBoundary.finish(attempt.transition) }
        var didMutateSession = false
        do {
            try await attempt.completionBoundary.complete(
                authorization,
                attempt.transition,
                { didMutateSession = true }
            )
            attempt.diagnostics.report(.completed(.apple), nil)
        } catch {
            await attempt.completionBoundary.recoverAfterFailure(
                didMutateSession,
                attempt.sourceSession,
                attempt.transition
            )
            attempt.diagnostics.report(
                .completionFailed(.apple),
                error
            )
        }
    }

    private func clearAppleCompletionTask(_ completedTaskID: UUID) {
        guard appleCompletionTaskID == completedTaskID else { return }
        appleCompletionTask = nil
        appleCompletionTaskID = nil
    }

    private static func appleDiagnostic(
        for error: Error,
        duringStart: Bool
    ) -> OAuthProviderSignInDiagnostic {
        guard let error = error as? AppleOAuthAuthorizationError else {
            return duringStart ? .appleBootstrapFailed : .appleProviderFailed
        }
        switch error {
        case .authorizationAlreadyInProgress, .nonceGenerationFailed:
            return .appleBootstrapFailed
        case .presentationUnavailable:
            return .applePresentationUnavailable
        case .invalidCredential:
            return .appleInvalidCredential
        case .missingIdentityToken:
            return .appleMissingIdentityToken
        case .missingAuthorizationCode:
            return .appleMissingAuthorizationCode
        case .invalidIdentityTokenEncoding:
            return .appleInvalidIdentityToken
        case .invalidAuthorizationCodeEncoding:
            return .appleInvalidAuthorizationCode
        }
    }
}

import Foundation

/// Owns provider-neutral OAuth session installation and authenticated completion
/// ordering. Provider presentation and all live SDK effects remain injected by
/// `SupabaseManager`.
@MainActor
struct OAuthSignInCoordinator {
    private let dependencies: OAuthSignInCoordinationDependencies

    init(dependencies: OAuthSignInCoordinationDependencies) {
        self.dependencies = dependencies
    }

    func complete(
        credentials: OAuthSignInCredentials,
        profileMetadata: OAuthProfileMetadata,
        registerProviderCredential: OAuthProviderCredentialRegistration?,
        ownedBy transition: AuthTransitionToken,
        didMutateSession: @MainActor () -> Void
    ) async throws -> OAuthSignInCompletion {
        try Task.checkCancellation()
        guard transition.kind == .oauth(credentials.provider) else {
            throw OAuthSignInWorkflowError.providerTransitionMismatch
        }

        let providerRegistrationIsValid = switch credentials.provider {
        case .apple:
            registerProviderCredential != nil
        case .google:
            registerProviderCredential == nil
        }
        guard providerRegistrationIsValid else {
            throw OAuthSignInWorkflowError
                .invalidProviderCredentialRegistrationConfiguration
        }

        let installed = try await installSession(
            credentials: credentials,
            ownedBy: transition,
            didMutateSession: didMutateSession
        )
        try Task.checkCancellation()

        if let registerProviderCredential {
            try await registerProviderCredential(
                installed.session.userID,
                transition
            )
            try Task.checkCancellation()
        }

        let didPersistMetadata: Bool
        if profileMetadata.isEmpty {
            didPersistMetadata = false
        } else {
            didPersistMetadata = await dependencies.completion
                .persistProfileMetadata(
                    profileMetadata,
                    credentials.provider,
                    installed.session.userID,
                    transition
                )
            try Task.checkCancellation()
        }

        let session = try await dependencies.session
            .publishAuthenticatedSession(transition)
        try Task.checkCancellation()
        dependencies.session.updateTransition(transition, .bindingPurchases)
        await dependencies.completion.ensureTelemetryLinked(
            session.userID,
            transition
        )
        try Task.checkCancellation()
        guard dependencies.session.currentSessionMatchesTransition(
            transition
        ), dependencies.completion.providerIdentityIsReady(session.userID)
        else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }

        await dependencies.completion.beginEntitlementSession(
            session.userID,
            transition
        )
        try Task.checkCancellation()
        _ = try await dependencies.session.verifyExpectedSession(transition)
        try Task.checkCancellation()
        if didPersistMetadata {
            _ = await dependencies.completion.refreshPublicAuthorIdentity(
                session.userID,
                transition
            )
            try Task.checkCancellation()
        }
        dependencies.session.updateTransition(transition, .finalizing)
        _ = try await dependencies.session.verifyExpectedSession(transition)
        try Task.checkCancellation()
        dependencies.completion.publishPublicAuthorIdentityChange(
            installed.previousUserID,
            session.userID.uuidString
        )
        dependencies.completion.markAuthenticatedOAuth()

        return OAuthSignInCompletion(
            previousUserID: installed.previousUserID,
            session: session
        )
    }

    private func installSession(
        credentials: OAuthSignInCredentials,
        ownedBy transition: AuthTransitionToken,
        didMutateSession: @MainActor () -> Void
    ) async throws -> OAuthSignInCompletion {
        guard dependencies.session.ownsTransition(transition),
              !dependencies.session.isSignOutInProgress() else {
            throw SupabaseAuthTransitionError.signOutInProgress
        }

        let previousSession = try await dependencies.session
            .verifyExpectedSessionIfPresent(transition)
        try Task.checkCancellation()
        let previousUserID = previousSession?.userID.uuidString

        if previousSession?.isAnonymous == true {
            guard await dependencies.merge.completePendingPurchaseHandoff(
                previousUserID,
                transition
            ) else {
                throw SupabaseAuthTransitionError
                    .signOutPurchaseContinuityPending
            }
            try Task.checkCancellation()

            do {
                try Task.checkCancellation()
                try await dependencies.session.linkIdentity(credentials)
                didMutateSession()
                try Task.checkCancellation()
                let linkedSession = try await dependencies.session
                    .readSDKSession()
                try Task.checkCancellation()
                guard let previousSession,
                      AuthTransitionPolicy.acceptsLinkedIdentityUpgrade(
                          sourceSession: previousSession.identity,
                          targetSession: linkedSession.identity
                      ), dependencies.session.adoptSession(
                          linkedSession,
                          transition
                      ), dependencies.session.currentSessionMatchesTransition(
                          transition
                      ) else {
                    throw SupabaseAuthTransitionError.signOutSessionChanged
                }
                if let previousUserID {
                    try dependencies.merge.clearGhostMerges(previousUserID)
                }
            } catch {
                if Task.isCancelled || error is CancellationError {
                    throw CancellationError()
                }
                guard dependencies.merge.requiresProviderBoundGhostMerge(
                    error
                ) else {
                    throw error
                }
                guard dependencies.session.ownsTransition(transition),
                      !dependencies.session.isSignOutInProgress() else {
                    throw SupabaseAuthTransitionError.signOutInProgress
                }
                guard let ghostID = previousUserID?.lowercased() else {
                    throw SupabaseAuthTransitionError
                        .guestMergeSessionChanged
                }

                let currentGuestSession = try await dependencies.session
                    .verifyExpectedSession(transition)
                try Task.checkCancellation()
                guard currentGuestSession.isAnonymous,
                      currentGuestSession.userID.uuidString.lowercased()
                        == ghostID else {
                    throw SupabaseAuthTransitionError
                        .guestMergeSessionChanged
                }

                let providerSubject = try OAuthIdentityTokenPolicy
                    .providerSubject(from: credentials.idToken)
                try await dependencies.merge.prepareGhostMerge(
                    ghostID,
                    credentials.provider,
                    providerSubject,
                    transition
                )
                try Task.checkCancellation()

                _ = try await dependencies.session.verifyExpectedSession(
                    transition
                )
                try Task.checkCancellation()
                dependencies.session.updateTransition(
                    transition,
                    .installingSession
                )
                let targetSession = try await dependencies.session
                    .replaceAndAdoptSession(
                        credentials,
                        transition,
                        didMutateSession
                    )
                try Task.checkCancellation()
                guard dependencies.session.currentSessionMatchesTransition(
                    transition
                ) else {
                    throw SupabaseAuthTransitionError.signOutSessionChanged
                }
                if targetSession.userID.uuidString.lowercased() == ghostID {
                    try dependencies.merge.clearGhostMerges(ghostID)
                } else {
                    _ = await dependencies.merge.completePendingGhostMerge(
                        targetSession.userID.uuidString,
                        transition
                    )
                    try Task.checkCancellation()
                }
            }
        } else {
            dependencies.session.updateTransition(
                transition,
                .installingSession
            )
            _ = try await dependencies.session
                .replaceAndAdoptSession(
                    credentials,
                    transition,
                    didMutateSession
                )
            try Task.checkCancellation()
            guard dependencies.session.currentSessionMatchesTransition(
                transition
            ) else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }
        }

        let targetSession = try await dependencies.session.readSDKSession()
        try Task.checkCancellation()
        guard dependencies.session.ownsTransition(transition) else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        if dependencies.session.expectedSession(transition)
            == previousSession?.identity {
            guard dependencies.session.adoptSession(
                targetSession,
                transition
            ) else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }
        }
        guard dependencies.session.currentSessionMatchesTransition(
            transition
        ) else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        return OAuthSignInCompletion(
            previousUserID: previousUserID,
            session: targetSession
        )
    }
}

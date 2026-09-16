import Foundation

struct OAuthSignInSessionBoundary {
    let ownsTransition: @MainActor (AuthTransitionToken) -> Bool
    let isSignOutInProgress: @MainActor () -> Bool
    let expectedSession: @MainActor (AuthTransitionToken)
        -> AuthTransitionSession?
    let verifyExpectedSessionIfPresent: @MainActor (
        AuthTransitionToken
    ) async throws -> OAuthSignInSession?
    let verifyExpectedSession: @MainActor (
        AuthTransitionToken
    ) async throws -> OAuthSignInSession
    let readSDKSession: @MainActor () async throws -> OAuthSignInSession
    let linkIdentity: @MainActor (OAuthSignInCredentials) async throws -> Void
    /// Installs the provider session and records that exact SDK identity as the
    /// transition expectation before cancellation can be observed.
    let replaceAndAdoptSession: @MainActor (
        OAuthSignInCredentials,
        AuthTransitionToken,
        OAuthSessionMutationObserver
    ) async throws -> OAuthSignInSession
    let adoptSession: @MainActor (
        OAuthSignInSession,
        AuthTransitionToken
    ) -> Bool
    let currentSessionMatchesTransition: @MainActor (
        AuthTransitionToken
    ) -> Bool
    let updateTransition: @MainActor (
        AuthTransitionToken,
        AuthTransitionPhase
    ) -> Void
    let publishAuthenticatedSession: @MainActor (
        AuthTransitionToken
    ) async throws -> OAuthSignInSession
}

typealias OAuthSessionMutationObserver = @MainActor () -> Void

struct OAuthSignInMergeBoundary {
    let completePendingPurchaseHandoff: @MainActor (
        String?,
        AuthTransitionToken
    ) async -> Bool
    let requiresProviderBoundGhostMerge: @MainActor (Error) -> Bool
    let prepareGhostMerge: @MainActor (
        String,
        AuthTransitionProvider,
        String,
        AuthTransitionToken
    ) async throws -> Void
    let clearGhostMerges: @MainActor (String) throws -> Void
    let completePendingGhostMerge: @MainActor (
        String,
        AuthTransitionToken
    ) async -> Bool
}

struct OAuthSignInCompletionBoundary {
    let persistProfileMetadata: @MainActor (
        OAuthProfileMetadata,
        AuthTransitionProvider,
        UUID,
        AuthTransitionToken
    ) async -> Bool
    let ensureTelemetryLinked: @MainActor (
        UUID,
        AuthTransitionToken
    ) async -> Void
    let providerIdentityIsReady: @MainActor (UUID) -> Bool
    let beginEntitlementSession: @MainActor (
        UUID,
        AuthTransitionToken
    ) async -> Void
    let refreshPublicAuthorIdentity: @MainActor (
        UUID,
        AuthTransitionToken
    ) async -> Bool
    let publishPublicAuthorIdentityChange: @MainActor (
        String?,
        String
    ) -> Void
    let markAuthenticatedOAuth: @MainActor () -> Void
}

struct OAuthSignInCoordinationDependencies {
    let session: OAuthSignInSessionBoundary
    let merge: OAuthSignInMergeBoundary
    let completion: OAuthSignInCompletionBoundary
}

typealias OAuthProviderCredentialRegistration = @MainActor (
    UUID,
    AuthTransitionToken
) async throws -> Void

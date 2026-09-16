import Foundation

typealias OAuthProviderAuthorizationCompletion = @MainActor (
    Result<OAuthProviderAuthorization, Error>
) -> Void

typealias OAuthProviderSessionMutationObserver = @MainActor () -> Void

struct OAuthProviderSignInTransitionBoundary {
    let begin: @MainActor (AuthTransitionProvider) -> AuthTransitionToken?
    let updateAwaitingProvider: @MainActor (AuthTransitionToken) -> Void
    let activeTransitionID: @MainActor () -> UUID?
    let sourceSession: @MainActor (AuthTransitionToken)
        -> AuthTransitionSession?
    let verifyExpectedSessionIfPresent: @MainActor (
        AuthTransitionToken
    ) async throws -> Void
    let finish: @MainActor (AuthTransitionToken) -> Void
}

struct OAuthProviderAuthorizationBoundary {
    let authorizeWithGoogle: @MainActor () async throws
        -> GoogleOAuthAuthorizationOutcome
    let startAppleAuthorization: @MainActor (
        @escaping OAuthProviderAuthorizationCompletion
    ) throws -> Void
    let cancelAppleAuthorization: @MainActor () -> Void
}

struct OAuthProviderSignInCompletionBoundary {
    let complete: @MainActor (
        OAuthProviderAuthorization,
        AuthTransitionToken,
        OAuthProviderSessionMutationObserver
    ) async throws -> Void
    let recoverAfterFailure: @MainActor (
        Bool,
        AuthTransitionSession?,
        AuthTransitionToken
    ) async -> Void
}

struct OAuthProviderSignInDiagnostics {
    let report: @MainActor (
        OAuthProviderSignInDiagnostic,
        Error?
    ) -> Void
}

struct OAuthProviderSignInDependencies {
    let transition: OAuthProviderSignInTransitionBoundary
    let authorization: OAuthProviderAuthorizationBoundary
    let completion: OAuthProviderSignInCompletionBoundary
    let diagnostics: OAuthProviderSignInDiagnostics
}

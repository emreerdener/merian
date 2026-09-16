import Foundation

struct AuthSessionBootstrapSnapshot {
    let identity: AuthTransitionSession
    let isExpired: Bool
    let publish: @MainActor () -> Void
    let schedulePublicAuthorIdentityRefresh: @MainActor () -> Void
    let ensurePurchaseIdentityReady: @MainActor (
        AuthTransitionToken?
    ) async -> Void
    let isCurrentPublishedSession: @MainActor (
        AuthTransitionToken?
    ) -> Bool
}

struct AuthSessionBootstrapStateBoundary {
    let isTestExecution: @MainActor () -> Bool
    let isAccountDeletionCleanupPending: @MainActor () -> Bool
    let isAuthenticated: @MainActor () -> Bool
    let currentPublishedSession: @MainActor () -> AuthTransitionSession?
    let awaitSignOutCompletion: @MainActor () async -> Void
}

struct AuthSessionBootstrapTransitionBoundary {
    let activeTransition: @MainActor () -> AuthTransitionToken?
    let beginAnonymousBootstrap: @MainActor () -> AuthTransitionToken?
    let allows: @MainActor (AuthTransitionToken?) -> Bool
    let adopt: @MainActor (
        AuthTransitionSession,
        AuthTransitionToken
    ) -> Bool
    let finish: @MainActor (AuthTransitionToken) -> Void
    let awaitAccountWorkQuiescence: @MainActor () async -> Bool
}

struct AuthSessionBootstrapWorkBoundary {
    let beginUnownedAccountWork: @MainActor (
        UUID
    ) -> AccountBoundWorkLease?
    let isAccountWorkCurrent: @MainActor (
        AccountBoundWorkLease
    ) -> Bool
    let finishAccountWork: @MainActor (AccountBoundWorkLease) -> Void
}

struct AuthSessionBootstrapOperationBoundary {
    let currentSDKSession: @MainActor () -> AuthSessionBootstrapSnapshot?
    let loadSDKSession: @MainActor () async throws
        -> AuthSessionBootstrapSnapshot
    let createAnonymousSession: @MainActor () async throws
        -> AuthSessionBootstrapSnapshot
    let isSessionMissingError: @MainActor (Error) -> Bool
}

enum AuthSessionBootstrapDiagnostic: Equatable {
    case existingSessionResolved
    case anonymousSessionEstablished
    case anonymousSessionCreationFailed
    case existingIdentityPreserved
}

struct AuthSessionBootstrapDependencies {
    let state: AuthSessionBootstrapStateBoundary
    let transition: AuthSessionBootstrapTransitionBoundary
    let work: AuthSessionBootstrapWorkBoundary
    let operations: AuthSessionBootstrapOperationBoundary
    let diagnose: @MainActor (
        AuthSessionBootstrapDiagnostic,
        Error?
    ) -> Void
}

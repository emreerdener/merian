import Foundation

struct PublicAuthorRefreshSessionBoundary {
    let isTestExecution: @MainActor () -> Bool
    let hasActiveTransition: @MainActor () -> Bool
    let currentPublishedUserID: @MainActor () -> UUID?
    let transitionOwnsExpectedUser: @MainActor (
        AuthTransitionToken,
        UUID
    ) -> Bool
    let beginUnownedAccountWork: @MainActor (
        UUID
    ) -> AccountBoundWorkLease?
    let finishAccountWork: @MainActor (AccountBoundWorkLease) -> Void
    let accountWorkIsCurrent: @MainActor (AccountBoundWorkLease) -> Bool
}

struct PublicAuthorRefreshOperationBoundary {
    let completePendingGhostMerges: @MainActor (UUID) async -> Void
    let refreshRemoteIdentity: @MainActor () async throws -> Void
}

struct PublicAuthorRefreshEventBoundary {
    let publishIdentityChanged: @MainActor (String?, String) -> Void
}

struct PublicAuthorRefreshDiagnostics {
    let reportRefreshFailure: @MainActor (Error) -> Void
}

struct PublicAuthorIdentityRefreshDependencies {
    let session: PublicAuthorRefreshSessionBoundary
    let operations: PublicAuthorRefreshOperationBoundary
    let events: PublicAuthorRefreshEventBoundary
    let diagnostics: PublicAuthorRefreshDiagnostics
}

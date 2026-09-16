import Foundation

struct GhostProfileMergeQueueSnapshot {
    let handoffs: [PendingGhostProfileMerge]
    let legacyMigrationWasDeferred: Bool
}

struct GhostProfileMergeSessionBoundary {
    let isSigningOut: @MainActor () -> Bool
    let currentPublishedSession: @MainActor () -> AuthTransitionSession?
    let currentSDKSession: @MainActor () -> AuthTransitionSession?
    let currentSessionMatchesTransition: @MainActor (
        AuthTransitionToken
    ) -> Bool
    let beginUnownedAccountWork: @MainActor (
        UUID
    ) -> AccountBoundWorkLease?
    let finishAccountWork: @MainActor (AccountBoundWorkLease) -> Void
    let loadSDKSession: @MainActor () async throws
        -> AuthTransitionSession
}

struct GhostProfileMergeQueueBoundary {
    let load: @MainActor () throws -> GhostProfileMergeQueueSnapshot
    let persist: @MainActor ([PendingGhostProfileMerge]) throws -> Void
    let clear: @MainActor (String) throws -> Void
    let clearSource: @MainActor (
        String
    ) throws -> [PendingGhostProfileMerge]
}

struct GhostProfileMergeOperationBoundary {
    let prepare: @MainActor (
        String,
        String
    ) async throws -> GhostProfileMergePreparation
    let complete: @MainActor (
        PendingGhostProfileMerge
    ) async throws -> Void
    let synchronizeProviderPurchases: @MainActor () async throws -> Void
    let rebindAndSynchronizeLocalEvidence: @MainActor (
        UUID,
        UUID
    ) async throws -> Void
    let synchronizeTargetEvidence: @MainActor (
        AuthTransitionToken?
    ) async throws -> Void
    let targetEvidenceMatches: @MainActor (UUID) -> Bool
    let isTerminalHandoffError: @MainActor (Error) -> Bool
}

enum GhostProfileMergeDiagnostic: Equatable {
    case secured
    case legacyMigrationDeferred
    case queueUnreadable
    case unexpectedTarget
    case invalidSource
    case completed
    case terminalDiscarded
    case terminalCleanupPending
    case retryPending
    case sessionUnavailable
}

struct GhostProfileMergeDependencies {
    let session: GhostProfileMergeSessionBoundary
    let queue: GhostProfileMergeQueueBoundary
    let operations: GhostProfileMergeOperationBoundary
    let setAnalyticsSuppressed: @MainActor (Bool) -> Void
    let diagnose: @MainActor (
        GhostProfileMergeDiagnostic,
        Error?
    ) -> Void
}

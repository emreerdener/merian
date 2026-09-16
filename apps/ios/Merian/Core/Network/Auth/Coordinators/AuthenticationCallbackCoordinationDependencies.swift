import Foundation

/// Provider-neutral capabilities attached to one Supabase Auth session by the
/// live facade. The coordinator never acquires or stores the SDK value itself.
struct AuthenticationCallbackSession {
    let identity: AuthTransitionSession
    let isExpired: Bool
    let publish: @MainActor () -> Void
    let ensurePurchaseIdentityReady: @MainActor (
        AuthTransitionToken
    ) async -> Void
    let purchaseIdentityIsReady: @MainActor () -> Bool
    let beginEntitlementSession: @MainActor (
        AuthTransitionToken
    ) async -> Void
}

typealias AuthCallbackSessionMutationObserver = @MainActor () -> Void

struct AuthenticationCallbackTransitionBoundary {
    let hasPendingPurchaseIdentityHandoff: @MainActor () -> Bool
    let isSignOutInProgress: @MainActor () -> Bool
    let begin: @MainActor () -> AuthTransitionToken?
    let finish: @MainActor (AuthTransitionToken) -> Void
    let owns: @MainActor (AuthTransitionToken) -> Bool
    let sourceSession: @MainActor (
        AuthTransitionToken
    ) -> AuthTransitionSession?
    let currentSessionMatches: @MainActor (
        AuthTransitionToken
    ) -> Bool
    let verifyExpectedSessionIfPresent: @MainActor (
        AuthTransitionToken
    ) async throws -> Void
    let verifyExpectedSession: @MainActor (
        AuthTransitionToken
    ) async throws -> Void
    let updatePhase: @MainActor (
        AuthTransitionToken,
        AuthTransitionPhase
    ) -> Void
}

struct AuthenticationCallbackSessionBoundary {
    let analyticsGeneration: @MainActor (AuthTransitionToken) -> UInt
    /// Installs the callback session and records that exact SDK identity as the
    /// transition expectation before cancellation can be observed.
    let installAndAdopt: @MainActor (
        AuthTransitionToken,
        AuthCallbackSessionMutationObserver
    ) async throws -> AuthenticationCallbackSession
    let current: @MainActor () -> AuthenticationCallbackSession?
    let clearPublishedSession: @MainActor () -> Void
}

struct AuthenticationCallbackCompletionBoundary {
    let clearMutatedSession: @MainActor (
        AuthTransitionToken
    ) async -> Void
    let markAuthenticatedOAuth: @MainActor (Bool) -> Void
}

enum AuthenticationCallbackDiagnostic: Equatable, Sendable {
    case transitionRejected
    case sourceSessionRejected
    case completionFailed
}

struct AuthenticationCallbackDiagnostics {
    let report: @MainActor (
        AuthenticationCallbackDiagnostic,
        Error?
    ) -> Void
}

struct AuthenticationCallbackDependencies {
    let transition: AuthenticationCallbackTransitionBoundary
    let session: AuthenticationCallbackSessionBoundary
    let completion: AuthenticationCallbackCompletionBoundary
    let diagnostics: AuthenticationCallbackDiagnostics
}

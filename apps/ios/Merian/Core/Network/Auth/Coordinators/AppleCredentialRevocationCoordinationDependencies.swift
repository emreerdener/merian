struct AppleCredentialRevocationIdentity: Equatable, Sendable {
    let session: AuthTransitionSession
    let providerSubject: String
}

enum AppleCredentialRevocationLookupResult: Equatable, Sendable {
    case authorized
    case revoked
    case notFound
    case transferred
    case unknown
    case lookupFailed

    var requiresLocalSessionClear: Bool {
        self != .authorized
    }
}

enum AppleCredentialRevocationDiagnostic: Equatable, Sendable {
    case authorizedSessionPreserved
    case lookupFailedClearingLocalSession
    case unauthorizedCredentialClearingLocalSession
}

struct AppleCredentialRevocationSessionBoundary {
    let hasActiveTransition: @MainActor () -> Bool
    let currentIdentity: @MainActor () -> AppleCredentialRevocationIdentity?
}

enum AppleCredentialRevocationClearOutcome: Equatable {
    case cleared
    case contextChanged
    case deferred
}

struct AppleRevocationOperationBoundary {
    let lookupCredentialState: @MainActor (
        String
    ) async -> AppleCredentialRevocationLookupResult
    /// Reports completed cleanup, a pre-admission context change that can be
    /// retried immediately when stable, or a recovery deferral that requires an
    /// explicit lifecycle or purchase-handoff completion resume while the
    /// attempt's Auth context remains current.
    let clearLocalSessionIfCurrent: @MainActor (
        AppleCredentialRevocationIdentity
    ) async -> AppleCredentialRevocationClearOutcome
}

struct AppleCredentialRevocationDependencies {
    let session: AppleCredentialRevocationSessionBoundary
    let operations: AppleRevocationOperationBoundary
    let diagnose: @MainActor (AppleCredentialRevocationDiagnostic) -> Void
}

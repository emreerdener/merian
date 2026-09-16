import Foundation

/// Maps provider-neutral bootstrap outcomes onto the privacy-safe Auth log.
@MainActor
enum AuthSessionBootstrapLiveDiagnostics {
    static func report(
        _ diagnostic: AuthSessionBootstrapDiagnostic,
        error: Error?
    ) {
        switch diagnostic {
        case .existingSessionResolved:
            MerianLog.auth.debug(
                "Existing session resolved on device."
            )
        case .anonymousSessionEstablished:
            MerianLog.auth.debug(
                "Signed-out session established."
            )
        case .anonymousSessionCreationFailed:
            let errorKind = error.map(MerianLog.errorKind)
                ?? "unavailable"
            MerianLog.auth.debug(
                "Failed to establish a signed-out session; kind=\(errorKind, privacy: .public)"
            )
        case .existingIdentityPreserved:
            MerianLog.auth.debug(
                "Skipped anonymous sign-in — preserving existing identity despite network or expiration error."
            )
        }
    }
}

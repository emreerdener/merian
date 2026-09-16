import os

/// Maps provider-neutral revocation outcomes onto the privacy-safe Auth log.
@MainActor
enum AppleCredentialRevocationLiveDiagnostics {
    static func report(_ diagnostic: AppleCredentialRevocationDiagnostic) {
        switch diagnostic {
        case .authorizedSessionPreserved:
            MerianLog.auth.debug(
                "Apple credential remained authorized after a revocation notification; preserving the active session."
            )
        case .lookupFailedClearingLocalSession:
            MerianLog.auth.notice(
                "Apple credential state lookup failed after a revocation notification; cleared the matching local session."
            )
        case .unauthorizedCredentialClearingLocalSession:
            MerianLog.auth.notice(
                "Apple confirmed that the active credential is no longer authorized; cleared the matching local session."
            )
        }
    }
}

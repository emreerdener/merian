import Foundation

extension OAuthProviderSignInDiagnostics {
    @MainActor
    static let live = Self { diagnostic, error in
        switch diagnostic {
        case .transitionRejected(.google):
            MerianLog.auth.debug(
                "Ignored Google Sign-In because another authentication transition owns the session."
            )
        case .transitionRejected(.apple):
            MerianLog.auth.debug(
                "Ignored Apple Sign-In because another authentication transition owns the session."
            )
        case .googlePresentationUnavailable:
            MerianLog.auth.debug(
                "Failed to find root view controller for Google Sign-In."
            )
        case .googleMissingIdentityToken:
            MerianLog.auth.debug("Google Sign-In: no ID token returned.")
        case .appleBootstrapFailed:
            MerianLog.auth.error(
                "Apple Sign-In bootstrap failed; kind=\(errorKind(error), privacy: .public)"
            )
        case .applePresentationUnavailable:
            MerianLog.auth.error(
                "Apple Sign-In aborted because no presentation anchor is available."
            )
        case .appleInvalidCredential:
            break
        case .appleMissingIdentityToken:
            MerianLog.auth.debug(
                "Apple Sign-In: unable to fetch identity token."
            )
        case .appleMissingAuthorizationCode:
            MerianLog.auth.error(
                "Apple Sign-In: unable to fetch the authorization code required for durable token revocation."
            )
        case .appleInvalidIdentityToken:
            MerianLog.auth.debug(
                "Apple Sign-In: failed to serialize token string."
            )
        case .appleInvalidAuthorizationCode:
            MerianLog.auth.error(
                "Apple Sign-In: failed to serialize the authorization code required for durable token revocation."
            )
        case .appleProviderFailed:
            MerianLog.auth.debug(
                "Apple Sign-In failed before completion; kind=\(errorKind(error), privacy: .public)"
            )
        case .appleStaleCallback:
            MerianLog.auth.error(
                "Ignored a stale Apple Sign-In callback that no longer owns the authentication transition."
            )
        case .completed(.google):
            MerianLog.auth.debug("Google Sign-In complete.")
        case .completed(.apple):
            MerianLog.auth.debug("Apple Sign-In complete.")
        case .completionFailed(.google):
            MerianLog.auth.debug(
                "Google Sign-In failed; kind=\(errorKind(error), privacy: .public)"
            )
        case .completionFailed(.apple):
            MerianLog.auth.debug(
                "Apple Sign-In failed; kind=\(errorKind(error), privacy: .public)"
            )
        }
    }

    private static func errorKind(_ error: Error?) -> String {
        guard let error else { return "UnavailableError" }
        return MerianLog.errorKind(error)
    }
}

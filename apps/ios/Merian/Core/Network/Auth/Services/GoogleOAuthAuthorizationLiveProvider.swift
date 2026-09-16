import Foundation
import GoogleSignIn
import UIKit

struct GoogleOAuthAuthorizationResponse: Equatable, Sendable {
    let idToken: String?
    let accessToken: String
    let displayName: String?
    let givenName: String?
    let familyName: String?
    let avatarURL: String?
}

struct GoogleOAuthAuthorizationLiveDependencies {
    let presentingViewController: @MainActor () -> UIViewController?
    let signIn: @MainActor (
        UIViewController
    ) async throws -> GoogleOAuthAuthorizationResponse

    @MainActor
    static var live: Self {
        Self(
            presentingViewController: {
                OAuthPresentationContextResolver.rootViewController()
            },
            signIn: { viewController in
                let result = try await GIDSignIn.sharedInstance.signIn(
                    withPresenting: viewController
                )
                return GoogleOAuthAuthorizationResponse(
                    idToken: result.user.idToken?.tokenString,
                    accessToken: result.user.accessToken.tokenString,
                    displayName: result.user.profile?.name,
                    givenName: result.user.profile?.givenName,
                    familyName: result.user.profile?.familyName,
                    avatarURL: result.user.profile?
                        .imageURL(withDimension: 256)?.absoluteString
                )
            }
        )
    }
}

/// Contains the Google SDK presentation and value-mapping surface used by the
/// provider-neutral sign-in task owner.
@MainActor
struct GoogleOAuthAuthorizationLiveProvider {
    private let dependencies: GoogleOAuthAuthorizationLiveDependencies

    init() {
        dependencies = .live
    }

    init(dependencies: GoogleOAuthAuthorizationLiveDependencies) {
        self.dependencies = dependencies
    }

    func authorize() async throws -> GoogleOAuthAuthorizationOutcome {
        guard let viewController = dependencies.presentingViewController()
        else {
            return .presentationUnavailable
        }

        try Task.checkCancellation()
        let response = try await dependencies.signIn(viewController)
        try Task.checkCancellation()
        guard let idToken = response.idToken else {
            return .missingIdentityToken
        }

        return .authorized(
            OAuthProviderAuthorization(
                credentials: OAuthSignInCredentials(
                    provider: .google,
                    idToken: idToken,
                    accessToken: response.accessToken,
                    nonce: nil
                ),
                profileMetadata: OAuthProfileMetadata(
                    displayName: response.displayName,
                    givenName: response.givenName,
                    familyName: response.familyName,
                    avatarURL: response.avatarURL
                ),
                appleCredentialRegistration: nil
            )
        )
    }
}

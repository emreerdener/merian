import AuthenticationServices
import CryptoKit
import Foundation
import Security

struct AppleOAuthAuthorizationLiveDependencies {
    let randomNonce: @MainActor () throws -> String
    let hashNonce: @MainActor (String) -> String
    let presentationAnchor: @MainActor () -> ASPresentationAnchor?
    let makeRequest: @MainActor () -> ASAuthorizationAppleIDRequest
    let makeController: @MainActor (
        ASAuthorizationAppleIDRequest
    ) -> ASAuthorizationController
    let performRequests: @MainActor (ASAuthorizationController) -> Void
    let registrationID: @MainActor () -> UUID

    @MainActor
    static var live: Self {
        Self(
            randomNonce: {
                try AppleOAuthAuthorizationLiveProvider.randomNonceString()
            },
            hashNonce: {
                AppleOAuthAuthorizationLiveProvider.sha256($0)
            },
            presentationAnchor: {
                OAuthPresentationContextResolver.keyWindowAnchor()
            },
            makeRequest: {
                ASAuthorizationAppleIDProvider().createRequest()
            },
            makeController: {
                ASAuthorizationController(authorizationRequests: [$0])
            },
            performRequests: { $0.performRequests() },
            registrationID: UUID.init
        )
    }
}

/// Owns Apple authorization-controller retention, delegate callbacks, nonce
/// generation, and conversion into provider-neutral OAuth values.
@MainActor
final class AppleOAuthAuthorizationLiveProvider: NSObject {
    private struct Attempt {
        let nonce: String
        let anchor: ASPresentationAnchor
        let controller: ASAuthorizationController
        let completion: OAuthProviderAuthorizationCompletion
    }

    private let dependencies: AppleOAuthAuthorizationLiveDependencies
    private var activeAttempt: Attempt?

    init(
        dependencies: AppleOAuthAuthorizationLiveDependencies = .live
    ) {
        self.dependencies = dependencies
    }

    func start(
        completion: @escaping OAuthProviderAuthorizationCompletion
    ) throws {
        guard activeAttempt == nil else {
            throw AppleOAuthAuthorizationError
                .authorizationAlreadyInProgress
        }

        let nonce = try dependencies.randomNonce()
        guard let anchor = dependencies.presentationAnchor() else {
            throw AppleOAuthAuthorizationError.presentationUnavailable
        }

        let request = dependencies.makeRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = dependencies.hashNonce(nonce)

        let controller = dependencies.makeController(request)
        controller.delegate = self
        controller.presentationContextProvider = self
        activeAttempt = Attempt(
            nonce: nonce,
            anchor: anchor,
            controller: controller,
            completion: completion
        )
        dependencies.performRequests(controller)
    }

    func cancel() {
        activeAttempt = nil
    }

    static func authorization(
        identityToken: Data?,
        authorizationCode: Data?,
        fullName: PersonNameComponents?,
        nonce: String,
        registrationID: UUID
    ) throws -> OAuthProviderAuthorization {
        guard let identityToken else {
            throw AppleOAuthAuthorizationError.missingIdentityToken
        }
        guard let authorizationCode else {
            throw AppleOAuthAuthorizationError.missingAuthorizationCode
        }
        guard let identityTokenString = String(
            data: identityToken,
            encoding: .utf8
        ) else {
            throw AppleOAuthAuthorizationError
                .invalidIdentityTokenEncoding
        }
        guard let authorizationCodeString = String(
            data: authorizationCode,
            encoding: .utf8
        ), !authorizationCodeString.isEmpty else {
            throw AppleOAuthAuthorizationError
                .invalidAuthorizationCodeEncoding
        }

        return OAuthProviderAuthorization(
            credentials: OAuthSignInCredentials(
                provider: .apple,
                idToken: identityTokenString,
                accessToken: nil,
                nonce: nonce
            ),
            profileMetadata: OAuthProfileMetadata(
                appleNameComponents: fullName
            ),
            appleCredentialRegistration: AppleOAuthCredentialRegistration(
                registrationID: registrationID,
                authorizationCode: authorizationCodeString
            )
        )
    }

    static func randomNonceString(length: Int = 32) throws -> String {
        precondition(length > 0)
        let charset = Array(
            "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._"
        )
        let maxValidValue = UInt8(charset.count * (256 / charset.count))

        var nonce = ""
        nonce.reserveCapacity(length)
        while nonce.count < length {
            var buffer = [UInt8](
                repeating: 0,
                count: length - nonce.count
            )
            let status = SecRandomCopyBytes(
                kSecRandomDefault,
                buffer.count,
                &buffer
            )
            guard status == errSecSuccess else {
                throw AppleOAuthAuthorizationError
                    .nonceGenerationFailed(status)
            }
            for byte in buffer where byte < maxValidValue {
                nonce.append(charset[Int(byte) % charset.count])
                if nonce.count == length { break }
            }
        }
        return nonce
    }

    static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

extension AppleOAuthAuthorizationLiveProvider:
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        if let attempt = activeAttempt,
           controller === attempt.controller {
            return attempt.anchor
        }
        return dependencies.presentationAnchor() ?? ASPresentationAnchor()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let attempt = activeAttempt,
              controller === attempt.controller else {
            MerianLog.auth.error(
                "Ignored a stale Apple Sign-In callback that no longer owns the authentication transition."
            )
            return
        }
        activeAttempt = nil

        guard let credential = authorization.credential
            as? ASAuthorizationAppleIDCredential else {
            attempt.completion(
                .failure(AppleOAuthAuthorizationError.invalidCredential)
            )
            return
        }

        do {
            attempt.completion(
                .success(
                    try Self.authorization(
                        identityToken: credential.identityToken,
                        authorizationCode: credential.authorizationCode,
                        fullName: credential.fullName,
                        nonce: attempt.nonce,
                        registrationID: dependencies.registrationID()
                    )
                )
            )
        } catch {
            attempt.completion(.failure(error))
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        guard let attempt = activeAttempt,
              controller === attempt.controller else {
            return
        }
        activeAttempt = nil
        attempt.completion(.failure(error))
    }
}

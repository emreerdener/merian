import Foundation

struct OAuthSignInCredentials: Equatable, Sendable {
    let provider: AuthTransitionProvider
    let idToken: String
    let accessToken: String?
    let nonce: String?
}

struct AppleOAuthCredentialRegistration: Equatable, Sendable {
    let registrationID: UUID
    let authorizationCode: String
}

struct OAuthProviderAuthorization: Equatable, Sendable {
    let credentials: OAuthSignInCredentials
    let profileMetadata: OAuthProfileMetadata
    let appleCredentialRegistration: AppleOAuthCredentialRegistration?
}

enum GoogleOAuthAuthorizationOutcome: Equatable, Sendable {
    case presentationUnavailable
    case missingIdentityToken
    case authorized(OAuthProviderAuthorization)
}

enum AppleOAuthAuthorizationError: LocalizedError, Equatable {
    case authorizationAlreadyInProgress
    case invalidCredential
    case invalidAuthorizationCodeEncoding
    case invalidIdentityTokenEncoding
    case missingAuthorizationCode
    case missingIdentityToken
    case nonceGenerationFailed(Int32)
    case presentationUnavailable

    var errorDescription: String? {
        switch self {
        case .authorizationAlreadyInProgress:
            "An Apple Sign-In request is already in progress."
        case .invalidCredential:
            "Apple Sign-In returned an unsupported credential."
        case .invalidAuthorizationCodeEncoding:
            "Apple Sign-In returned an invalid authorization code."
        case .invalidIdentityTokenEncoding:
            "Apple Sign-In returned an invalid identity token."
        case .missingAuthorizationCode:
            "Apple Sign-In did not return an authorization code."
        case .missingIdentityToken:
            "Apple Sign-In did not return an identity token."
        case .nonceGenerationFailed(let status):
            "Failed to generate an Apple Sign-In nonce (\(status))."
        case .presentationUnavailable:
            "Apple Sign-In could not find a presentation anchor."
        }
    }
}

enum OAuthProviderSignInDiagnostic: Equatable, Sendable {
    case appleBootstrapFailed
    case appleInvalidAuthorizationCode
    case appleInvalidCredential
    case appleInvalidIdentityToken
    case appleMissingAuthorizationCode
    case appleMissingIdentityToken
    case applePresentationUnavailable
    case appleProviderFailed
    case appleStaleCallback
    case completed(AuthTransitionProvider)
    case completionFailed(AuthTransitionProvider)
    case googleMissingIdentityToken
    case googlePresentationUnavailable
    case transitionRejected(AuthTransitionProvider)
}

struct OAuthSignInSession: Equatable, Sendable {
    let identity: AuthTransitionSession

    var userID: UUID {
        identity.userID
    }

    var isAnonymous: Bool {
        identity.isAnonymous
    }
}

struct OAuthSignInCompletion: Equatable, Sendable {
    let previousUserID: String?
    let session: OAuthSignInSession
}

enum OAuthSessionReplacementDisposition: Equatable, Sendable {
    case installed
    case failed
    case cancelled
}

struct OAuthProfileMetadata: Equatable, Sendable {
    let displayName: String?
    let givenName: String?
    let familyName: String?
    let avatarURL: String?

    init(
        displayName: String? = nil,
        givenName: String? = nil,
        familyName: String? = nil,
        avatarURL: String? = nil
    ) {
        self.displayName = Self.normalized(displayName)
        self.givenName = Self.normalized(givenName)
        self.familyName = Self.normalized(familyName)
        self.avatarURL = Self.normalized(avatarURL)
    }

    init(appleNameComponents components: PersonNameComponents?) {
        guard let components else {
            self.init()
            return
        }

        let formatter = PersonNameComponentsFormatter()
        formatter.style = .medium
        let formatted = Self.normalized(formatter.string(from: components))
        let fallback = [components.givenName, components.familyName]
            .compactMap(Self.normalized)
            .joined(separator: " ")

        self.init(
            displayName: formatted ?? Self.normalized(fallback),
            givenName: components.givenName,
            familyName: components.familyName
        )
    }

    var isEmpty: Bool {
        displayName == nil
            && givenName == nil
            && familyName == nil
            && avatarURL == nil
    }

    private static func normalized(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !normalized.isEmpty else {
            return nil
        }
        return normalized
    }
}

enum OAuthSignInWorkflowError: LocalizedError {
    case invalidAppleCredentialRegistrationReceipt
    case invalidProviderCredentialRegistrationConfiguration
    case providerTransitionMismatch

    var errorDescription: String? {
        switch self {
        case .invalidAppleCredentialRegistrationReceipt:
            "The Apple credential registration response was invalid."
        case .invalidProviderCredentialRegistrationConfiguration:
            "The identity provider credential registration configuration was invalid."
        case .providerTransitionMismatch:
            "The identity provider did not match the active authentication transition."
        }
    }
}

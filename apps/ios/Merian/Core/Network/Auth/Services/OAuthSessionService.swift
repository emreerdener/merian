import Foundation
import Supabase

/// Adapts provider-neutral OAuth values to the Supabase Auth SDK. Transition
/// ownership, replacement reconciliation, and observable state publication
/// remain with the Auth facade and coordinators.
@MainActor
struct OAuthSessionService {
    typealias ReadSessionOperation = @MainActor () async throws -> Session
    typealias CurrentSessionOperation = @MainActor () -> Session?
    typealias LinkIdentityOperation = @MainActor (
        OpenIDConnectCredentials
    ) async throws -> Void
    typealias InstallSessionOperation = @MainActor (
        OpenIDConnectCredentials
    ) async throws -> Session
    typealias UpdateProfileOperation = @MainActor (
        UserAttributes
    ) async throws -> User

    private let readSessionOperation: ReadSessionOperation
    private let currentSessionOperation: CurrentSessionOperation
    private let linkIdentityOperation: LinkIdentityOperation
    private let installSessionOperation: InstallSessionOperation
    private let updateProfileOperation: UpdateProfileOperation

    init(
        readSession: @escaping ReadSessionOperation,
        currentSession: @escaping CurrentSessionOperation,
        linkIdentity: @escaping LinkIdentityOperation,
        installSession: @escaping InstallSessionOperation,
        updateProfile: @escaping UpdateProfileOperation
    ) {
        readSessionOperation = readSession
        currentSessionOperation = currentSession
        linkIdentityOperation = linkIdentity
        installSessionOperation = installSession
        updateProfileOperation = updateProfile
    }

    func readSession() async throws -> Session {
        try await readSessionOperation()
    }

    func currentSession() -> Session? {
        currentSessionOperation()
    }

    func linkIdentity(
        using credentials: OAuthSignInCredentials
    ) async throws {
        try await linkIdentityOperation(
            Self.openIDConnectCredentials(from: credentials)
        )
    }

    func installSession(
        using credentials: OAuthSignInCredentials
    ) async throws -> Session {
        try await installSessionOperation(
            Self.openIDConnectCredentials(from: credentials)
        )
    }

    func updateProfileMetadata(
        _ metadata: OAuthProfileMetadata
    ) async throws -> User? {
        guard let attributes = Self.userAttributes(from: metadata) else {
            return nil
        }
        return try await updateProfileOperation(attributes)
    }

    func signInSession(from session: Session) -> OAuthSignInSession {
        OAuthSignInSession(
            identity: AuthTransitionSession(
                userID: session.user.id,
                isAnonymous: session.user.isAnonymous
            )
        )
    }

    private static func openIDConnectCredentials(
        from credentials: OAuthSignInCredentials
    ) -> OpenIDConnectCredentials {
        let provider: OpenIDConnectCredentials.Provider =
            switch credentials.provider {
            case .apple:
                .apple
            case .google:
                .google
            }
        return OpenIDConnectCredentials(
            provider: provider,
            idToken: credentials.idToken,
            accessToken: credentials.accessToken,
            nonce: credentials.nonce
        )
    }

    private static func userAttributes(
        from metadata: OAuthProfileMetadata
    ) -> UserAttributes? {
        var values: [String: AnyJSON] = [:]
        if let displayName = metadata.displayName {
            values["full_name"] = .string(displayName)
            values["name"] = .string(displayName)
        }
        if let givenName = metadata.givenName {
            values["given_name"] = .string(givenName)
        }
        if let familyName = metadata.familyName {
            values["family_name"] = .string(familyName)
        }
        if let avatarURL = metadata.avatarURL {
            values["avatar_url"] = .string(avatarURL)
            values["picture"] = .string(avatarURL)
        }
        guard !values.isEmpty else { return nil }
        return UserAttributes(data: values)
    }
}

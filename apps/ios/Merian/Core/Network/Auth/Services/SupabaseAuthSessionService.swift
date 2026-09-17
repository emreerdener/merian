import Foundation
import Supabase

/// One Supabase Auth session projected for provider-neutral recovery policy.
/// The SDK user remains available only for facade-owned adoption, publication,
/// public-author refresh, purchase-identity, entitlement, and generation-fence
/// effects.
@MainActor
struct AuthSessionRecoveryLiveSession {
    let user: User
    let identity: AuthTransitionSession
}

/// The request-scoped Supabase Auth operations used by OAuth, recovery, and
/// local sign-out. Listener lifetime and anonymous bootstrap remain with their
/// focused owners because they have independent task and replay semantics.
@MainActor
struct SupabaseAuthSessionOperations {
    let readSession: @MainActor () async throws -> Session
    let currentSession: @MainActor () -> Session?
    let refreshSession: @MainActor () async throws -> Session
    let signOutLocal: @MainActor () async throws -> Void
    let linkIdentity: @MainActor (
        OpenIDConnectCredentials
    ) async throws -> Void
    let installSession: @MainActor (
        OpenIDConnectCredentials
    ) async throws -> Session
    let installCallbackSession: @MainActor (URL) async throws -> Session
    let updateProfile: @MainActor (UserAttributes) async throws -> User
}

/// Centralizes stateless, request-scoped Supabase Auth SDK adaptation without
/// acquiring a singleton or owning asynchronous work. Product sequencing,
/// transition admission, cancellation, and observable state remain with the
/// focused coordinators and Auth facade.
@MainActor
struct SupabaseAuthSessionService {
    private let operations: SupabaseAuthSessionOperations

    init(operations: SupabaseAuthSessionOperations) {
        self.operations = operations
    }

    func readSession() async throws -> Session {
        try await operations.readSession()
    }

    func currentSession() -> Session? {
        operations.currentSession()
    }

    func refreshRecoverySession() async throws
        -> AuthSessionRecoveryLiveSession {
        Self.recoverySession(from: try await operations.refreshSession())
    }

    func loadRecoverySession() async throws
        -> AuthSessionRecoveryLiveSession {
        Self.recoverySession(from: try await operations.readSession())
    }

    func signOutLocal() async throws {
        try await operations.signOutLocal()
    }

    func linkIdentity(
        using credentials: OAuthSignInCredentials
    ) async throws {
        try await operations.linkIdentity(
            Self.openIDConnectCredentials(from: credentials)
        )
    }

    func installSession(
        using credentials: OAuthSignInCredentials
    ) async throws -> Session {
        try await operations.installSession(
            Self.openIDConnectCredentials(from: credentials)
        )
    }

    func installCallbackSession(from url: URL) async throws -> Session {
        try await operations.installCallbackSession(url)
    }

    func updateProfileMetadata(
        _ metadata: OAuthProfileMetadata
    ) async throws -> User? {
        guard let attributes = Self.userAttributes(from: metadata) else {
            return nil
        }
        return try await operations.updateProfile(attributes)
    }

    func signInSession(from session: Session) -> OAuthSignInSession {
        OAuthSignInSession(
            identity: AuthTransitionSession(
                userID: session.user.id,
                isAnonymous: session.user.isAnonymous
            )
        )
    }

    private static func recoverySession(
        from session: Session
    ) -> AuthSessionRecoveryLiveSession {
        AuthSessionRecoveryLiveSession(
            user: session.user,
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

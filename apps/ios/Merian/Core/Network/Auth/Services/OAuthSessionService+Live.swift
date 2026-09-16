import Supabase

extension OAuthSessionService {
    static func live(client: SupabaseClient) -> Self {
        Self(
            readSession: {
                try await client.auth.session
            },
            currentSession: {
                client.auth.currentSession
            },
            linkIdentity: { credentials in
                _ = try await client.auth.linkIdentityWithIdToken(
                    credentials: credentials
                )
            },
            installSession: { credentials in
                try await client.auth.signInWithIdToken(
                    credentials: credentials
                )
            },
            updateProfile: { attributes in
                try await client.auth.update(user: attributes)
            }
        )
    }
}

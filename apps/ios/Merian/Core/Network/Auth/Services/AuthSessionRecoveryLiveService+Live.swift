import Supabase

extension AuthSessionRecoveryLiveService {
    static func live(client: SupabaseClient) -> Self {
        Self(
            refreshSession: {
                try await client.auth.refreshSession()
            },
            readSession: {
                try await client.auth.session
            },
            localSignOut: {
                try await client.auth.signOut(scope: .local)
            }
        )
    }
}

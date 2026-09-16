import Supabase

extension AuthSessionBootstrapLiveService {
    static func live(client: SupabaseClient) -> Self {
        Self(
            readSession: {
                try await client.auth.session
            },
            currentSession: {
                client.auth.currentSession
            },
            createAnonymousSession: {
                try await client.auth.signInAnonymously()
            }
        )
    }
}

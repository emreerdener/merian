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
                guard !MerianEnvironment.isHistoryQualificationBuild else { throw MerianEnvironment.HistoryQualificationFailure.accounts }
                return try await client.auth.signInAnonymously()
            }
        )
    }
}

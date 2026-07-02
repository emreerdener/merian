import Foundation
import Supabase

enum MerianSupabaseClientFactory {
    static func makeClient(emitLocalSessionAsInitialSession: Bool = true) -> SupabaseClient {
        let url = URL(string: MerianEnvironment.supabaseUrl) ?? URL(string: MerianEnvironment.fallbackSupabaseURL)!
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: MerianEnvironment.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: KeychainLocalStorage(
                        service: ShareImportSharedConstants.supabaseKeychainService,
                        accessGroup: ShareImportAuthStore.keychainAccessGroup()
                    ),
                    emitLocalSessionAsInitialSession: emitLocalSessionAsInitialSession
                )
            )
        )
    }
}

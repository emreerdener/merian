import Foundation
import Supabase

enum MerianSupabaseClientFactory {
    static func makeClient(
        emitLocalSessionAsInitialSession: Bool = true,
        session: URLSession = .shared
    ) -> SupabaseClient {
        let url = SecureTransportPolicy.httpsURL(
            from: MerianEnvironment.supabaseUrl
        ) ?? SecureTransportPolicy.httpsURL(
            from: MerianEnvironment.fallbackSupabaseURL
        )!
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: MerianEnvironment.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: KeychainLocalStorage(),
                    emitLocalSessionAsInitialSession: emitLocalSessionAsInitialSession
                ),
                global: .init(
                    // History reads bypass the inference transports. Every SDK
                    // request must retain the same truthful reader capability.
                    headers: [IdentificationDispatchAuthorization.protocolHeader:
                        String(IdentificationDispatchAuthorization.currentProtocol)],
                    session: session
                )
            )
        )
    }
}

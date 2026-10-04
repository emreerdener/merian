import Foundation
import os
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
                    storage: makeAuthStorage(),
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

    static func makeAuthStorage() -> any AuthLocalStorage {
        #if DEBUG
        if TestExecutionCoordinator.isRunningTests {
            return ProcessLocalAuthStorage()
        }
        #endif
        return KeychainLocalStorage()
    }
}

#if DEBUG
/// Test clients must neither restore nor overwrite a simulator's saved session.
/// Each client owns its storage; explicitly installed test sessions still work.
private struct ProcessLocalAuthStorage: AuthLocalStorage {
    private let values = OSAllocatedUnfairLock(initialState: [String: Data]())

    func store(key: String, value: Data) throws {
        values.withLock { $0[key] = value }
    }

    func retrieve(key: String) throws -> Data? {
        values.withLock { $0[key] }
    }

    func remove(key: String) throws {
        values.withLock { _ = $0.removeValue(forKey: key) }
    }
}
#endif

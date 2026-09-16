import Supabase

extension AuthSessionLifecycleLiveProvider {
    static func live(client: SupabaseClient) -> Self {
        Self(
            startListening: { handler in
                let authStateChanges = client.auth.authStateChanges
                return Task { @MainActor in
                    for await state in authStateChanges {
                        guard !Task.isCancelled else { return }
                        await handler(
                            AuthSessionLifecycleSDKState(
                                user: state.session?.user,
                                isExpired:
                                    state.session?.isExpired ?? false,
                                origin: state.event == .initialSession
                                    ? .initialRestoration
                                    : .runtimeTransition
                            )
                        )
                    }
                }
            },
            currentState: {
                let session = client.auth.currentSession
                return AuthSessionLifecycleSDKState(
                    user: session?.user,
                    isExpired: session?.isExpired ?? false,
                    origin: .runtimeTransition
                )
            }
        )
    }
}

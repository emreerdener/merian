import Foundation

/// Projects the authenticated account solely for local registration
/// coalescing. The identifier never enters the push registration payload.
@MainActor
struct PushRegistrationContextService {
    let currentAccountScopeID: @MainActor () -> String?

    static var live: Self {
        Self(
            currentAccountScopeID: {
                SupabaseManager.shared.client.auth.currentSession?.user.id
                    .uuidString.lowercased()
            }
        )
    }
}

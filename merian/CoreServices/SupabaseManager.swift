import Foundation
import Supabase

/// Manages the global Supabase connection and core Authentication states for Ghost Users
@MainActor
final class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()
    
    let client: SupabaseClient
    
    @Published var currentUser: User?
    @Published var isAuthenticated: Bool = false
    
    private init() {
        guard let url = URL(string: MerianEnvironment.supabaseUrl) else {
            fatalError("CRITICAL EXCEPTION: Invalid Supabase URL in environment configuration")
        }
        
        self.client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: MerianEnvironment.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
        
        Task {
            await self.setupAuthStateListener()
        }
    }
    
    /// Monitors Session tokens and updates the UI layer reactively
    private func setupAuthStateListener() async {
        for await state in client.auth.authStateChanges {
            if let session = state.session, !session.isExpired {
                self.currentUser = session.user
                self.isAuthenticated = true
            } else {
                self.currentUser = nil
                self.isAuthenticated = false
            }
            
            print("🔐 Supabase Auth Event: \(state.event) | Authenticated: \(self.isAuthenticated)")
        }
    }
    
    /// Initializes an Anonymous session for new users prior to any sign-in. Matches the "Ghost User / Explorer Tier" architecture.
    func initializeGhostSession() async {
        do {
            // Check if they are already actively signed in (either as a Ghost or an Authenticated Apple user)
            _ = try await client.auth.session
            print("👻 Active Merian User Identity already resolved natively on device.")
            await RevenueCatManager.shared.linkWithSupabase(userId: DeviceIdentityManager.shared.deviceId)
            PostHogManager.shared.identifyUser(userId: DeviceIdentityManager.shared.deviceId)
        } catch {
            let errString = String(describing: error)
            
            // If the user's session merely timed out offline or threw a Network Error, NEVER sign in anonymously.
            // This prevents permanently erasing their Apple Sign-In and RevenueCat Pro Subscription boundaries natively.
            if let authError = error as? AuthError, case .sessionNotFound = authError {
                do {
                    let authResponse = try await client.auth.signInAnonymously()
                    print("👻 Successfully established new Ghost User Identity: \(authResponse.user.id.uuidString)")
                    await RevenueCatManager.shared.linkWithSupabase(userId: DeviceIdentityManager.shared.deviceId)
                    PostHogManager.shared.identifyUser(userId: DeviceIdentityManager.shared.deviceId)
                } catch {
                    print("⚠️ Failed to establish Anonymous Supabase Session: \(error.localizedDescription)")
                }
            } else if errString.contains("sessionNotFound") || errString.contains("sessionMissing") {
                do {
                    let authResponse = try await client.auth.signInAnonymously()
                    print("👻 Successfully established new Ghost User Identity: \(authResponse.user.id.uuidString)")
                    await RevenueCatManager.shared.linkWithSupabase(userId: DeviceIdentityManager.shared.deviceId)
                    PostHogManager.shared.identifyUser(userId: DeviceIdentityManager.shared.deviceId)
                } catch {
                    print("⚠️ Failed to establish Anonymous Supabase Session: \(error.localizedDescription)")
                }
            } else {
                print("⚠️ Bypassed Anonymous Sign-In: Existing user identity bounds protected despite network/expiration failure.")
            }
        }
    }
    
    /// Signs a user out of their session, defaulting them back to an unauthenticated physical state
    func signOut() async {
        do {
            try await client.auth.signOut()
            PostHogManager.shared.reset()
            print("User actively signed out and token flushed")
        } catch {
            print("⚠️ Failed to purge local Supabase Auth state: \(error.localizedDescription)")
        }
    }
    
    /// Securely resolves the local JWT token out of the active user session structure.
    func getActiveJWT() async throws -> String {
        let session = try await client.auth.session
        return session.accessToken
    }
}

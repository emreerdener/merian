import Foundation
import AuthenticationServices
import CryptoKit
import Supabase
import GoogleSignIn
import RevenueCat
import Observation
import os

// MARK: - Core Auth & Network Engine
/// Manages the global Supabase connection and core Authentication states for Ghost Users
@MainActor
@Observable final class SupabaseManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    // MARK: - Singleton Architecture
    static let shared = SupabaseManager()
    
    // MARK: - Auth Client Pipeline
    let client: SupabaseClient
    
    // MARK: - State Management
    var currentUser: User?
    var isAuthenticated: Bool = false
    
    var isGuestUser: Bool {
        currentUser?.isAnonymous ?? true
    }
    
    // MARK: - Cryptographic Signatures
    private var currentNonce: String?
    private var activeAppleAuth: ASAuthorizationController?
    
    private override init() {
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
        
        super.init()
        
        Task {
            await self.setupAuthStateListener()
        }
    }
    
    // MARK: - Session Orchestration
    /// Monitors Session tokens and updates the UI layer reactively
    private func setupAuthStateListener() async {
        for await state in client.auth.authStateChanges {
            if let session = state.session, !session.isExpired {
                self.currentUser = session.user
                self.isAuthenticated = true
                
                await self.linkExternalTelemetry(user: session.user)
                
                // Trigger historical profile synchronization inherently capturing Re-installs natively
                if let context = AppDIContainer.shared.offlineQueueManager.modelContext {
                    Task { await AppDIContainer.shared.scanRepository.syncHistoricalScansDown(modelContext: context) }
                }
            } else {
                self.currentUser = nil
                self.isAuthenticated = false
            }
            
            MerianLog.auth.debug("🔐 Supabase Auth Event: \(String(describing: state.event), privacy: .public) | Authenticated: \(self.isAuthenticated, privacy: .private)")
        }
    }
    
    private func linkExternalTelemetry(user: User) async {
        let userId = user.id.uuidString
        let email = user.email
        let fullName = user.userMetadata["full_name"]?.stringValue ?? user.userMetadata["name"]?.stringValue
        let avatarUrl = user.userMetadata["avatar_url"]?.stringValue ?? user.userMetadata["picture"]?.stringValue
        
        await RevenueCatManager.shared.linkWithSupabase(
            userId: userId,
            email: email,
            displayName: fullName,
            avatarUrl: avatarUrl
        )
        PostHogManager.shared.identifyUser(userId: userId)
    }
    
    // MARK: - Ghost Profile Architecture
    /// Initializes an Anonymous session for new users prior to any sign-in. Matches the "Ghost User / Explorer Tier" architecture.
    func initializeGhostSession() async {
        do {
            // Check if they are already actively signed in (either as a Ghost or an Authenticated Apple user)
            let session = try await client.auth.session
            MerianLog.auth.debug("👻 Active Merian User Identity already resolved natively on device.")
            await linkExternalTelemetry(user: session.user)
        } catch {
            let errString = String(describing: error)
            
            // If the user's session merely timed out offline or threw a Network Error, NEVER sign in anonymously.
            // This prevents permanently erasing their Apple Sign-In and RevenueCat Pro Subscription boundaries natively.
            if let authError = error as? AuthError, case .sessionMissing = authError {
                do {
                    let authResponse = try await client.auth.signInAnonymously()
                    MerianLog.auth.debug("👻 Successfully established new Ghost User Identity: \(authResponse.user.id.uuidString, privacy: .private)")
                    await linkExternalTelemetry(user: authResponse.user)
                } catch {
                    MerianLog.auth.debug("⚠️ Failed to establish Anonymous Supabase Session: \(error.localizedDescription, privacy: .private)")
                }
            } else if errString.contains("sessionNotFound") || errString.contains("sessionMissing") {
                do {
                    let authResponse = try await client.auth.signInAnonymously()
                    MerianLog.auth.debug("👻 Successfully established new Ghost User Identity: \(authResponse.user.id.uuidString, privacy: .private)")
                    await linkExternalTelemetry(user: authResponse.user)
                } catch {
                    MerianLog.auth.debug("⚠️ Failed to establish Anonymous Supabase Session: \(error.localizedDescription, privacy: .private)")
                }
            } else {
                MerianLog.auth.debug("⚠️ Bypassed Anonymous Sign-In: Existing user identity bounds protected despite network/expiration failure.")
            }
        }
    }
    
    // MARK: - Secure Authentication Utilities
    /// Signs a user out of their session, defaulting them back to an unauthenticated physical state
    func signOut() async {
        do {
            try await client.auth.signOut()
            PostHogManager.shared.reset()
            _ = try? await Purchases.shared.logOut()
            KeychainManager.shared.removeObject(forKey: "Merian_HasAuthenticatedOAuth")
            MerianLog.auth.debug("User actively signed out and token flushed")
        } catch {
            MerianLog.auth.debug("⚠️ Failed to purge local Supabase Auth state: \(error.localizedDescription, privacy: .private)")
        }
    }
    
    /// Securely resolves the local JWT token out of the active user session structure.
    func getActiveJWT() async throws -> String {
        let session = try await client.auth.session
        return session.accessToken
    }
    
    /// Unifies the JWT extraction, OAuth Ghost fallbacks, and generic REST header injection, aggressively stripping duplicated catch structures across Network clients natively
    func getValidAuthHeaders() async throws -> [String: String] {
        var token: String
        do {
            token = try await self.getActiveJWT()
        } catch {
            let hasAuthenticated = KeychainManager.shared.bool(forKey: "Merian_HasAuthenticatedOAuth")
            if !hasAuthenticated {
                await self.initializeGhostSession()
                token = try await self.getActiveJWT()
            } else {
                throw error
            }
        }
        
        return [
            "Authorization": "Bearer \(token)",
            "apikey": MerianEnvironment.supabaseAnonKey,
            "Content-Type": "application/json"
        ]
    }
    
    // MARK: - OAuth & Apple Sign In
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let windowScene = scenes.first else {
            fatalError("No valid UIWindowScene available for authentication.")
        }
        return scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? ASPresentationAnchor(windowScene: windowScene)
    }
    private func getRootViewController() -> UIViewController? {
        guard let screen = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return nil }
        return screen.windows.first(where: { $0.isKeyWindow })?.rootViewController
    }
    
    private func finalizeOAuthLogin(provider: OpenIDConnectCredentials.Provider, idToken: String, accessToken: String?, nonce: String?) async throws {
        if self.isGuestUser {
            let ghostId = try? await client.auth.session.user.id.uuidString
            do {
                _ = try await client.auth.linkIdentityWithIdToken(
                    credentials: .init(provider: provider, idToken: idToken, accessToken: accessToken, nonce: nonce)
                )
            } catch {
                _ = try await client.auth.signInWithIdToken(
                    credentials: .init(provider: provider, idToken: idToken, accessToken: accessToken, nonce: nonce)
                )
                if let ghostId = ghostId {
                    await triggerGhostProfileMerge(from: ghostId)
                }
            }
        } else {
            _ = try await client.auth.signInWithIdToken(
                credentials: .init(provider: provider, idToken: idToken, accessToken: accessToken, nonce: nonce)
            )
        }
    }
    
    func signInWithGoogle() async {
        guard let rootVC = getRootViewController() else {
            MerianLog.auth.debug("Failed to find root view controller for Google Sign In")
            return
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
            guard let idToken = result.user.idToken?.tokenString else {
                MerianLog.auth.debug("No idToken found.")
                return
            }
            let accessToken = result.user.accessToken.tokenString
            
            try await self.finalizeOAuthLogin(provider: .google, idToken: idToken, accessToken: accessToken, nonce: nil)
            let session = try await client.auth.session
            await linkExternalTelemetry(user: session.user)
            
            KeychainManager.shared.set(true, forKey: "Merian_HasAuthenticatedOAuth")
            
            MerianLog.auth.debug("Google Sign In complete!")
        } catch {
            MerianLog.auth.debug("Google Sign In Cancelled or Error: \(error.localizedDescription, privacy: .private)")
        }
    }
    
    private func triggerGhostProfileMerge(from ghostId: String) async {
        struct GhostPayload: Encodable {
            let ghost_id: String
        }
        do {
            let _ = try await client.functions.invoke(
                "merge-ghost-profile",
                options: .init(body: GhostPayload(ghost_id: ghostId))
            )
            MerianLog.auth.debug("Ghost Profile explicitly merged via Edge natively for \(ghostId, privacy: .private)")
        } catch {
            MerianLog.auth.debug("Ghost profile merge failed over Edge bounds: \(error.localizedDescription, privacy: .private)")
        }
    }
    
    // MARK: - Native Apple Sign In Helpers
    func startAppleSignIn() {
        let nonce = randomNonceString()
        currentNonce = nonce
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        
        // Retain strongly to avoid premature deallocation during the sign-in flow
        self.activeAppleAuth = authorizationController 
        authorizationController.performRequests()
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        let maxValidValue = UInt8(charset.count * (256 / charset.count))
        
        var nonce = ""
        nonce.reserveCapacity(length)
        
        while nonce.count < length {
            var buffer = [UInt8](repeating: 0, count: length - nonce.count)
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
            if errorCode != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
            }
            
            for byte in buffer {
                if byte < maxValidValue {
                    nonce.append(charset[Int(byte) % charset.count])
                    if nonce.count == length { break }
                }
            }
        }
        
        return nonce
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        return hashString
    }
}

// MARK: - ASAuthorizationControllerDelegate
extension SupabaseManager: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let windowScene = scenes.first else {
            fatalError("No valid UIWindowScene available for authentication.")
        }
        return scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? ASPresentationAnchor(windowScene: windowScene)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        self.activeAppleAuth = nil
        
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            guard let nonce = currentNonce else {
                fatalError("Invalid state: A login callback was received, but no login request was sent.")
            }
            guard let appleIDToken = appleIDCredential.identityToken else {
                MerianLog.auth.debug("Unable to fetch identity token")
                return
            }
            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                MerianLog.auth.debug("Unable to serialize token string from data: \(appleIDToken.debugDescription, privacy: .private)")
                return
            }
            
            Task {
                do {
                    try await self.finalizeOAuthLogin(provider: .apple, idToken: idTokenString, accessToken: nil, nonce: nonce)
                    let session = try await client.auth.session
                    await linkExternalTelemetry(user: session.user)
                    
                    KeychainManager.shared.set(true, forKey: "Merian_HasAuthenticatedOAuth")
                    
                    MerianLog.auth.debug("Apple Sign In complete!")
                } catch {
                    MerianLog.auth.debug("Failed to authenticate Apple token with Supabase: \(error.localizedDescription, privacy: .private)")
                }
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        self.activeAppleAuth = nil
        MerianLog.auth.debug("Apple Sign In error: \(error.localizedDescription, privacy: .private)")
    }
}

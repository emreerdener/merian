import Foundation
import AuthenticationServices
import CryptoKit
import Supabase
import GoogleSignIn
import RevenueCat

/// Manages the global Supabase connection and core Authentication states for Ghost Users
@MainActor
final class SupabaseManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = SupabaseManager()
    
    let client: SupabaseClient
    
    @Published var currentUser: User?
    @Published var isAuthenticated: Bool = false
    
    var isGuestUser: Bool {
        currentUser?.isAnonymous ?? true
    }
    
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
    
    /// Monitors Session tokens and updates the UI layer reactively
    private func setupAuthStateListener() async {
        for await state in client.auth.authStateChanges {
            if let session = state.session, !session.isExpired {
                self.currentUser = session.user
                self.isAuthenticated = true
                
                // Trigger historical profile synchronization inherently capturing Re-installs natively
                if let context = AppDIContainer.shared.offlineQueueManager.modelContext {
                    Task { await AppDIContainer.shared.scanRepository.syncHistoricalScansDown(modelContext: context) }
                }
            } else {
                self.currentUser = nil
                self.isAuthenticated = false
            }
            
            print("🔐 Supabase Auth Event: \(state.event) | Authenticated: \(self.isAuthenticated)")
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
    
    /// Initializes an Anonymous session for new users prior to any sign-in. Matches the "Ghost User / Explorer Tier" architecture.
    func initializeGhostSession() async {
        do {
            // Check if they are already actively signed in (either as a Ghost or an Authenticated Apple user)
            let session = try await client.auth.session
            print("👻 Active Merian User Identity already resolved natively on device.")
            await linkExternalTelemetry(user: session.user)
        } catch {
            let errString = String(describing: error)
            
            // If the user's session merely timed out offline or threw a Network Error, NEVER sign in anonymously.
            // This prevents permanently erasing their Apple Sign-In and RevenueCat Pro Subscription boundaries natively.
            if let authError = error as? AuthError, case .sessionMissing = authError {
                do {
                    let authResponse = try await client.auth.signInAnonymously()
                    print("👻 Successfully established new Ghost User Identity: \(authResponse.user.id.uuidString)")
                    await linkExternalTelemetry(user: authResponse.user)
                } catch {
                    print("⚠️ Failed to establish Anonymous Supabase Session: \(error.localizedDescription)")
                }
            } else if errString.contains("sessionNotFound") || errString.contains("sessionMissing") {
                do {
                    let authResponse = try await client.auth.signInAnonymously()
                    print("👻 Successfully established new Ghost User Identity: \(authResponse.user.id.uuidString)")
                    await linkExternalTelemetry(user: authResponse.user)
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
            _ = try? await Purchases.shared.logOut()
            UserDefaults.standard.removeObject(forKey: "Merian_HasAuthenticatedOAuth")
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
    
    func signInWithGoogle() async {
        guard let rootVC = getRootViewController() else {
            print("Failed to find root view controller for Google Sign In")
            return
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
            guard let idToken = result.user.idToken?.tokenString else {
                print("No idToken found.")
                return
            }
            let accessToken = result.user.accessToken.tokenString
            
            if self.isGuestUser {
                let ghostId = try? await client.auth.session.user.id.uuidString
                do {
                    let _ = try await client.auth.linkIdentityWithIdToken(
                        credentials: .init(
                            provider: .google,
                            idToken: idToken,
                            accessToken: accessToken
                        )
                    )
                } catch {
                    let _ = try await client.auth.signInWithIdToken(
                        credentials: .init(
                            provider: .google,
                            idToken: idToken,
                            accessToken: accessToken
                        )
                    )
                    if let ghostId = ghostId {
                        await triggerGhostProfileMerge(from: ghostId)
                    }
                }
            } else {
                let _ = try await client.auth.signInWithIdToken(
                    credentials: .init(
                        provider: .google,
                        idToken: idToken,
                        accessToken: accessToken
                    )
                )
            }
            
            let session = try await client.auth.session
            await linkExternalTelemetry(user: session.user)
            
            UserDefaults.standard.set(true, forKey: "Merian_HasAuthenticatedOAuth")
            
            print("Google Sign In complete!")
        } catch {
            print("Google Sign In Cancelled or Error: \(error.localizedDescription)")
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
            print("Ghost Profile explicitly merged via Edge natively for \(ghostId)")
        } catch {
            print("Ghost profile merge failed over Edge bounds: \(error.localizedDescription)")
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
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }

        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            // Pick a random character from the set, wrapping around if needed.
            charset[Int(byte) % charset.count]
        }
        return String(nonce)
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
                print("Unable to fetch identity token")
                return
            }
            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                print("Unable to serialize token string from data: \(appleIDToken.debugDescription)")
                return
            }
            
            Task {
                do {
                    if self.isGuestUser {
                        let ghostId = try? await client.auth.session.user.id.uuidString
                        do {
                            let _ = try await client.auth.linkIdentityWithIdToken(
                                credentials: .init(
                                    provider: .apple, 
                                    idToken: idTokenString, 
                                    nonce: nonce
                                )
                            )
                        } catch {
                            let _ = try await client.auth.signInWithIdToken(
                                credentials: .init(provider: .apple, idToken: idTokenString, nonce: nonce)
                            )
                            if let ghostId = ghostId {
                                await triggerGhostProfileMerge(from: ghostId)
                            }
                        }
                    } else {
                        let _ = try await client.auth.signInWithIdToken(
                            credentials: .init(provider: .apple, idToken: idTokenString, nonce: nonce)
                        )
                    }
                    
                    let session = try await client.auth.session
                    await linkExternalTelemetry(user: session.user)
                    
                    UserDefaults.standard.set(true, forKey: "Merian_HasAuthenticatedOAuth")
                    
                    print("Apple Sign In complete!")
                } catch {
                    print("Failed to authenticate Apple token with Supabase: \(error.localizedDescription)")
                }
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        self.activeAppleAuth = nil
        print("Apple Sign In error: \(error.localizedDescription)")
    }
}

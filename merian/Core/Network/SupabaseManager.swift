import AuthenticationServices
import CryptoKit
import Foundation
import GoogleSignIn
import Observation
import os
import Supabase

// MARK: - Supabase Manager

/// Manages the global Supabase connection, auth state, and OAuth sign-in flows.
@MainActor
@Observable final class SupabaseManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    private enum AppleSignInBootstrapError: LocalizedError {
        case nonceGenerationFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .nonceGenerationFailed(let status):
                return "Failed to generate an Apple Sign-In nonce (\(status))."
            }
        }
    }

    // MARK: - Singleton Architecture
    static let shared = SupabaseManager()

    // MARK: - Client
    let client: SupabaseClient

    // MARK: - State
    var currentUser: User?
    var isAuthenticated: Bool = false

    var isGuestUser: Bool {
        currentUser?.isAnonymous ?? true
    }

    var currentUserAvatarUrl: URL? {
        guard let urlString = currentUser?.userMetadata["avatar_url"]?.stringValue ?? currentUser?.userMetadata["picture"]?.stringValue else {
            return nil
        }
        return URL(string: urlString)
    }

    // MARK: - Apple Sign-In State
    private var currentNonce: String?
    private var activeAppleAuth: ASAuthorizationController?

    // MARK: - Session Deduplication
    /// Tracks the last user ID for which external telemetry (RevenueCat, PostHog) was linked.
    /// Guards against the Supabase SDK emitting two auth events on cold start — one for the
    /// locally cached token and one when the server validates/refreshes it. Without this guard
    /// both events call linkWithSupabase and PostHog identify for the same user.
    private var lastLinkedUserId: String?

    /// Retained handle for the auth state listener task. Stored so the task can be cancelled
    /// on teardown and is consistent with the @ObservationIgnored task handle pattern used
    /// throughout the engine layer. Fire-and-forget tasks with no handle cannot be inspected,
    /// restarted, or cleanly shut down.
    @ObservationIgnored private var authListenerTask: Task<Void, Never>?
    /// Single-flight guard for anonymous session creation. Multiple callers can reach
    /// `initializeGhostSession()` while the first network round-trip is suspended; without this
    /// handle they each attempt a fresh anonymous sign-in and race to replace the active session.
    @ObservationIgnored private var ghostSessionTask: Task<Void, Never>?

    // MARK: - Initialization

    private override init() {
        if !MerianEnvironment.configurationIssues.isEmpty {
            let issues = MerianEnvironment.configurationIssues.map(\.description).joined(separator: " | ")
            MerianLog.auth.fault("Environment configuration degraded: \(issues, privacy: .public)")
        }

        if !TestExecutionCoordinator.isRunningTests {
            PostHogManager.shared.configure()
        }

        let url = URL(string: MerianEnvironment.supabaseUrl) ?? URL(string: MerianEnvironment.fallbackSupabaseURL)!
        self.client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: MerianEnvironment.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )

        super.init()

        self.authListenerTask = Task { await self.setupAuthStateListener() }
    }

    // MARK: - Auth State

    private func setupAuthStateListener() async {
        for await state in client.auth.authStateChanges {
            if let session = state.session, !session.isExpired {
                self.currentUser = session.user
                self.isAuthenticated = true

                if !TestExecutionCoordinator.isRunningTests,
                   await self.ensureTelemetryLinkedIfNeeded(for: session.user) {
                    // Only link telemetry and trigger historical sync when the active user
                    // identity actually changes. The Supabase SDK fires two auth events on
                    // cold start (local cache + server validation), both with the same user —
                    // skipping the duplicate avoids a redundant RevenueCat logIn round-trip,
                    // a duplicate PostHog identify, and a second concurrent historical sync.
                    // Sync historical scans on session restore to capture re-installs.
                    // Stamp lastHistoricalSyncDate here so AppLifecycleManager's 15-minute
                    // throttle gate sees this sync and skips its own redundant call — without
                    // this write both callers fire concurrently on every cold launch.
                    if let context = AppDIContainer.shared.offlineQueueManager.modelContext {
                        UserDefaults.standard.set(Date(), forKey: UserDefaultsKeys.lastHistoricalSyncDate)
                        Task {
                            await SpeciesPreferredNameRepository.syncCloudPreferences(modelContext: context)
                            await AppDIContainer.shared.scanRepository.syncHistoricalScansDown(modelContext: context)
                        }
                    }
                }
            } else {
                self.currentUser = nil
                self.isAuthenticated = false
                lastLinkedUserId = nil
            }

            MerianLog.auth.debug("Auth event: \(String(describing: state.event), privacy: .public) | authenticated: \(self.isAuthenticated, privacy: .private)")
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

    @discardableResult
    private func ensureTelemetryLinkedIfNeeded(for user: User) async -> Bool {
        let userId = user.id.uuidString
        guard userId != lastLinkedUserId else { return false }
        lastLinkedUserId = userId
        await linkExternalTelemetry(user: user)
        return true
    }

    // MARK: - Ghost Session

    /// Creates an anonymous session for new users. Skips creation if a session exists or
    /// if the error is network/expiry — preserving any existing Apple Sign-In identity.
    func initializeGhostSession() async {
        guard !TestExecutionCoordinator.isRunningTests else { return }

        if let existingTask = ghostSessionTask {
            await existingTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performGhostSessionInitialization()
            await MainActor.run { [weak self] in
                self?.ghostSessionTask = nil
            }
        }
        ghostSessionTask = task
        await task.value
    }

    private func performGhostSessionInitialization() async {
        do {
            let session = try await client.auth.session
            MerianLog.auth.debug("Existing session resolved on device.")
            _ = await ensureTelemetryLinkedIfNeeded(for: session.user)
        } catch {
            let errString = String(describing: error)

            // Only create a new anonymous session if the session is genuinely missing —
            // never on network failure, to avoid overwriting a real Apple/Google identity.
            let isSessionMissing: Bool = {
                if let authError = error as? AuthError, case .sessionMissing = authError { return true }
                return errString.contains("sessionNotFound") || errString.contains("sessionMissing")
            }()

            if isSessionMissing {
                do {
                    let authResponse = try await client.auth.signInAnonymously()
                    MerianLog.auth.debug("Ghost session established: \(authResponse.user.id.uuidString, privacy: .private)")
                    _ = await ensureTelemetryLinkedIfNeeded(for: authResponse.user)
                } catch {
                    MerianLog.auth.debug("Failed to establish ghost session: \(error.localizedDescription, privacy: .private)")
                }
            } else {
                MerianLog.auth.debug("Skipped anonymous sign-in — preserving existing identity despite network or expiration error.")
            }
        }
    }

    // MARK: - Session Utilities

    func signOut() async {
        defer {
            currentUser = nil
            isAuthenticated = false
            lastLinkedUserId = nil
            KeychainManager.shared.removeObject(forKey: KeychainKeys.hasAuthenticatedOAuth)
            PostHogManager.shared.reset()
        }

        do {
            try await client.auth.signOut()
        } catch {
            MerianLog.auth.debug("Supabase sign-out failed; continuing local cleanup: \(error.localizedDescription, privacy: .private)")
        }

        await RevenueCatManager.shared.handleSupabaseSignOut()
        MerianLog.auth.debug("User signed out.")
    }

    /// Returns the JWT access token from the active session.
    func getActiveJWT() async throws -> String {
        let session = try await client.auth.session
        return session.accessToken
    }

    /// Attempts to refresh the locally stored Supabase session after an Edge
    /// function reports that the backing Auth session is missing.
    @discardableResult
    func refreshActiveSessionForRetry() async -> Bool {
        do {
            let session = try await client.auth.refreshSession()
            currentUser = session.user
            isAuthenticated = true
            _ = await ensureTelemetryLinkedIfNeeded(for: session.user)
            MerianLog.auth.debug("Supabase session refreshed after auth failure.")
            return true
        } catch {
            MerianLog.auth.debug("Supabase session refresh after auth failure failed: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    /// Clears a broken anonymous session and creates a fresh ghost identity.
    @discardableResult
    func resetGhostSessionForRetry() async -> Bool {
        await signOut()
        await initializeGhostSession()

        do {
            let session = try await client.auth.session
            currentUser = session.user
            isAuthenticated = true
            MerianLog.auth.debug("Ghost session regenerated after auth failure.")
            return true
        } catch {
            MerianLog.auth.debug("Ghost session regeneration after auth failure failed: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    func clearLocalSessionAfterAuthFailure() async {
        do {
            try await client.auth.signOut(scope: .local)
        } catch {
            MerianLog.auth.debug("Local Supabase sign-out after auth failure failed: \(error.localizedDescription, privacy: .private)")
        }

        currentUser = nil
        isAuthenticated = false
        lastLinkedUserId = nil
        KeychainManager.shared.removeObject(forKey: KeychainKeys.hasAuthenticatedOAuth)
        PostHogManager.shared.reset()
        await RevenueCatManager.shared.handleSupabaseSignOut()
        MerianLog.auth.debug("Cleared local Supabase session after auth failure.")
    }

    /// Builds authenticated REST headers, initializing a ghost session if no token exists.
    func getValidAuthHeaders() async throws -> [String: String] {
        if TestExecutionCoordinator.isRunningTests {
            return [
                "Authorization": "Bearer merian-test-session",
                "apikey": MerianEnvironment.supabaseAnonKey,
                "Content-Type": "application/json"
            ]
        }

        var token: String
        do {
            token = try await self.getActiveJWT()
        } catch {
            let hasAuthenticated = KeychainManager.shared.bool(forKey: KeychainKeys.hasAuthenticatedOAuth)
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

    // MARK: - Google Sign-In

    func signInWithGoogle() async {
        guard let rootVC = getRootViewController() else {
            MerianLog.auth.debug("Failed to find root view controller for Google Sign-In.")
            return
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
            guard let idToken = result.user.idToken?.tokenString else {
                MerianLog.auth.debug("Google Sign-In: no ID token returned.")
                return
            }
            let accessToken = result.user.accessToken.tokenString

            try await self.finalizeOAuthLogin(provider: .google, idToken: idToken, accessToken: accessToken, nonce: nil)
            let session = try await client.auth.session
            _ = await ensureTelemetryLinkedIfNeeded(for: session.user)

            KeychainManager.shared.set(true, forKey: KeychainKeys.hasAuthenticatedOAuth)
            MerianLog.auth.debug("Google Sign-In complete.")
        } catch {
            MerianLog.auth.debug("Google Sign-In failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    // MARK: - Apple Sign-In

    func startAppleSignIn() {
        let nonce: String
        do {
            nonce = try randomNonceString()
        } catch {
            currentNonce = nil
            MerianLog.auth.error("Apple Sign-In bootstrap failed: \(error.localizedDescription, privacy: .private)")
            return
        }
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        guard keyWindowAnchor() != nil else {
            currentNonce = nil
            MerianLog.auth.error("Apple Sign-In aborted because no presentation anchor is available.")
            return
        }

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        // Retained strongly to avoid deallocation during the sign-in flow.
        self.activeAppleAuth = controller
        controller.performRequests()
    }

    // MARK: - Private OAuth Helpers

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

    private func triggerGhostProfileMerge(from ghostId: String) async {
        struct GhostPayload: Encodable { let ghost_id: String }
        do {
            _ = try await client.functions.invoke(
                "merge-ghost-profile",
                options: .init(body: GhostPayload(ghost_id: ghostId))
            )
            MerianLog.auth.debug("Ghost profile merged for \(ghostId, privacy: .private)")
        } catch {
            MerianLog.auth.debug("Ghost profile merge failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func getRootViewController() -> UIViewController? {
        guard let screen = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return nil }
        return screen.windows.first(where: { $0.isKeyWindow })?.rootViewController
    }

    /// Shared key-window anchor used by both ASWebAuthentication and ASAuthorizationController delegates.
    private func keyWindowAnchor() -> ASPresentationAnchor? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return keyWindow
        }
        if let firstWindow = scenes.flatMap(\.windows).first {
            return firstWindow
        }
        if let windowScene = scenes.first {
            return ASPresentationAnchor(windowScene: windowScene)
        }

        MerianLog.auth.error("No UIWindowScene available for authentication presentation.")
        return nil
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        keyWindowAnchor() ?? ASPresentationAnchor()
    }

    // MARK: - Cryptographic Utilities

    private func randomNonceString(length: Int = 32) throws -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        let maxValidValue = UInt8(charset.count * (256 / charset.count))

        var nonce = ""
        nonce.reserveCapacity(length)

        while nonce.count < length {
            var buffer = [UInt8](repeating: 0, count: length - nonce.count)
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
            if errorCode != errSecSuccess {
                throw AppleSignInBootstrapError.nonceGenerationFailed(errorCode)
            }
            for byte in buffer where byte < maxValidValue {
                nonce.append(charset[Int(byte) % charset.count])
                if nonce.count == length { break }
            }
        }

        return nonce
    }

    private func sha256(_ input: String) -> String {
        let hashedData = SHA256.hash(data: Data(input.utf8))
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension SupabaseManager: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        keyWindowAnchor() ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        self.activeAppleAuth = nil

        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }

        guard let nonce = currentNonce else {
            MerianLog.auth.error("Apple Sign-In callback received without a pending nonce; aborting login.")
            return
        }
        currentNonce = nil
        guard let appleIDToken = appleIDCredential.identityToken else {
            MerianLog.auth.debug("Apple Sign-In: unable to fetch identity token.")
            return
        }
        guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            MerianLog.auth.debug("Apple Sign-In: failed to serialize token string.")
            return
        }

        Task {
            do {
                try await self.finalizeOAuthLogin(provider: .apple, idToken: idTokenString, accessToken: nil, nonce: nonce)
                let session = try await client.auth.session
                _ = await ensureTelemetryLinkedIfNeeded(for: session.user)
                KeychainManager.shared.set(true, forKey: KeychainKeys.hasAuthenticatedOAuth)
                MerianLog.auth.debug("Apple Sign-In complete.")
            } catch {
                MerianLog.auth.debug("Apple Sign-In failed: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        self.activeAppleAuth = nil
        self.currentNonce = nil
        MerianLog.auth.debug("Apple Sign-In error: \(error.localizedDescription, privacy: .private)")
    }
}

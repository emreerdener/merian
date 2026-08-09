import AuthenticationServices
import CryptoKit
import Foundation
import GoogleSignIn
import Observation
import os
import Supabase

private struct RevenueCatPublicIdentity: Decodable {
    let email: String?
    let publicUsername: String?
    let publicAuthorName: String?
    let publicIdentitySource: String?
    let publicAvatarUrl: String?

    private enum CodingKeys: String, CodingKey {
        case email
        case publicUsername = "public_username"
        case publicAuthorName = "public_author_name"
        case publicIdentitySource = "public_identity_source"
        case publicAvatarUrl = "public_avatar_url"
    }
}

enum SupabaseAuthTransitionError: LocalizedError {
    case signOutInProgress
    case invalidOAuthIdentityToken
    case guestMergeSessionChanged
    case guestMergeHandoffPersistenceFailed

    var errorDescription: String? {
        switch self {
        case .signOutInProgress:
            return "Authentication is changing. Try again in a moment."
        case .invalidOAuthIdentityToken:
            return "The identity provider returned an invalid token."
        case .guestMergeSessionChanged:
            return "The guest session changed before the account upgrade could be secured."
        case .guestMergeHandoffPersistenceFailed:
            return "The account upgrade could not be secured on this device. Your guest session is unchanged."
        }
    }
}

enum AccountPresentationPolicy {
    static func isGhost(
        userID: UUID?,
        authIsAnonymous: Bool,
        storedGhostModeUserID: String?
    ) -> Bool {
        guard let userID else { return true }
        if authIsAnonymous { return true }
        return storedGhostModeUserID?.lowercased()
            == userID.uuidString.lowercased()
    }

    static func persistedGhostModeUserID(
        userID: UUID?,
        authIsAnonymous: Bool
    ) -> String? {
        guard let userID, !authIsAnonymous else { return nil }
        return userID.uuidString.lowercased()
    }

    static func canResumeLinkedAccount(
        userID: UUID?,
        authIsAnonymous: Bool,
        isUsingGhostMode: Bool
    ) -> Bool {
        userID != nil && !authIsAnonymous && isUsingGhostMode
    }
}

// MARK: - Supabase Manager

/// Manages the global Supabase connection, auth state, and OAuth sign-in flows.
@MainActor
@Observable final class SupabaseManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum AuthSessionAdoption: Equatable {
        case signedOut
        case awaitingRefresh(userId: UUID)
        case authenticated(userId: UUID)
    }

    private enum AppleSignInBootstrapError: LocalizedError {
        case nonceGenerationFailed(OSStatus)
        case invalidCredentialRegistrationReceipt

        var errorDescription: String? {
            switch self {
            case .nonceGenerationFailed(let status):
                return "Failed to generate an Apple Sign-In nonce (\(status))."
            case .invalidCredentialRegistrationReceipt:
                return "The Apple credential registration response was invalid."
            }
        }
    }

    private struct AppleRevocationCredentialPayload: Encodable {
        let registration_id: String
        let authorization_code: String
        let identity_token: String
    }

    private struct AppleRevocationCredentialResponse: Decodable {
        let success: Bool
        let status: String
    }

    private struct GhostProfileMergePreparePayload: Encodable {
        let operation = "prepare"
        let provider: String
        let provider_subject: String
    }

    private struct GhostProfileMergePrepareResponse: Decodable {
        let handoff_id: String
        let handoff_secret: String
        let expires_at: String
    }

    private struct GhostProfileMergeCompletePayload: Encodable {
        let operation = "complete"
        let handoff_id: String
        let handoff_secret: String
    }

    private struct GhostProfileIdentityRefreshPayload: Encodable {
        let operation = "refresh_identity"
    }

    struct PendingGhostProfileMerge: Codable, Equatable {
        let ghostUserId: String
        let provider: String
        let providerSubject: String
        let handoffId: String
        let handoffSecret: String
        let expiresAt: String
    }

    struct PendingGhostProfileMergeQueue: Codable, Equatable {
        let version: Int
        var handoffs: [PendingGhostProfileMerge]

        init(handoffs: [PendingGhostProfileMerge]) {
            self.version = 1
            self.handoffs = handoffs
        }
    }

    private struct GhostProfileMergeErrorPayload: Decodable {
        let code: String?
    }

    // MARK: - Singleton Architecture
    static let shared = SupabaseManager()

    // MARK: - Client
    let client: SupabaseClient

    // MARK: - State
    var currentUser: User?
    var isAuthenticated: Bool = false
    private(set) var isUsingGhostMode = false

    var isGuestUser: Bool {
        AccountPresentationPolicy.isGhost(
            userID: currentUser?.id,
            authIsAnonymous: currentUser?.isAnonymous ?? true,
            storedGhostModeUserID: isUsingGhostMode
                ? currentUser?.id.uuidString
                : nil
        )
    }

    var canResumeLinkedAccount: Bool {
        AccountPresentationPolicy.canResumeLinkedAccount(
            userID: currentUser?.id,
            authIsAnonymous: currentUser?.isAnonymous ?? true,
            isUsingGhostMode: isUsingGhostMode
        )
    }

    var currentUserAvatarUrl: URL? {
        guard let urlString = currentUser?.userMetadata["avatar_url"]?.stringValue ?? currentUser?.userMetadata["picture"]?.stringValue else {
            return nil
        }
        return SecureTransportPolicy.httpsURL(from: urlString)
    }

    // MARK: - Apple Sign-In State
    private var currentNonce: String?
    private var activeAppleAuth: ASAuthorizationController?

    // MARK: - Session Deduplication
    /// Tracks the last user ID considered for RevenueCat linkage and history sync.
    /// Same-user auth events retry RevenueCat only while its identity fence is not ready;
    /// they never repeat the identity-change-only historical download.
    private var lastLinkedUserId: UUID?

    /// Retained handle for the auth state listener task. Stored so the task can be cancelled
    /// on teardown and is consistent with the @ObservationIgnored task handle pattern used
    /// throughout the engine layer. Fire-and-forget tasks with no handle cannot be inspected,
    /// restarted, or cleanly shut down.
    @ObservationIgnored private var authListenerTask: Task<Void, Never>?
    /// Single-flight guard for anonymous session creation. Multiple callers can reach
    /// `initializeGhostSession()` while the first network round-trip is suspended; without this
    /// handle they each attempt a fresh anonymous sign-in and race to replace the active session.
    @ObservationIgnored private var ghostSessionTask: Task<Void, Never>?
    /// Single-flight completion for a persisted provider-bound guest merge.
    /// Auth callbacks and the interactive login path can observe the same new
    /// permanent session; both converge on this task rather than racing cleanup.
    @ObservationIgnored private var ghostProfileMergeTask: Task<Bool, Never>?
    /// Identifies the currently retained task so a cancelled task that finishes
    /// later cannot clear the handle for a newer auth session's merge.
    @ObservationIgnored private var ghostProfileMergeTaskId: UUID?
    @ObservationIgnored private var ghostProfileMergeTaskTargetUserId: String?
    /// Single-flight sign-out handle. Authenticated request creation is closed as
    /// soon as this transition begins, before the SDK invalidates the session.
    @ObservationIgnored private var signOutTask: Task<Void, Never>?
    @ObservationIgnored private var publicAuthorIdentityRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var appleCredentialRevocationObserver: NSObjectProtocol?
    @ObservationIgnored private weak var appRouteSessionController: (any AppRouteSessionControlling)?
    @ObservationIgnored private weak var milestoneToastSessionController: (any MilestoneToastSessionControlling)?
    private var lastPublicAuthorIdentityRefreshUserId: String?
    @ObservationIgnored private(set) var isSigningOut = false

    // MARK: - Initialization

    private override init() {
        if !MerianEnvironment.configurationIssues.isEmpty {
            let issues = MerianEnvironment.configurationIssues.map(\.description).joined(separator: " | ")
            MerianLog.auth.fault("Environment configuration degraded: \(issues, privacy: .public)")
        }

        self.client = MerianSupabaseClientFactory.makeClient(emitLocalSessionAsInitialSession: true)

        super.init()

        self.setupAuthStateListener()
        self.appleCredentialRevocationObserver = NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.revalidateAppleCredentialAfterRevocationNotification()
            }
        }
    }

    deinit {
        authListenerTask?.cancel()
        ghostSessionTask?.cancel()
        ghostProfileMergeTask?.cancel()
        signOutTask?.cancel()
        publicAuthorIdentityRefreshTask?.cancel()
        if let appleCredentialRevocationObserver {
            NotificationCenter.default.removeObserver(appleCredentialRevocationObserver)
        }
    }

    func bindAppRouteSessionController(_ controller: any AppRouteSessionControlling) {
        appRouteSessionController = controller
        controller.beginAccountSession(
            accountID: currentUser?.id.uuidString,
            origin: .initialRestoration,
            now: Date()
        )
    }

    func bindMilestoneToastSessionController(
        _ controller: any MilestoneToastSessionControlling
    ) {
        milestoneToastSessionController = controller
        controller.beginAccountSession(
            accountID: currentUser?.id.uuidString,
            origin: .initialRestoration,
            now: Date()
        )
    }

    // MARK: - Auth State

    private func revalidateAppleCredentialAfterRevocationNotification() {
        guard let appleUserId = currentUser?.identities?.first(where: {
            $0.provider == "apple" && !$0.id.isEmpty
        })?.id else { return }

        ASAuthorizationAppleIDProvider().getCredentialState(
            forUserID: appleUserId
        ) { [weak self] state, error in
            Task { @MainActor [weak self] in
                guard let self,
                      self.currentUser?.identities?.contains(where: {
                          $0.provider == "apple" && $0.id == appleUserId
                      }) == true else { return }

                guard Self.shouldClearLocalSessionAfterAppleCredentialState(
                    state,
                    lookupFailed: error != nil
                ) else {
                    MerianLog.auth.debug(
                        "Apple credential remained authorized after a revocation notification; preserving the active session."
                    )
                    return
                }

                if error != nil {
                    MerianLog.auth.notice(
                        "Apple credential state lookup failed after a revocation notification; clearing the local session."
                    )
                } else {
                    MerianLog.auth.notice(
                        "Apple confirmed that the active credential is no longer authorized; clearing the local session."
                    )
                }
                await self.clearLocalSessionAfterAuthFailure()
            }
        }
    }

    static func shouldClearLocalSessionAfterAppleCredentialState(
        _ state: ASAuthorizationAppleIDProvider.CredentialState,
        lookupFailed: Bool = false
    ) -> Bool {
        if lookupFailed { return true }

        switch state {
        case .authorized:
            return false
        case .revoked, .notFound, .transferred:
            return true
        @unknown default:
            return true
        }
    }

    static func authSessionAdoption(
        userId: UUID?,
        isExpired: Bool
    ) -> AuthSessionAdoption {
        guard let userId else { return .signedOut }
        if isExpired {
            return .awaitingRefresh(userId: userId)
        }
        return .authenticated(userId: userId)
    }

    private func setupAuthStateListener() {
        let authStateChanges = client.auth.authStateChanges
        authListenerTask = Task { [weak self] in
            for await state in authStateChanges {
                // Bind the manager only for one delivered event. The task spends
                // its next suspension waiting on the stream with no strong owner
                // reference, so the manager can deinitialize and cancel it.
                guard let self else { return }
                do {
                    let pendingHandoffs = try loadPendingGhostProfileMergeQueue()
                    ConsentManager.shared.setAnalyticsSuppressedForGhostHandoff(
                        !pendingHandoffs.isEmpty
                    )
                } catch {
                    // A read or decode failure is uncertainty, not evidence that
                    // the durable handoff is absent. Keep analytics fail-closed.
                    ConsentManager.shared
                        .setAnalyticsSuppressedForGhostHandoff(true)
                    MerianLog.auth.error(
                        "Could not read the guest handoff queue; analytics remains suppressed: \(error.localizedDescription, privacy: .private)"
                    )
                }
                let sessionAdoption = Self.authSessionAdoption(
                    userId: state.session?.user.id,
                    isExpired: state.session?.isExpired ?? false
                )
                let accountSessionOrigin: AppRouteAccountSessionOrigin = state.event == .initialSession
                    ? .initialRestoration
                    : .runtimeTransition
                switch sessionAdoption {
                case .authenticated:
                    guard !isSigningOut else {
                        MerianLog.auth.debug("Ignored authenticated SDK event while sign-out is in progress.")
                        continue
                    }
                    guard let session = state.session else { continue }
                    self.currentUser = session.user
                    self.isAuthenticated = true
                    self.isUsingGhostMode = AccountPresentationPolicy.isGhost(
                        userID: session.user.id,
                        authIsAnonymous: false,
                        storedGhostModeUserID: KeychainManager.shared.string(
                            forKey: KeychainKeys.ghostModeUserID
                        )
                    )
                    appRouteSessionController?.beginAccountSession(
                        accountID: session.user.id.uuidString,
                        origin: accountSessionOrigin,
                        now: Date()
                    )
                    milestoneToastSessionController?.beginAccountSession(
                        accountID: session.user.id.uuidString,
                        origin: accountSessionOrigin,
                        now: Date()
                    )
                    ConsentManager.shared.observeSession(userId: session.user.id)
                    await EntitlementManager.shared.beginSession(
                        userID: session.user.id,
                        client: client
                    )
                    schedulePublicAuthorIdentityRefreshIfNeeded(for: session.user)

                    if !TestExecutionCoordinator.isRunningTests,
                       await self.ensureTelemetryLinkedIfNeeded(for: session.user) {
                        // Trigger historical sync only when the active user identity changes.
                        // The Supabase SDK fires two auth events on cold start (local cache +
                        // server validation), both with the same user. A same-user event may
                        // retry a failed RevenueCat link but cannot start a second history sync.
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
                case .awaitingRefresh(let userId):
                    guard !isSigningOut else {
                        MerianLog.auth.debug("Ignored refreshing SDK session while sign-out is in progress.")
                        continue
                    }

                    // With emitLocalSessionAsInitialSession enabled, Supabase emits an
                    // expired cached session before refreshing it. The account identity
                    // is known even though authenticated requests must remain closed.
                    // Preserve that identity for consent restoration so the app root
                    // cannot briefly present approval UI before tokenRefreshed arrives.
                    self.currentUser = nil
                    self.isAuthenticated = false
                    appRouteSessionController?.beginAccountSession(
                        accountID: userId.uuidString,
                        origin: accountSessionOrigin,
                        now: Date()
                    )
                    milestoneToastSessionController?.beginAccountSession(
                        accountID: userId.uuidString,
                        origin: accountSessionOrigin,
                        now: Date()
                    )
                    ConsentManager.shared.observeSession(userId: userId)
                    MerianLog.auth.debug(
                        "Cached auth session is awaiting refresh; consent restoration remains pending."
                    )
                case .signedOut:
                    self.currentUser = nil
                    self.isAuthenticated = false
                    self.isUsingGhostMode = false
                    appRouteSessionController?.beginAccountSession(
                        accountID: nil,
                        origin: accountSessionOrigin,
                        now: Date()
                    )
                    milestoneToastSessionController?.beginAccountSession(
                        accountID: nil,
                        origin: accountSessionOrigin,
                        now: Date()
                    )
                    ConsentManager.shared.observeSession(userId: nil)
                    EntitlementManager.shared.handleSignOut()
                    lastLinkedUserId = nil
                    lastPublicAuthorIdentityRefreshUserId = nil
                    publicAuthorIdentityRefreshTask?.cancel()
                    publicAuthorIdentityRefreshTask = nil
                    cancelGhostProfileMergeTask()
                }

                MerianLog.auth.debug("Auth event: \(String(describing: state.event), privacy: .public) | authenticated: \(self.isAuthenticated, privacy: .private)")
            }
        }
    }

    private func linkExternalTelemetry(user: User) async {
        let publicIdentity = await fetchRevenueCatPublicIdentity(for: user.id)
        let email = firstNonEmpty(user.email, publicIdentity?.email)
        let fullName = firstNonEmpty(
            user.userMetadata["full_name"]?.stringValue,
            user.userMetadata["name"]?.stringValue,
            publicIdentity?.publicAuthorName
        )
        let avatarUrl = firstNonEmpty(
            user.userMetadata["avatar_url"]?.stringValue,
            user.userMetadata["picture"]?.stringValue,
            publicIdentity?.publicAvatarUrl
        )

        await RevenueCatManager.shared.linkWithSupabase(
            userId: user.id,
            email: email,
            displayName: fullName,
            avatarUrl: avatarUrl,
            publicUsername: publicIdentity?.publicUsername,
            publicAuthorName: publicIdentity?.publicAuthorName,
            publicIdentitySource: publicIdentity?.publicIdentitySource,
            accountKind: RevenueCatAccountMutationPolicy.accountKind(
                isAnonymous: user.isAnonymous
            )
        )
    }

    private func fetchRevenueCatPublicIdentity(for userId: UUID) async -> RevenueCatPublicIdentity? {
        do {
            let response: [RevenueCatPublicIdentity] = try await client.from("users")
                .select("email,public_username,public_author_name,public_identity_source,public_avatar_url")
                .eq("id", value: userId)
                .limit(1)
                .execute()
                .value
            return response.first
        } catch {
            MerianLog.auth.debug("RevenueCat public identity lookup failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        values.lazy.compactMap {
            guard let trimmed = $0?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else {
                return nil
            }
            return trimmed
        }.first
    }

    @discardableResult
    private func ensureTelemetryLinkedIfNeeded(for user: User) async -> Bool {
        let userId = user.id
        let identityChanged = userId != lastLinkedUserId
        let expectedAccountKind = RevenueCatAccountMutationPolicy.accountKind(
            isAnonymous: user.isAnonymous
        )
        let accountKindChanged = RevenueCatManager.shared.linkedAccountKind
            != expectedAccountKind
        guard identityChanged || accountKindChanged ||
                !RevenueCatManager.shared.isIdentityReady else {
            return false
        }
        lastLinkedUserId = userId
        await linkExternalTelemetry(user: user)
        return identityChanged
    }

    // MARK: - Ghost Session

    /// Creates an anonymous session for new users. Skips creation if a session exists or
    /// if the error is network/expiry — preserving any existing Apple Sign-In identity.
    func initializeGhostSession() async {
        guard !TestExecutionCoordinator.isRunningTests else { return }

        if let signOutTask {
            await signOutTask.value
        }

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
        guard !Task.isCancelled else { return }

        do {
            let session = try await client.auth.session
            guard !Task.isCancelled else { return }
            MerianLog.auth.debug("Existing session resolved on device.")
            schedulePublicAuthorIdentityRefreshIfNeeded(for: session.user)
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
                guard !Task.isCancelled else { return }
                do {
                    let authResponse = try await client.auth.signInAnonymously()
                    guard !Task.isCancelled else { return }
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

    /// Returns the linked account to Naturebook's Ghost presentation without
    /// invalidating its private Supabase session or changing its canonical UUID.
    /// This is the user-facing logout contract. A true Auth sign-out cannot later
    /// recover the same Supabase anonymous user, so it is reserved for account
    /// deletion and authoritative credential failure.
    @discardableResult
    func continueAsGhost() -> Bool {
        guard let user = currentUser else { return false }
        guard let storedUserID = AccountPresentationPolicy.persistedGhostModeUserID(
            userID: user.id,
            authIsAnonymous: user.isAnonymous
        ) else {
            isUsingGhostMode = user.isAnonymous
            return user.isAnonymous
        }

        guard KeychainManager.shared.set(
            storedUserID,
            forKey: KeychainKeys.ghostModeUserID
        ) else {
            MerianLog.auth.error(
                "Could not persist Ghost mode; preserving the linked-account presentation."
            )
            return false
        }

        isUsingGhostMode = true
        MerianLog.auth.debug(
            "Continued as Ghost without changing the Supabase or RevenueCat identity."
        )
        return true
    }

    /// Leaves same-UUID Ghost presentation without running OAuth or replacing
    /// the private linked session that continued to own the account.
    @discardableResult
    func resumeLinkedAccount() -> Bool {
        guard let user = currentUser,
              canResumeLinkedAccount else {
            return false
        }
        leaveGhostMode(for: user.id)
        return !isUsingGhostMode
    }

    private func leaveGhostMode(for userID: UUID) {
        let storedUserID = KeychainManager.shared.string(
            forKey: KeychainKeys.ghostModeUserID
        )
        guard storedUserID?.lowercased() == userID.uuidString.lowercased()
                || isUsingGhostMode else {
            return
        }
        KeychainManager.shared.removeObject(forKey: KeychainKeys.ghostModeUserID)
        isUsingGhostMode = false
    }

    func signOut() async {
        await signOut(
            performRemoteSignOut: { [client] in
                try await client.auth.signOut(scope: .local)
            },
            performExternalSignOut: {
                await RevenueCatManager.shared.handleSupabaseSignOut()
            }
        )
    }

    /// Internal dependency seam used by tests to prove local auth closes before
    /// the remote session invalidation begins.
    func signOut(
        performRemoteSignOut: @MainActor @escaping () async throws -> Void,
        performExternalSignOut: @MainActor @escaping () async -> Void
    ) async {
        if let signOutTask {
            await signOutTask.value
            return
        }

        let cancelledGhostSessionTask = beginLocalSignOutTransition()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isSigningOut = false
                self.signOutTask = nil
            }

            if let cancelledGhostSessionTask {
                await cancelledGhostSessionTask.value
            }

            do {
                try await performRemoteSignOut()
            } catch {
                MerianLog.auth.debug("Supabase sign-out failed; continuing local cleanup: \(error.localizedDescription, privacy: .private)")
            }

            await performExternalSignOut()
            MerianLog.auth.debug("User signed out.")
        }
        signOutTask = task
        await task.value
    }

    /// Replaces the active account with a fresh anonymous identity only after
    /// local cleanup and remote sign-out have completed.
    func transitionToGhostSession() async {
        await signOut()
        await initializeGhostSession()
    }

    @discardableResult
    private func beginLocalSignOutTransition() -> Task<Void, Never>? {
        isSigningOut = true
        currentUser = nil
        isAuthenticated = false
        lastLinkedUserId = nil
        lastPublicAuthorIdentityRefreshUserId = nil

        let cancelledGhostSessionTask = ghostSessionTask
        cancelledGhostSessionTask?.cancel()
        ghostSessionTask = nil

        publicAuthorIdentityRefreshTask?.cancel()
        publicAuthorIdentityRefreshTask = nil
        cancelGhostProfileMergeTask()
        KeychainManager.shared.removeObject(forKey: KeychainKeys.hasAuthenticatedOAuth)
        KeychainManager.shared.removeObject(forKey: KeychainKeys.ghostModeUserID)
        isUsingGhostMode = false
        PostHogManager.shared.reset()
        return cancelledGhostSessionTask
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
        guard !isSigningOut else { return false }

        do {
            let session = try await client.auth.refreshSession()
            guard !isSigningOut else { return false }
            currentUser = session.user
            isAuthenticated = true
            schedulePublicAuthorIdentityRefreshIfNeeded(for: session.user)
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
        await transitionToGhostSession()

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
        lastPublicAuthorIdentityRefreshUserId = nil
        publicAuthorIdentityRefreshTask?.cancel()
        publicAuthorIdentityRefreshTask = nil
        cancelGhostProfileMergeTask()
        KeychainManager.shared.removeObject(forKey: KeychainKeys.hasAuthenticatedOAuth)
        KeychainManager.shared.removeObject(forKey: KeychainKeys.ghostModeUserID)
        isUsingGhostMode = false
        PostHogManager.shared.reset()
        await RevenueCatManager.shared.handleSupabaseSignOut()
        MerianLog.auth.debug("Cleared local Supabase session after auth failure.")
    }

    /// Builds authenticated REST headers, initializing a ghost session if no token exists.
    func getValidAuthHeaders() async throws -> [String: String] {
        guard !isSigningOut else {
            throw SupabaseAuthTransitionError.signOutInProgress
        }

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

        guard !isSigningOut else {
            throw SupabaseAuthTransitionError.signOutInProgress
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

            let previousUserId = try await self.finalizeOAuthLogin(
                provider: .google,
                idToken: idToken,
                accessToken: accessToken,
                nonce: nil
            )
            let didPersistGoogleMetadata = await updateGoogleUserMetadataIfAvailable(from: result.user)
            let session = try await client.auth.session
            currentUser = session.user
            isAuthenticated = true
            leaveGhostMode(for: session.user.id)
            _ = await ensureTelemetryLinkedIfNeeded(for: session.user)
            if didPersistGoogleMetadata {
                _ = await refreshPublicAuthorIdentity()
            }
            publishPublicAuthorIdentityChanged(
                previousUserId: previousUserId,
                currentUserId: session.user.id.uuidString
            )

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

    private func finalizeOAuthLogin(
        provider: OpenIDConnectCredentials.Provider,
        idToken: String,
        accessToken: String?,
        nonce: String?
    ) async throws -> String? {
        guard !isSigningOut else {
            throw SupabaseAuthTransitionError.signOutInProgress
        }

        let previousSession = try? await client.auth.session
        let previousUserId = previousSession?.user.id.uuidString

        if previousSession?.user.isAnonymous == true {
            let credentials = OpenIDConnectCredentials(
                provider: provider,
                idToken: idToken,
                accessToken: accessToken,
                nonce: nonce
            )

            do {
                _ = try await client.auth.linkIdentityWithIdToken(
                    credentials: credentials
                )
                if let previousUserId {
                    try clearPendingGhostProfileMerges(
                        ghostUserId: previousUserId
                    )
                }
            } catch {
                guard Self.requiresProviderBoundGhostMerge(after: error) else {
                    throw error
                }
                guard !isSigningOut else {
                    throw SupabaseAuthTransitionError.signOutInProgress
                }
                guard let ghostId = previousUserId?.lowercased() else {
                    throw SupabaseAuthTransitionError.guestMergeSessionChanged
                }

                let currentGuestSession = try await client.auth.session
                guard currentGuestSession.user.isAnonymous,
                      currentGuestSession.user.id.uuidString.lowercased() == ghostId else {
                    throw SupabaseAuthTransitionError.guestMergeSessionChanged
                }

                let providerSubject = try Self.oauthProviderSubject(from: idToken)
                _ = try await prepareGhostProfileMerge(
                    ghostUserId: ghostId,
                    provider: provider,
                    providerSubject: providerSubject
                )

                let targetSession = try await installOAuthSessionReplacingCurrentAccount(
                    credentials: credentials
                )
                if targetSession.user.id.uuidString.lowercased() == ghostId {
                    try clearPendingGhostProfileMerges(ghostUserId: ghostId)
                } else {
                    _ = await completePendingGhostProfileMergeIfNeeded(
                        expectedTargetUserId: targetSession.user.id.uuidString
                    )
                }
            }
        } else {
            _ = try await installOAuthSessionReplacingCurrentAccount(
                credentials: .init(
                    provider: provider,
                    idToken: idToken,
                    accessToken: accessToken,
                    nonce: nonce
                )
            )
        }

        return previousUserId
    }

    private func registerAppleRevocationCredential(
        registrationId: UUID,
        authorizationCode: String,
        identityToken: String
    ) async throws {
        try await Self.performAppleCredentialRegistrationWithRetry {
            let response: AppleRevocationCredentialResponse = try await self.client.functions.invoke(
                "register-apple-revocation-token",
                options: .init(
                    body: AppleRevocationCredentialPayload(
                        registration_id: registrationId.uuidString.lowercased(),
                        authorization_code: authorizationCode,
                        identity_token: identityToken
                    )
                )
            )
            guard response.success, response.status == "registered" else {
                throw AppleSignInBootstrapError.invalidCredentialRegistrationReceipt
            }
        }
    }

    static func performAppleCredentialRegistrationWithRetry(
        maximumAttempts: Int = 2,
        invoke: () async throws -> Void,
        waitBeforeRetry: () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(350))
        }
    ) async throws {
        precondition(maximumAttempts > 0)
        var lastError: Error?

        for attempt in 1...maximumAttempts {
            do {
                try await invoke()
                return
            } catch {
                lastError = error
                guard attempt < maximumAttempts else { break }
                try Task.checkCancellation()
                try await waitBeforeRetry()
            }
        }

        throw lastError ?? AppleSignInBootstrapError.invalidCredentialRegistrationReceipt
    }

    private func installOAuthSessionReplacingCurrentAccount(
        credentials: OpenIDConnectCredentials
    ) async throws -> Session {
        try await Self.performOAuthSessionReplacement(
            suspendAnalytics: {
                ConsentManager.shared.beginAnalyticsAccountTransition()
            },
            installSession: {
                try await self.client.auth.signInWithIdToken(
                    credentials: credentials
                )
            },
            currentSession: {
                self.client.auth.currentSession
            },
            reconcileSession: { generation, session in
                self.reconcileOAuthSessionReplacement(
                    generation: generation,
                    session: session
                )
            }
        )
    }

    private func reconcileOAuthSessionReplacement(
        generation: UInt,
        session: Session?
    ) {
        let resolvedSession = client.auth.currentSession ?? session
        let activeSession = !isSigningOut && resolvedSession?.isExpired == false
            ? resolvedSession
            : nil
        guard ConsentManager.shared.resolveAnalyticsAccountTransition(
            generation: generation,
            userId: activeSession?.user.id
        ) else {
            return
        }
        currentUser = activeSession?.user
        isAuthenticated = activeSession != nil
    }

    @discardableResult
    private func prepareGhostProfileMerge(
        ghostUserId: String,
        provider: OpenIDConnectCredentials.Provider,
        providerSubject: String
    ) async throws -> PendingGhostProfileMerge {
        let response: GhostProfileMergePrepareResponse = try await client.functions.invoke(
            "merge-ghost-profile",
            options: .init(
                body: GhostProfileMergePreparePayload(
                    provider: provider.rawValue,
                    provider_subject: providerSubject
                )
            )
        )

        let pending = PendingGhostProfileMerge(
            ghostUserId: ghostUserId,
            provider: provider.rawValue,
            providerSubject: providerSubject,
            handoffId: response.handoff_id,
            handoffSecret: response.handoff_secret,
            expiresAt: response.expires_at
        )
        let existingHandoffs = try loadPendingGhostProfileMergeQueue()
        let queue = Self.enqueuingPendingGhostProfileMerge(
            pending,
            in: existingHandoffs
        )
        try persistPendingGhostProfileMergeQueue(queue)
        ConsentManager.shared.setAnalyticsSuppressedForGhostHandoff(true)
        MerianLog.auth.debug("Secured provider-bound guest profile handoff.")
        return pending
    }

    @discardableResult
    private func completePendingGhostProfileMergeIfNeeded(
        expectedTargetUserId: String? = nil
    ) async -> Bool {
        if let existingTask = ghostProfileMergeTask {
            if ghostProfileMergeTaskTargetUserId
                == expectedTargetUserId?.lowercased() {
                return await existingTask.value
            }

            // A new authenticated identity superseded this in-flight attempt.
            // The old request remains server-idempotent, but its task must not
            // suppress completion for the new active session.
            cancelGhostProfileMergeTask()
        }

        let taskId = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            return await self.performPendingGhostProfileMerge(
                expectedTargetUserId: expectedTargetUserId
            )
        }
        ghostProfileMergeTaskId = taskId
        ghostProfileMergeTaskTargetUserId = expectedTargetUserId?.lowercased()
        ghostProfileMergeTask = task
        let result = await task.value
        if ghostProfileMergeTaskId == taskId {
            ghostProfileMergeTask = nil
            ghostProfileMergeTaskId = nil
            ghostProfileMergeTaskTargetUserId = nil
        }
        return result
    }

    private func performPendingGhostProfileMerge(
        expectedTargetUserId: String?
    ) async -> Bool {
        guard !Task.isCancelled, !isSigningOut else { return false }
        let pendingHandoffs: [PendingGhostProfileMerge]
        do {
            pendingHandoffs = try loadPendingGhostProfileMergeQueue()
        } catch {
            ConsentManager.shared.setAnalyticsSuppressedForGhostHandoff(true)
            MerianLog.auth.error(
                "Guest profile upgrade remains pending because its durable queue is unreadable: \(error.localizedDescription, privacy: .private)"
            )
            return false
        }
        guard !pendingHandoffs.isEmpty else {
            ConsentManager.shared.setAnalyticsSuppressedForGhostHandoff(false)
            return true
        }
        ConsentManager.shared.setAnalyticsSuppressedForGhostHandoff(true)

        do {
            let session = try await client.auth.session
            guard !session.user.isAnonymous else { return false }

            let targetUserId = session.user.id.uuidString.lowercased()
            if let expectedTargetUserId,
               targetUserId != expectedTargetUserId.lowercased() {
                MerianLog.auth.error("Refused guest merge retry for an unexpected active account.")
                return false
            }

            guard let targetUUID = UUID(uuidString: targetUserId) else {
                MerianLog.auth.error("Refused guest merge for an invalid active account UUID.")
                return false
            }

            var allHandoffsResolved = true
            for pending in pendingHandoffs {
                guard !Task.isCancelled, !isSigningOut else { return false }

                do {
                    guard let ghostUUID = UUID(uuidString: pending.ghostUserId) else {
                        throw SupabaseAuthTransitionError.guestMergeSessionChanged
                    }
                    try await Self.finalizeGhostProfileHandoff(
                        completeServerHandoff: {
                            try await self.client.functions.invoke(
                                "merge-ghost-profile",
                                options: .init(
                                    body: GhostProfileMergeCompletePayload(
                                        handoff_id: pending.handoffId,
                                        handoff_secret: pending.handoffSecret
                                    )
                                )
                            )
                        },
                        synchronizeProviderPurchases: {
                            try await RevenueCatManager.shared
                                .synchronizePurchasesAfterAccountMerge()
                        },
                        rebindAndSynchronizeLocalEvidence: {
                            try await ConsentManager.shared
                                .rebindAndSynchronizeGhostEvidence(
                                    from: ghostUUID,
                                    to: targetUUID
                                )
                        },
                        clearPendingHandoff: {
                            guard !self.isSigningOut,
                                  self.currentUser?.id == targetUUID,
                                  ConsentManager.shared.currentSessionUserId
                                    == targetUUID else {
                                throw SupabaseAuthTransitionError
                                    .guestMergeSessionChanged
                            }
                            try self.clearPendingGhostProfileMerge(
                                handoffId: pending.handoffId
                            )
                        }
                    )
                    guard !Task.isCancelled, !isSigningOut else { return false }
                    MerianLog.auth.debug(
                        "Guest profile upgrade finalized for \(pending.ghostUserId, privacy: .private)"
                    )
                } catch {
                    if Self.shouldDiscardPendingGhostProfileMerge(after: error) {
                        do {
                            // Terminal handoffs are never rebound locally, but
                            // the permanent account must still be authoritative
                            // before removing the durable suppression marker.
                            try await ConsentManager.shared
                                .synchronizeWithCurrentSession()
                            try Task.checkCancellation()
                            guard !isSigningOut,
                                  currentUser?.id == targetUUID,
                                  ConsentManager.shared.currentSessionUserId
                                    == targetUUID else {
                                throw SupabaseAuthTransitionError
                                    .guestMergeSessionChanged
                            }
                            try clearPendingGhostProfileMerge(
                                handoffId: pending.handoffId
                            )
                            MerianLog.auth.error(
                                "Discarded a terminal guest profile handoff: \(error.localizedDescription, privacy: .private)"
                            )
                        } catch {
                            allHandoffsResolved = false
                            MerianLog.auth.error(
                                "Terminal guest handoff cleanup remains pending: \(error.localizedDescription, privacy: .private)"
                            )
                        }
                    } else {
                        allHandoffsResolved = false
                        MerianLog.auth.error(
                            "Guest profile upgrade remains pending and will retry: \(error.localizedDescription, privacy: .private)"
                        )
                    }
                }
            }
            let queueIsEmpty = try loadPendingGhostProfileMergeQueue().isEmpty
            if allHandoffsResolved && queueIsEmpty {
                ConsentManager.shared.setAnalyticsSuppressedForGhostHandoff(false)
            }
            return allHandoffsResolved && queueIsEmpty
        } catch {
            MerianLog.auth.error(
                "Guest profile upgrade retry could not read the active session: \(error.localizedDescription, privacy: .private)"
            )
            return false
        }
    }

    @discardableResult
    private func refreshPublicAuthorIdentity() async -> Bool {
        do {
            try await client.functions.invoke(
                "merge-ghost-profile",
                options: .init(body: GhostProfileIdentityRefreshPayload())
            )
            return true
        } catch {
            MerianLog.auth.debug(
                "Public author identity refresh failed: \(error.localizedDescription, privacy: .private)"
            )
            return false
        }
    }

    private func loadPendingGhostProfileMergeQueue() throws -> [PendingGhostProfileMerge] {
        guard let data = try KeychainManager.shared.dataOrThrow(
            forKey: KeychainKeys.pendingGhostProfileMerge
        ) else {
            return []
        }

        if let queue = try? JSONDecoder().decode(
            PendingGhostProfileMergeQueue.self,
            from: data
        ), queue.version == 1 {
            return queue.handoffs
        }

        // Backward compatibility for builds that stored one handoff record.
        if let legacy = try? JSONDecoder().decode(
            PendingGhostProfileMerge.self,
            from: data
        ) {
            do {
                try persistPendingGhostProfileMergeQueue([legacy])
            } catch {
                // The original record is still readable. Preserve it and retry
                // the format migration after the next successful Keychain write.
                MerianLog.auth.error(
                    "Could not migrate the guest profile handoff queue: \(error.localizedDescription, privacy: .private)"
                )
            }
            return [legacy]
        }

        MerianLog.auth.error(
            "Retained an unreadable guest profile handoff queue; analytics remains suppressed."
        )
        throw SupabaseAuthTransitionError.guestMergeHandoffPersistenceFailed
    }

    private func persistPendingGhostProfileMergeQueue(
        _ handoffs: [PendingGhostProfileMerge]
    ) throws {
        if handoffs.isEmpty {
            try KeychainManager.shared.removeObjectVerified(
                forKey: KeychainKeys.pendingGhostProfileMerge
            )
            return
        }

        let encoded = try JSONEncoder().encode(
            PendingGhostProfileMergeQueue(handoffs: handoffs)
        )
        guard KeychainManager.shared.set(
            encoded,
            forKey: KeychainKeys.pendingGhostProfileMerge,
            accessibility: .whenUnlockedThisDeviceOnly
        ),
        try KeychainManager.shared.dataOrThrow(
            forKey: KeychainKeys.pendingGhostProfileMerge
        ) == encoded else {
            throw SupabaseAuthTransitionError.guestMergeHandoffPersistenceFailed
        }
    }

    private func clearPendingGhostProfileMerge(handoffId: String) throws {
        let remaining = try loadPendingGhostProfileMergeQueue().filter {
            $0.handoffId.caseInsensitiveCompare(handoffId) != .orderedSame
        }
        try persistPendingGhostProfileMergeQueue(remaining)
    }

    private func clearPendingGhostProfileMerges(
        ghostUserId: String
    ) throws {
        let remaining = try loadPendingGhostProfileMergeQueue().filter {
            $0.ghostUserId.caseInsensitiveCompare(ghostUserId) != .orderedSame
        }
        try persistPendingGhostProfileMergeQueue(remaining)
        ConsentManager.shared.setAnalyticsSuppressedForGhostHandoff(
            !remaining.isEmpty
        )
    }

    private func cancelGhostProfileMergeTask() {
        ghostProfileMergeTask?.cancel()
        ghostProfileMergeTask = nil
        ghostProfileMergeTaskId = nil
        ghostProfileMergeTaskTargetUserId = nil
    }

    nonisolated static func requiresProviderBoundGhostMerge(after error: Error) -> Bool {
        guard let authError = error as? AuthError else { return false }
        return authError.errorCode == .identityAlreadyExists
    }

    nonisolated static func enqueuingPendingGhostProfileMerge(
        _ pending: PendingGhostProfileMerge,
        in handoffs: [PendingGhostProfileMerge]
    ) -> [PendingGhostProfileMerge] {
        var updated = handoffs.filter {
            $0.ghostUserId.caseInsensitiveCompare(pending.ghostUserId)
                != .orderedSame
        }
        updated.append(pending)
        return updated
    }

    static func finalizeGhostProfileHandoff(
        completeServerHandoff: () async throws -> Void,
        synchronizeProviderPurchases: () async throws -> Void,
        rebindAndSynchronizeLocalEvidence: () async throws -> Void,
        clearPendingHandoff: () throws -> Void
    ) async throws {
        try await completeServerHandoff()
        try Task.checkCancellation()
        try await synchronizeProviderPurchases()
        try Task.checkCancellation()
        try await rebindAndSynchronizeLocalEvidence()
        try Task.checkCancellation()
        try clearPendingHandoff()
    }

    static func performOAuthSessionReplacement<Value>(
        suspendAnalytics: () -> UInt,
        installSession: () async throws -> Value,
        currentSession: () -> Value?,
        reconcileSession: (UInt, Value?) -> Void
    ) async throws -> Value {
        let generation = suspendAnalytics()
        do {
            let installedSession = try await installSession()
            reconcileSession(generation, installedSession)
            return installedSession
        } catch {
            reconcileSession(generation, currentSession())
            throw error
        }
    }

    nonisolated static func shouldDiscardPendingGhostProfileMerge(
        after error: Error
    ) -> Bool {
        guard case let FunctionsError.httpError(_, data) = error,
              let payload = try? JSONDecoder().decode(
                  GhostProfileMergeErrorPayload.self,
                  from: data
              ) else {
            return false
        }

        return payload.code == "handoff_expired"
            || payload.code == "handoff_invalid"
    }

    nonisolated static func oauthProviderSubject(from idToken: String) throws -> String {
        let segments = idToken.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else {
            throw SupabaseAuthTransitionError.invalidOAuthIdentityToken
        }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - payload.count % 4) % 4
        payload.append(String(repeating: "=", count: padding))

        guard let data = Data(base64Encoded: payload),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = object["sub"] as? String else {
            throw SupabaseAuthTransitionError.invalidOAuthIdentityToken
        }

        let normalizedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSubject.isEmpty,
              normalizedSubject.count <= 255,
              normalizedSubject.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw SupabaseAuthTransitionError.invalidOAuthIdentityToken
        }
        return normalizedSubject
    }

    @discardableResult
    private func updateGoogleUserMetadataIfAvailable(from googleUser: GIDGoogleUser) async -> Bool {
        var metadata: [String: AnyJSON] = [:]

        if let displayName = googleUser.profile?.name.trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty {
            metadata["full_name"] = .string(displayName)
            metadata["name"] = .string(displayName)
        }

        if let givenName = googleUser.profile?.givenName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !givenName.isEmpty {
            metadata["given_name"] = .string(givenName)
        }

        if let familyName = googleUser.profile?.familyName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !familyName.isEmpty {
            metadata["family_name"] = .string(familyName)
        }

        if let imageUrl = googleUser.profile?.imageURL(withDimension: 256)?.absoluteString,
           !imageUrl.isEmpty {
            metadata["avatar_url"] = .string(imageUrl)
            metadata["picture"] = .string(imageUrl)
        }

        guard !metadata.isEmpty else { return false }

        do {
            let updatedUser = try await client.auth.update(user: UserAttributes(data: metadata))
            currentUser = updatedUser
            MerianLog.auth.debug("Google profile metadata persisted for public author identity.")
            return true
        } catch {
            MerianLog.auth.debug("Google profile metadata update failed: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    @discardableResult
    private func updateAppleUserMetadataIfAvailable(
        from components: PersonNameComponents?
    ) async -> Bool {
        guard let components else { return false }

        var metadata: [String: AnyJSON] = [:]
        if let displayName = formattedAppleDisplayName(from: components) {
            metadata["full_name"] = .string(displayName)
            metadata["name"] = .string(displayName)
        }
        if let givenName = components.givenName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !givenName.isEmpty {
            metadata["given_name"] = .string(givenName)
        }
        if let familyName = components.familyName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !familyName.isEmpty {
            metadata["family_name"] = .string(familyName)
        }

        guard !metadata.isEmpty else { return false }

        do {
            let updatedUser = try await client.auth.update(user: UserAttributes(data: metadata))
            currentUser = updatedUser
            MerianLog.auth.debug("Apple profile metadata persisted for public author identity.")
            return true
        } catch {
            MerianLog.auth.debug("Apple profile metadata update failed: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    private func formattedAppleDisplayName(from components: PersonNameComponents) -> String? {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .medium

        let formatted = formatter.string(from: components)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !formatted.isEmpty { return formatted }

        let fallbackParts = [
            components.givenName,
            components.familyName
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !fallbackParts.isEmpty else { return nil }
        return fallbackParts.joined(separator: " ")
    }

    private func schedulePublicAuthorIdentityRefreshIfNeeded(for user: User) {
        guard !TestExecutionCoordinator.isRunningTests, !user.isAnonymous else { return }

        let userId = user.id.uuidString.lowercased()
        guard userId != lastPublicAuthorIdentityRefreshUserId else { return }

        lastPublicAuthorIdentityRefreshUserId = userId
        publicAuthorIdentityRefreshTask?.cancel()
        publicAuthorIdentityRefreshTask = Task { [weak self] in
            await self?.refreshPublicAuthorIdentityForRestoredSession(userId: userId)
        }
    }

    private func refreshPublicAuthorIdentityForRestoredSession(userId: String) async {
        defer {
            if currentUser?.id.uuidString.lowercased() == userId || currentUser == nil {
                publicAuthorIdentityRefreshTask = nil
            }
        }

        guard !Task.isCancelled else { return }
        _ = await completePendingGhostProfileMergeIfNeeded(
            expectedTargetUserId: userId
        )
        guard !Task.isCancelled else { return }
        guard await refreshPublicAuthorIdentity() else { return }
        guard !Task.isCancelled else { return }
        guard currentUser?.id.uuidString.lowercased() == userId else { return }

        publishPublicAuthorIdentityChanged(previousUserId: nil, currentUserId: userId)
    }

    private func publishPublicAuthorIdentityChanged(previousUserId: String?, currentUserId: String) {
        AppDIContainer.shared.appEventPublisher.send(
            .publicAuthorIdentityChanged(
                previousUserId: previousUserId?.lowercased(),
                currentUserId: currentUserId.lowercased()
            )
        )
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
        guard let appleAuthorizationCode = appleIDCredential.authorizationCode else {
            MerianLog.auth.error("Apple Sign-In: unable to fetch the authorization code required for durable token revocation.")
            return
        }
        guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            MerianLog.auth.debug("Apple Sign-In: failed to serialize token string.")
            return
        }
        guard let authorizationCodeString = String(
            data: appleAuthorizationCode,
            encoding: .utf8
        ), !authorizationCodeString.isEmpty else {
            MerianLog.auth.error("Apple Sign-In: failed to serialize the authorization code required for durable token revocation.")
            return
        }
        let credentialRegistrationId = UUID()

        Task {
            var didInstallAppleSession = false
            do {
                let previousUserId = try await self.finalizeOAuthLogin(
                    provider: .apple,
                    idToken: idTokenString,
                    accessToken: nil,
                    nonce: nonce
                )
                didInstallAppleSession = true
                try await self.registerAppleRevocationCredential(
                    registrationId: credentialRegistrationId,
                    authorizationCode: authorizationCodeString,
                    identityToken: idTokenString
                )
                let didPersistAppleMetadata = await updateAppleUserMetadataIfAvailable(
                    from: appleIDCredential.fullName
                )
                let session = try await client.auth.session
                currentUser = session.user
                isAuthenticated = true
                leaveGhostMode(for: session.user.id)
                _ = await ensureTelemetryLinkedIfNeeded(for: session.user)
                if didPersistAppleMetadata {
                    _ = await refreshPublicAuthorIdentity()
                }
                publishPublicAuthorIdentityChanged(
                    previousUserId: previousUserId,
                    currentUserId: session.user.id.uuidString
                )
                KeychainManager.shared.set(true, forKey: KeychainKeys.hasAuthenticatedOAuth)
                MerianLog.auth.debug("Apple Sign-In complete.")
            } catch {
                if didInstallAppleSession {
                    await self.clearLocalSessionAfterAuthFailure()
                }
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

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

private struct LegacyPrincipalRotation: Codable, Equatable {
    let sourceUserId: String
    let purchasePrincipalId: String
    let revenueCatAppUserId: String
    let installationCapabilityFingerprint: String
    let startedAt: String
}

private enum PrincipalRotationLocalState: String, Codable {
    case preparing
    case prepared
}

private struct ServerPrincipalRotation: Codable, Equatable {
    let protocolVersion: Int
    let localState: PrincipalRotationLocalState
    let rotationId: String
    let rotationSecret: String
    let sourceUserId: String
    let purchasePrincipalId: String
    let revenueCatAppUserId: String
    let bindingGeneration: Int64
    let installationCapabilityFingerprint: String
    let startedAt: String
    let expiresAt: String?
}

private enum PendingPurchasePrincipalAuthRotation: Equatable {
    case legacy(LegacyPrincipalRotation)
    case server(ServerPrincipalRotation)

    var sourceUserId: String {
        switch self {
        case let .legacy(rotation): rotation.sourceUserId
        case let .server(rotation): rotation.sourceUserId
        }
    }

    var purchasePrincipalId: String {
        switch self {
        case let .legacy(rotation): rotation.purchasePrincipalId
        case let .server(rotation): rotation.purchasePrincipalId
        }
    }

    var revenueCatAppUserId: String {
        switch self {
        case let .legacy(rotation): rotation.revenueCatAppUserId
        case let .server(rotation): rotation.revenueCatAppUserId
        }
    }

    var installationCapabilityFingerprint: String {
        switch self {
        case let .legacy(rotation):
            rotation.installationCapabilityFingerprint
        case let .server(rotation):
            rotation.installationCapabilityFingerprint
        }
    }
}

enum SupabaseAuthTransitionError: LocalizedError {
    case signOutInProgress
    case invalidOAuthIdentityToken
    case guestMergeSessionChanged
    case guestMergeHandoffPersistenceFailed
    case signOutPurchaseHandoffPersistenceFailed
    case signOutPurchaseContinuityPending
    case signOutSessionChanged
    case purchasePrincipalRotationPersistenceFailed
    case accountDeletionRecoveryPersistenceFailed
    case accountDeletionRecoveryPending
    case accountBoundWorkQuiescenceFailed

    var errorDescription: String? {
        switch self {
        case .signOutInProgress:
            return "Authentication is changing. Try again in a moment."
        case .invalidOAuthIdentityToken:
            return "The identity provider returned an invalid token."
        case .guestMergeSessionChanged:
            return "Your signed-out session changed before the account upgrade could be secured."
        case .guestMergeHandoffPersistenceFailed:
            return "The account upgrade could not be secured on this device. Your signed-out session is unchanged."
        case .signOutPurchaseHandoffPersistenceFailed:
            return "Purchase access could not be secured on this device. Your account is still signed in."
        case .signOutPurchaseContinuityPending:
            return "Purchase access is still syncing after sign-out. Please try again."
        case .signOutSessionChanged:
            return "The signed-out session changed before purchase access finished syncing."
        case .purchasePrincipalRotationPersistenceFailed:
            return "Purchase access could not be secured on this device. Your account is still signed in."
        case .accountDeletionRecoveryPersistenceFailed:
            return "Account deletion could not be secured on this device. Your account is unchanged."
        case .accountDeletionRecoveryPending:
            return "Account deletion cleanup is still finishing on this device."
        case .accountBoundWorkQuiescenceFailed:
            return "Background work could not be safely paused. Your account is unchanged. Try again."
        }
    }
}

enum AccountPresentationPolicy {
    static func isGuest(
        userID: UUID?,
        authIsAnonymous: Bool
    ) -> Bool {
        userID == nil || authIsAnonymous
    }
}

enum AuthTransitionProvider: String, Equatable, Sendable {
    case apple
    case google
}

enum AuthTransitionKind: Equatable, Sendable {
    case oauth(AuthTransitionProvider)
    case authenticationCallback
    case anonymousBootstrap
    case signOut
    case recovery
    case accountDeletion
    case accountDeletionCleanup
}

enum AuthTransitionPhase: String, Equatable, Sendable {
    case preparing
    case awaitingProvider
    case installingSession
    case bindingPurchases
    case deletingAccount
    case finalizing
}

struct AuthTransitionSession: Equatable, Sendable {
    let userID: UUID
    let isAnonymous: Bool
}

struct AuthTransitionToken: Equatable, Sendable {
    let id: UUID
    let kind: AuthTransitionKind
}

struct AuthTransitionState: Equatable, Sendable {
    let token: AuthTransitionToken
    var phase: AuthTransitionPhase
    let sourceSession: AuthTransitionSession?
    var expectedSession: AuthTransitionSession?
    var authGeneration: UInt64
}

struct AccountBoundWorkLease: Equatable, Sendable {
    let id: UUID
    let session: AuthTransitionSession
}

struct AccountBoundWorkCoordinator {
    private(set) var activeSessionsByLeaseID:
        [UUID: AuthTransitionSession] = [:]

    var isEmpty: Bool { activeSessionsByLeaseID.isEmpty }

    mutating func begin(
        session: AuthTransitionSession,
        id: UUID = UUID()
    ) -> AccountBoundWorkLease {
        activeSessionsByLeaseID[id] = session
        return AccountBoundWorkLease(id: id, session: session)
    }

    func owns(_ lease: AccountBoundWorkLease) -> Bool {
        activeSessionsByLeaseID[lease.id] == lease.session
    }

    @discardableResult
    mutating func finish(_ lease: AccountBoundWorkLease) -> Bool {
        guard owns(lease) else { return false }
        activeSessionsByLeaseID[lease.id] = nil
        return true
    }
}

struct AuthTransitionCoordinator {
    private(set) var active: AuthTransitionState?

    mutating func begin(
        kind: AuthTransitionKind,
        sourceSession: AuthTransitionSession?,
        authGeneration: UInt64,
        id: UUID = UUID()
    ) -> AuthTransitionToken? {
        guard active == nil else { return nil }
        let token = AuthTransitionToken(id: id, kind: kind)
        active = AuthTransitionState(
            token: token,
            phase: .preparing,
            sourceSession: sourceSession,
            expectedSession: sourceSession,
            authGeneration: authGeneration
        )
        return token
    }

    func owns(_ token: AuthTransitionToken) -> Bool {
        active?.token == token
    }

    @discardableResult
    mutating func updatePhase(
        _ phase: AuthTransitionPhase,
        for token: AuthTransitionToken
    ) -> Bool {
        guard active?.token == token else { return false }
        active?.phase = phase
        return true
    }

    @discardableResult
    mutating func adoptExpectedSession(
        _ session: AuthTransitionSession?,
        authGeneration: UInt64,
        for token: AuthTransitionToken
    ) -> Bool {
        guard active?.token == token else { return false }
        active?.expectedSession = session
        active?.authGeneration = authGeneration
        return true
    }

    mutating func observeAuthEvent(
        session: AuthTransitionSession?,
        authGeneration: UInt64
    ) {
        guard let expected = active?.expectedSession,
              expected == session else {
            if active?.expectedSession == nil, session == nil {
                active?.authGeneration = authGeneration
            }
            return
        }
        active?.authGeneration = authGeneration
    }

    func validatesExpectedSession(
        _ session: AuthTransitionSession?,
        authGeneration: UInt64,
        for token: AuthTransitionToken
    ) -> Bool {
        guard let active, active.token == token else { return false }
        return active.expectedSession == session
            && active.authGeneration == authGeneration
    }

    @discardableResult
    mutating func finish(_ token: AuthTransitionToken) -> Bool {
        guard active?.token == token else { return false }
        active = nil
        return true
    }
}

@MainActor
final class AuthTransitionSingleFlight {
    private var task: Task<Bool, Never>?

    var isRunning: Bool { task != nil }

    func run(
        operation: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        if let task {
            return await task.value
        }

        let task = Task { @MainActor in
            await operation()
        }
        self.task = task
        let result = await task.value
        self.task = nil
        return result
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

    private struct SignOutPurchasePreparePayload: Encodable {
        let operation = "prepare"
    }

    private struct SignOutPurchasePrepareResponse: Decodable {
        let success: Bool
        let handoff_id: String
        let handoff_secret: String
        let expires_at: String
    }

    private struct SignOutPurchaseContinuePayload: Encodable {
        let operation: String
        let handoff_id: String
        let handoff_secret: String
    }

    private struct SignOutPurchaseOperationResponse: Decodable {
        let success: Bool
        let handoff_id: String
    }

    private struct SignOutPurchaseBindResponse: Decodable {
        let success: Bool
        let handoff_id: String
        let destination_user_id: String
    }

    private struct SignOutPurchaseErrorPayload: Decodable {
        let code: String?
    }

    struct PendingSignOutPurchaseHandoff: Codable, Equatable {
        let sourceUserId: String
        let handoffId: String
        let handoffSecret: String
        let expiresAt: String
    }

    // MARK: - Singleton Architecture
    static let shared = SupabaseManager()

    // MARK: - Client
    let client: SupabaseClient
    private let purchasePrincipalResolver: PurchasePrincipalResolver

    // MARK: - State
    var currentUser: User?
    var isAuthenticated: Bool = false

    var isGuestUser: Bool {
        AccountPresentationPolicy.isGuest(
            userID: currentUser?.id,
            authIsAnonymous: currentUser?.isAnonymous ?? true
        )
    }

    var currentUserAvatarUrl: URL? {
        guard let urlString = currentUser?.userMetadata["avatar_url"]?.stringValue ?? currentUser?.userMetadata["picture"]?.stringValue else {
            return nil
        }
        return SecureTransportPolicy.httpsURL(from: urlString)
    }

    // MARK: - Authentication Transition State
    private var authTransitionCoordinator = AuthTransitionCoordinator()
    @ObservationIgnored private var authTransitionAnalyticsGenerations:
        [UUID: UInt] = [:]
    private var accountBoundWorkCoordinator = AccountBoundWorkCoordinator()
    @ObservationIgnored private var accountBoundWorkDrainWaiters:
        [CheckedContinuation<Void, Never>] = []

    var activeAuthTransition: AuthTransitionState? {
        authTransitionCoordinator.active
    }

    var isAuthTransitionInProgress: Bool {
        activeAuthTransition != nil
    }

    /// Account-scoped work that does not own the active Auth transition may
    /// start only while the current session is stable. Background workers use
    /// this gate before dispatch and immediately before their remote mutation;
    /// transition-owned requests use the token-aware request path instead.
    var allowsUnownedAccountBoundWork: Bool {
        isAuthenticated
            && currentUser != nil
            && !isSigningOut
            && Self.allowsAuthenticatedRequest(
                activeTransition: activeAuthTransition?.token,
                requestOwner: nil,
                accountDeletionCleanupPending:
                    AccountDeletionLocalCleanupStore.isPending()
            )
    }

    /// Atomically admits ordinary account work only while Auth has no
    /// transition owner. The returned lease keeps the exact SDK session stable
    /// until the caller finishes; every Auth mutation drains admitted leases.
    func beginUnownedAccountBoundWork(
        expectedUserID: UUID? = nil
    ) throws -> AccountBoundWorkLease {
        guard allowsUnownedAccountBoundWork,
              let currentUser,
              let sdkUser = client.auth.currentSession?.user,
              currentUser.id == sdkUser.id,
              currentUser.isAnonymous == sdkUser.isAnonymous,
              expectedUserID.map({ $0 == sdkUser.id }) ?? true else {
            throw SupabaseAuthTransitionError.signOutInProgress
        }
        return accountBoundWorkCoordinator.begin(
            session: transitionSession(from: sdkUser)!
        )
    }

    func isAccountBoundWorkLeaseCurrent(
        _ lease: AccountBoundWorkLease
    ) -> Bool {
        guard accountBoundWorkCoordinator.owns(lease),
              let currentUser,
              let sdkUser = client.auth.currentSession?.user else {
            return false
        }
        let observed = transitionSession(from: sdkUser)
        return transitionSession(from: currentUser) == lease.session
            && observed == lease.session
    }

    func finishAccountBoundWork(_ lease: AccountBoundWorkLease) {
        guard accountBoundWorkCoordinator.finish(lease),
              accountBoundWorkCoordinator.isEmpty else {
            return
        }
        let waiters = accountBoundWorkDrainWaiters
        accountBoundWorkDrainWaiters.removeAll(keepingCapacity: true)
        for waiter in waiters {
            waiter.resume()
        }
    }

    var isOAuthTransitionInProgress: Bool {
        guard let kind = activeAuthTransition?.token.kind,
              case .oauth = kind else {
            return false
        }
        return true
    }

    private var isUserSignOutTransitionInProgress: Bool {
        guard let kind = activeAuthTransition?.token.kind,
              case .signOut = kind else {
            return false
        }
        return true
    }

    private struct AppleSignInAttempt {
        let transition: AuthTransitionToken
        let nonce: String
        let controller: ASAuthorizationController
    }

    private struct OAuthLoginCompletion {
        let previousUserId: String?
        let session: Session
    }

    private var activeAppleSignInAttempt: AppleSignInAttempt?

    // MARK: - Session Deduplication
    /// Tracks the last user ID considered for RevenueCat linkage and history sync.
    /// Same-user auth events retry RevenueCat only while its identity fence is not ready;
    /// they never repeat the identity-change-only historical download.
    private var lastLinkedUserId: UUID?
    private var activePurchasePrincipalBinding: PurchasePrincipalBinding?
    private var authSessionGeneration: UInt64 = 0

    /// Retained handle for the auth state listener task. Stored so the task can be cancelled
    /// on teardown and is consistent with the @ObservationIgnored task handle pattern used
    /// throughout the engine layer. Fire-and-forget tasks with no handle cannot be inspected,
    /// restarted, or cleanly shut down.
    @ObservationIgnored private var authListenerTask: Task<Void, Never>?
    /// Single-flight guard for anonymous session creation. Multiple callers can reach
    /// `initializeGhostSession()` while the first network round-trip is suspended; without this
    /// handle they each attempt a fresh anonymous sign-in and race to replace the active session.
    @ObservationIgnored private var ghostSessionTask: Task<User?, Never>?
    @ObservationIgnored private var ghostSessionTaskId: UUID?
    @ObservationIgnored private var ghostSessionTaskAuthTransitionId: UUID?
    /// Single-flight completion for a persisted provider-bound guest merge.
    /// Auth callbacks and the interactive login path can observe the same new
    /// permanent session; both converge on this task rather than racing cleanup.
    @ObservationIgnored private var ghostProfileMergeTask: Task<Bool, Never>?
    /// Identifies the currently retained task so a cancelled task that finishes
    /// later cannot clear the handle for a newer auth session's merge.
    @ObservationIgnored private var ghostProfileMergeTaskId: UUID?
    @ObservationIgnored private var ghostProfileMergeTaskTargetUserId: String?
    /// Single-flight completion for a durable signed-out purchase handoff.
    /// The interactive transition and restored-session callback can observe
    /// the same anonymous destination and must converge on one receipt sync.
    @ObservationIgnored private var signOutPurchaseHandoffTask: Task<Bool, Never>?
    @ObservationIgnored private var signOutPurchaseHandoffTaskId: UUID?
    @ObservationIgnored private var signOutPurchaseHandoffTargetUserId: String?
    @ObservationIgnored private var signOutPurchaseHandoffAuthGeneration: UInt64?
    @ObservationIgnored private var purchasePrincipalLinkTask:
        Task<PurchasePrincipalBinding?, Never>?
    @ObservationIgnored private var purchasePrincipalLinkTaskId: UUID?
    @ObservationIgnored private var purchasePrincipalLinkTaskUserId: UUID?
    @ObservationIgnored private var purchasePrincipalLinkTaskGeneration: UInt64?
    @ObservationIgnored private var purchasePrincipalLinkTaskCapabilityFingerprint: String?
    @ObservationIgnored private var purchasePrincipalLinkTaskAllowsCapabilityCreation = true
    /// Single-flight sign-out handle. Authenticated request creation is closed as
    /// soon as this transition begins, before the SDK invalidates the session.
    @ObservationIgnored private var signOutTask: Task<Void, Never>?
    @ObservationIgnored private let userSignOutSingleFlight =
        AuthTransitionSingleFlight()
    @ObservationIgnored private var publicAuthorIdentityRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var appleCredentialRevocationObserver: NSObjectProtocol?
    @ObservationIgnored private var pendingAppleCredentialRevalidation = false
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

        let client = MerianSupabaseClientFactory.makeClient(
            emitLocalSessionAsInitialSession: true
        )
        self.client = client
        self.purchasePrincipalResolver = PurchasePrincipalResolver(
            client: client
        )

        super.init()

        // Remove the retired presentation-only logout marker. Linked sessions
        // must restore as linked accounts; ordinary logout creates a new
        // anonymous session instead of masking an authenticated one.
        KeychainManager.shared.removeObject(forKey: KeychainKeys.legacyGhostModeUserID)
        do {
            let pendingLegacyHandoff = try loadPendingSignOutPurchaseHandoff()
            let pendingStableRotation = try loadPendingPurchasePrincipalAuthRotation()
            RevenueCatManager.shared.setPurchaseIdentityHandoffPending(
                pendingLegacyHandoff != nil || pendingStableRotation != nil
            )
        } catch {
            // Keychain uncertainty is not evidence that a purchase handoff is
            // absent. Keep provider mutations fail-closed until it is resolved.
            RevenueCatManager.shared.setPurchaseIdentityHandoffPending(true)
        }
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
        signOutPurchaseHandoffTask?.cancel()
        purchasePrincipalLinkTask?.cancel()
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

    private func transitionSession(from user: User?) -> AuthTransitionSession? {
        user.map {
            AuthTransitionSession(
                userID: $0.id,
                isAnonymous: $0.isAnonymous
            )
        }
    }

    private func beginAuthTransition(
        _ kind: AuthTransitionKind
    ) -> AuthTransitionToken? {
        if let deletionRecoveryState =
            AccountDeletionLocalCleanupStore.state() {
            guard Self.allowsAuthTransitionDuringAccountDeletionRecovery(
                recoveryState: deletionRecoveryState,
                kind: kind
            ) else { return nil }
        }
        let sourceUser = client.auth.currentSession?.user ?? currentUser
        guard let token = authTransitionCoordinator.begin(
            kind: kind,
            sourceSession: transitionSession(from: sourceUser),
            authGeneration: authSessionGeneration
        ) else {
            return nil
        }
        AppDIContainer.shared.inferenceEngine.beginAuthTransitionWriteFence()
        authTransitionAnalyticsGenerations[token.id] =
            ConsentManager.shared.beginAnalyticsAccountTransition()
        appRouteSessionController?.beginAccountSession(
            accountID: nil,
            origin: .runtimeTransition,
            now: Date()
        )
        milestoneToastSessionController?.beginAccountSession(
            accountID: nil,
            origin: .runtimeTransition,
            now: Date()
        )
        return token
    }

    static func allowsAuthTransitionDuringAccountDeletionRecovery(
        recoveryState: AccountDeletionLocalRecoveryState,
        kind: AuthTransitionKind
    ) -> Bool {
        switch (recoveryState, kind) {
        case (.intakePending, .accountDeletion),
             (.capabilityPreparationPending, .accountDeletion),
             (.capabilityPreparedPending, .accountDeletion),
             (.capabilityIntakePending, .accountDeletion),
             (.cleanupPending, .accountDeletionCleanup),
             (.capabilityCleanupPending, .accountDeletionCleanup),
             (.capabilityRetirementPending, .accountDeletionCleanup),
             (.capabilityRejectionRetirementPending,
              .accountDeletionCleanup),
             (.capabilityLookupPending, .accountDeletionCleanup):
            return true
        default:
            return false
        }
    }

    func ownsAuthTransition(_ token: AuthTransitionToken) -> Bool {
        authTransitionCoordinator.owns(token)
    }

    private func authTransitionAllows(
        _ token: AuthTransitionToken?
    ) -> Bool {
        if let active = activeAuthTransition?.token {
            return token == active
        }
        return token == nil
    }

    static func allowsAuthenticatedRequest(
        activeTransition: AuthTransitionToken?,
        requestOwner: AuthTransitionToken?,
        accountDeletionCleanupPending: Bool
    ) -> Bool {
        if accountDeletionCleanupPending {
            // The only network call allowed behind the durable deletion fence
            // is an exact-owner replay of the idempotent intake. Accepted local
            // cleanup never owns `.accountDeletion` and therefore stays fully
            // offline.
            guard let activeTransition,
                  activeTransition.kind == .accountDeletion else {
                return false
            }
            return requestOwner == activeTransition
        }
        if let activeTransition {
            return requestOwner == activeTransition
        }
        return requestOwner == nil
    }

    static func shouldDeferAuthListenerSideEffects(
        hasActiveTransition: Bool,
        accountDeletionCleanupPending: Bool
    ) -> Bool {
        hasActiveTransition || accountDeletionCleanupPending
    }

    @discardableResult
    private func updateAuthTransition(
        _ token: AuthTransitionToken,
        phase: AuthTransitionPhase
    ) -> Bool {
        authTransitionCoordinator.updatePhase(phase, for: token)
    }

    @discardableResult
    private func adoptAuthTransitionSession(
        _ session: User?,
        for token: AuthTransitionToken
    ) -> Bool {
        authTransitionCoordinator.adoptExpectedSession(
            transitionSession(from: session),
            authGeneration: authSessionGeneration,
            for: token
        )
    }

    private func finishAuthTransition(_ token: AuthTransitionToken) {
        guard authTransitionCoordinator.owns(token) else { return }
        let analyticsGeneration =
            authTransitionAnalyticsGenerations.removeValue(forKey: token.id)
        guard authTransitionCoordinator.finish(token) else { return }
        AppDIContainer.shared.inferenceEngine.finishAuthTransitionWriteFence()
        let sdkSession = client.auth.currentSession
        let finalUserID: UUID?
        if let sdkSession,
           !sdkSession.isExpired,
           currentUser?.id == sdkSession.user.id,
           isAuthenticated {
            finalUserID = sdkSession.user.id
        } else {
            finalUserID = nil
        }
        appRouteSessionController?.beginAccountSession(
            accountID: finalUserID?.uuidString,
            origin: .runtimeTransition,
            now: Date()
        )
        milestoneToastSessionController?.beginAccountSession(
            accountID: finalUserID?.uuidString,
            origin: .runtimeTransition,
            now: Date()
        )
        if let analyticsGeneration {
            _ = ConsentManager.shared.resolveAnalyticsAccountTransition(
                generation: analyticsGeneration,
                userId: finalUserID
            )
        }
        if let finalUser = currentUser,
           finalUser.id == finalUserID {
            schedulePublicAuthorIdentityRefreshIfNeeded(for: finalUser)
        }
        if pendingAppleCredentialRevalidation {
            pendingAppleCredentialRevalidation = false
            revalidateAppleCredentialAfterRevocationNotification()
        }
    }

    private func analyticsGeneration(
        for transition: AuthTransitionToken
    ) -> UInt {
        guard ownsAuthTransition(transition),
              let generation =
                authTransitionAnalyticsGenerations[transition.id] else {
            // This path is defensive: a valid owner always receives its
            // generation atomically in `beginAuthTransition`.
            return 0
        }
        return generation
    }

    func currentSessionMatchesAuthTransition(
        _ token: AuthTransitionToken
    ) -> Bool {
        guard ownsAuthTransition(token) else { return false }
        return authTransitionCoordinator.validatesExpectedSession(
            transitionSession(from: client.auth.currentSession?.user),
            authGeneration: authSessionGeneration,
            for: token
        )
    }

    private func awaitAccountBoundWorkQuiescenceForAuthTransition() async
        -> Bool {
        // Closing the Auth transition happens synchronously before this drain,
        // so no new ordinary lease or collection mutation can enter. Existing
        // work completes against the preserved source session.
        await ConsentManager.shared
            .cancelAndAwaitSynchronizationForAuthTransition()
        await AppDIContainer.shared.inferenceEngine
            .awaitAuthTransitionWriteQuiescence()
        guard await OfflineQueueManager.shared
            .quiesceBackgroundAccountWorkForAuthTransition(
                sourceUserID:
                    authTransitionCoordinator.active?.sourceSession?.userID
            ) else {
            MerianLog.auth.error(
                "Authentication transition stopped because background account work could not be durably paused."
            )
            return false
        }
        await OfflineQueueManager.shared
            .awaitCollectionSyncQuiescenceForAuthTransition()
        guard !accountBoundWorkCoordinator.isEmpty else { return true }
        await withCheckedContinuation { continuation in
            if accountBoundWorkCoordinator.isEmpty {
                continuation.resume()
            } else {
                accountBoundWorkDrainWaiters.append(continuation)
            }
        }
        return true
    }

    private func verifiedExpectedSession(
        for token: AuthTransitionToken
    ) async throws -> Session {
        guard ownsAuthTransition(token) else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        guard await awaitAccountBoundWorkQuiescenceForAuthTransition() else {
            throw SupabaseAuthTransitionError.accountBoundWorkQuiescenceFailed
        }
        guard ownsAuthTransition(token) else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        let session = try await client.auth.session
        guard ownsAuthTransition(token),
              authTransitionCoordinator.validatesExpectedSession(
                transitionSession(from: session.user),
                authGeneration: authSessionGeneration,
                for: token
              ) else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        return session
    }

    private func verifiedExpectedSessionIfPresent(
        for token: AuthTransitionToken
    ) async throws -> Session? {
        guard await awaitAccountBoundWorkQuiescenceForAuthTransition() else {
            throw SupabaseAuthTransitionError.accountBoundWorkQuiescenceFailed
        }
        guard ownsAuthTransition(token) else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        guard let expected = authTransitionCoordinator.active?.expectedSession
        else {
            guard ownsAuthTransition(token),
                  client.auth.currentSession == nil,
                  authTransitionCoordinator.validatesExpectedSession(
                    nil,
                    authGeneration: authSessionGeneration,
                    for: token
                  ) else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }
            return nil
        }
        let session = try await verifiedExpectedSession(for: token)
        guard session.user.id == expected.userID,
              session.user.isAnonymous == expected.isAnonymous else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        return session
    }

    static func shouldAcceptAppleSignInCallback(
        activeTransitionID: UUID?,
        attemptTransitionID: UUID,
        controllerMatches: Bool
    ) -> Bool {
        controllerMatches && activeTransitionID == attemptTransitionID
    }

    static func shouldClearOAuthSessionAfterFailure(
        observedSessionMutation: Bool,
        sourceSession: AuthTransitionSession?,
        currentSession: AuthTransitionSession?
    ) -> Bool {
        observedSessionMutation || sourceSession != currentSession
    }

    static func allowsOAuthMetadataMutation(
        transitionIsCurrent: Bool,
        transitionExpectedUserID: UUID?,
        currentSessionUserID: UUID?,
        expectedUserID: UUID,
        updatedUserID: UUID? = nil
    ) -> Bool {
        transitionIsCurrent
            && transitionExpectedUserID == expectedUserID
            && currentSessionUserID == expectedUserID
            && (updatedUserID.map { $0 == expectedUserID } ?? true)
    }

    static func acceptsAuthenticationCallbackTarget(
        sourceSession: AuthTransitionSession?,
        targetSession: AuthTransitionSession
    ) -> Bool {
        guard let sourceSession else { return true }
        return !sourceSession.isAnonymous
            && sourceSession.userID == targetSession.userID
            && !targetSession.isAnonymous
    }

    private func revalidateAppleCredentialAfterRevocationNotification() {
        guard !isAuthTransitionInProgress else {
            pendingAppleCredentialRevalidation = true
            return
        }
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

                guard !self.isAuthTransitionInProgress else {
                    self.pendingAppleCredentialRevalidation = true
                    return
                }

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
                authSessionGeneration &+= 1
                let eventAuthGeneration = authSessionGeneration
                authTransitionCoordinator.observeAuthEvent(
                    session: transitionSession(from: state.session?.user),
                    authGeneration: eventAuthGeneration
                )
                let deletionCleanupPending =
                    AccountDeletionLocalCleanupStore.isPending()
                if deletionCleanupPending {
                    // Server acceptance is a durable local-auth fence. A
                    // cached source session must not restore, relink billing,
                    // or start account work before launch recovery signs it
                    // out and finishes local erasure.
                    currentUser = nil
                    isAuthenticated = false
                    activePurchasePrincipalBinding = nil
                    RevenueCatManager.shared.beginPurchaseIdentityResolution()
                    MerianLog.auth.debug(
                        "Deferred an SDK auth event until accepted account deletion cleanup finishes."
                    )
                    continue
                }
                if Self.shouldDeferAuthListenerSideEffects(
                    hasActiveTransition:
                        authTransitionCoordinator.active != nil,
                    accountDeletionCleanupPending: deletionCleanupPending
                ) {
                    // Auth events still advance the generation above so the
                    // owner can adopt the exact SDK destination. Every
                    // account-bound side effect remains owned by that one
                    // transition until it has verified its final session.
                    MerianLog.auth.debug(
                        "Deferred an SDK auth event to the active authentication transition."
                    )
                    continue
                }
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
                        "Could not read the signed-out handoff queue; analytics remains suppressed; kind=\(MerianLog.errorKind(error), privacy: .public)"
                    )
                }
                do {
                    let pendingLegacyHandoff = try loadPendingSignOutPurchaseHandoff()
                    let pendingStableRotation = try loadPendingPurchasePrincipalAuthRotation()
                    RevenueCatManager.shared.setPurchaseIdentityHandoffPending(
                        pendingLegacyHandoff != nil || pendingStableRotation != nil
                    )
                } catch {
                    RevenueCatManager.shared.setPurchaseIdentityHandoffPending(true)
                    MerianLog.auth.error(
                        "Could not read the sign-out purchase handoff; purchase mutations remain disabled; kind=\(MerianLog.errorKind(error), privacy: .public)"
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
                    if currentUser?.id != session.user.id {
                        activePurchasePrincipalBinding = nil
                        lastLinkedUserId = nil
                    }
                    self.currentUser = session.user
                    self.isAuthenticated = true
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
                    schedulePublicAuthorIdentityRefreshIfNeeded(for: session.user)

                    var didLinkExternalIdentity = false
                    if !TestExecutionCoordinator.isRunningTests {
                        if session.user.isAnonymous,
                           RevenueCatManager.shared
                            .isPurchaseIdentityHandoffPending {
                            // A sign-out handoff binds the exact anonymous
                            // destination before RevenueCat is allowed to
                            // switch identities or restore a receipt.
                            _ = await completePendingSignOutPurchaseHandoffIfNeeded(
                                expectedDestinationUserId: session.user.id.uuidString,
                                expectedAuthGeneration: eventAuthGeneration
                            )
                        } else {
                            didLinkExternalIdentity = await self
                                .ensureTelemetryLinkedWhenSafe(
                                    for: session.user,
                                )
                        }
                        if !session.user.isAnonymous,
                           RevenueCatManager.shared
                            .isPurchaseIdentityHandoffPending,
                           !isUserSignOutTransitionInProgress {
                            await abandonPendingPurchasePrincipalRotationIfSourceRestored(
                                sourceUserId: session.user.id
                            )
                            await abandonPendingSignOutPurchaseHandoffIfSourceRestored(
                                sourceUserId: session.user.id.uuidString
                            )
                            if !RevenueCatManager.shared
                                .isPurchaseIdentityHandoffPending {
                                didLinkExternalIdentity = await self
                                    .ensureTelemetryLinkedWhenSafe(
                                        for: session.user
                                    )
                            }
                        }
                    }
                    guard authSessionGeneration == eventAuthGeneration,
                          currentUser?.id == session.user.id else {
                        continue
                    }
                    if RevenueCatManager.shared
                        .isPurchaseIdentityHandoffPending {
                        // An unrelated permanent session must not gain either
                        // provider-backed or account-backed paid readiness
                        // while another source's sign-out rotation is live.
                        EntitlementManager.shared.handleSignOut()
                    } else {
                        await EntitlementManager.shared.beginSession(
                            userID: session.user.id,
                            client: client
                        )
                    }
                    if didLinkExternalIdentity {
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
                    self.activePurchasePrincipalBinding = nil
                    RevenueCatManager.shared.beginPurchaseIdentityResolution()
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
                    self.activePurchasePrincipalBinding = nil
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
                    await RevenueCatManager.shared.handleSupabaseSignOut()
                    lastLinkedUserId = nil
                    lastPublicAuthorIdentityRefreshUserId = nil
                    publicAuthorIdentityRefreshTask?.cancel()
                    publicAuthorIdentityRefreshTask = nil
                    cancelGhostProfileMergeTask()
                }

                MerianLog.auth.debug(
                    "Processed an authentication state change."
                )
            }
        }
    }

    private func linkLegacyRevenueCatIdentity(user: User) async {
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

    /// An already-issued v1 sign-out proof is bound to the destination Auth
    /// UUID's RevenueCat customer. Finish that immutable compatibility
    /// contract before allowing a concurrent stable-principal rollout to
    /// adopt the installation. Otherwise receipt sync could target the new
    /// principal while server completion still verifies the legacy UUID.
    private func linkLegacyRevenueCatIdentityForSignOutHandoff(
        user: User
    ) async throws {
        await linkLegacyRevenueCatIdentity(user: user)
        let expectedAppUserID = RevenueCatAppUserIDPolicy.canonicalID(
            for: user.id
        )
        guard RevenueCatManager.shared.isIdentityReady,
              !RevenueCatManager.shared.usesStablePurchasePrincipal,
              RevenueCatManager.shared.linkedAppUserID == expectedAppUserID,
              RevenueCatManager.shared.linkedAuthUserID == user.id else {
            throw SupabaseAuthTransitionError
                .signOutPurchaseContinuityPending
        }
        activePurchasePrincipalBinding = .legacyFallback
    }

    private func resolveAndLinkPurchasePrincipal(
        for user: User,
        expectedAuthGeneration: UInt64,
        expectedCapabilityFingerprint: String? = nil,
        allowsCapabilityCreation: Bool = true
    ) async -> PurchasePrincipalBinding? {
        if let existingTask = purchasePrincipalLinkTask,
           purchasePrincipalLinkTaskUserId == user.id,
           purchasePrincipalLinkTaskGeneration == expectedAuthGeneration,
           purchasePrincipalLinkTaskCapabilityFingerprint
            == expectedCapabilityFingerprint,
           purchasePrincipalLinkTaskAllowsCapabilityCreation
            == allowsCapabilityCreation {
            return await existingTask.value
        }
        cancelPurchasePrincipalLinkTask()

        let taskId = UUID()
        let task: Task<PurchasePrincipalBinding?, Never> = Task { @MainActor [weak self] in
            guard let self else { return nil }
            return await self.performPurchasePrincipalLink(
                for: user,
                expectedAuthGeneration: expectedAuthGeneration,
                expectedCapabilityFingerprint: expectedCapabilityFingerprint,
                allowsCapabilityCreation: allowsCapabilityCreation
            )
        }
        purchasePrincipalLinkTask = task
        purchasePrincipalLinkTaskId = taskId
        purchasePrincipalLinkTaskUserId = user.id
        purchasePrincipalLinkTaskGeneration = expectedAuthGeneration
        purchasePrincipalLinkTaskCapabilityFingerprint =
            expectedCapabilityFingerprint
        purchasePrincipalLinkTaskAllowsCapabilityCreation =
            allowsCapabilityCreation
        let result = await task.value
        if purchasePrincipalLinkTaskId == taskId {
            purchasePrincipalLinkTask = nil
            purchasePrincipalLinkTaskId = nil
            purchasePrincipalLinkTaskUserId = nil
            purchasePrincipalLinkTaskGeneration = nil
            purchasePrincipalLinkTaskCapabilityFingerprint = nil
            purchasePrincipalLinkTaskAllowsCapabilityCreation = true
        }
        return result
    }

    private func performPurchasePrincipalLink(
        for user: User,
        expectedAuthGeneration: UInt64,
        expectedCapabilityFingerprint: String?,
        allowsCapabilityCreation: Bool
    ) async -> PurchasePrincipalBinding? {
        guard currentUser?.id == user.id,
              authSessionGeneration == expectedAuthGeneration,
              !Task.isCancelled else {
            return nil
        }
        // A fresh resolver attempt invalidates any prior mode decision. If the
        // request or its durable activation write fails, callers must not fall
        // through using a stale legacy binding from an earlier auth event.
        activePurchasePrincipalBinding = nil
        RevenueCatManager.shared.beginPurchaseIdentityResolution()
        do {
            let binding = try await purchasePrincipalResolver.resolve(
                expectedCapabilityFingerprint: expectedCapabilityFingerprint,
                allowsCapabilityCreation: allowsCapabilityCreation
            )
            guard currentUser?.id == user.id,
                  authSessionGeneration == expectedAuthGeneration,
                  !Task.isCancelled else {
                return nil
            }
            // The server's explicit mode is authoritative even if the
            // provider SDK cannot finish linking in this attempt. Sign-out may
            // use the legacy handoff only after an explicit legacy response;
            // a transient stable-link failure must never fall through to a
            // receipt-transfer protocol.
            activePurchasePrincipalBinding = binding

            let accountKind = RevenueCatAccountMutationPolicy.accountKind(
                isAnonymous: user.isAnonymous
            )
            switch binding.mode {
            case .stable:
                await RevenueCatManager.shared.linkResolvedPurchasePrincipal(
                    binding,
                    authUserID: user.id,
                    accountKind: accountKind
                )
            case .legacy:
                await linkLegacyRevenueCatIdentity(user: user)
            }

            guard currentUser?.id == user.id,
                  authSessionGeneration == expectedAuthGeneration,
                  !Task.isCancelled,
                  RevenueCatManager.shared.isIdentityReady else {
                return nil
            }
            return binding
        } catch {
            MerianLog.auth.debug(
                "Purchase identity resolution failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
            return nil
        }
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
            MerianLog.auth.debug(
                "RevenueCat public identity lookup failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
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
    private func ensureTelemetryLinkedIfNeeded(
        for user: User,
        expectedAuthGeneration: UInt64? = nil,
        expectedCapabilityFingerprint: String? = nil,
        allowsCapabilityCreation: Bool = true
    ) async -> Bool {
        let userId = user.id
        let generation = expectedAuthGeneration ?? authSessionGeneration
        let identityChanged = userId != lastLinkedUserId
        let expectedAccountKind = RevenueCatAccountMutationPolicy.accountKind(
            isAnonymous: user.isAnonymous
        )
        let accountKindChanged = RevenueCatManager.shared.linkedAccountKind
            != expectedAccountKind
        guard expectedCapabilityFingerprint != nil ||
                activePurchasePrincipalBinding == nil || identityChanged ||
                accountKindChanged ||
                !RevenueCatManager.shared.isIdentityReady else {
            return false
        }
        guard await resolveAndLinkPurchasePrincipal(
            for: user,
            expectedAuthGeneration: generation,
            expectedCapabilityFingerprint: expectedCapabilityFingerprint,
            allowsCapabilityCreation: allowsCapabilityCreation
        ) != nil else {
            return false
        }
        lastLinkedUserId = userId
        return identityChanged
    }

    static func shouldDeferExternalIdentityLink(
        isAnonymous: Bool,
        purchaseIdentityHandoffPending: Bool
    ) -> Bool {
        _ = isAnonymous
        return purchaseIdentityHandoffPending
    }

    nonisolated static func shouldRestoreSourceIdentityAfterFailedSignOut(
        activeUserId: UUID?,
        activeUserIsAnonymous: Bool,
        sourceUserId: UUID,
        purchaseContinuityPending: Bool
    ) -> Bool {
        activeUserId == sourceUserId
            && !activeUserIsAnonymous
            && !purchaseContinuityPending
    }

    @discardableResult
    private func ensureTelemetryLinkedWhenSafe(
        for user: User,
        ownedBy transition: AuthTransitionToken? = nil
    ) async -> Bool {
        let accountWorkLease: AccountBoundWorkLease?
        if let transition {
            guard ownsAuthTransition(transition),
                  client.auth.currentSession?.user.id == user.id else {
                return false
            }
            accountWorkLease = nil
        } else {
            guard let lease = try? beginUnownedAccountBoundWork(
                expectedUserID: user.id
            ) else { return false }
            accountWorkLease = lease
        }
        defer {
            if let accountWorkLease {
                finishAccountBoundWork(accountWorkLease)
            }
        }

        let legacyHandoffPending: Bool
        let stableRotationPending: Bool
        do {
            legacyHandoffPending = try loadPendingSignOutPurchaseHandoff() != nil
            stableRotationPending =
                try loadPendingPurchasePrincipalAuthRotation() != nil
        } catch {
            MerianLog.auth.error(
                "Deferred external identity linking because sign-out purchase state is unreadable."
            )
            return false
        }
        guard !Self.shouldDeferExternalIdentityLink(
            isAnonymous: user.isAnonymous,
            purchaseIdentityHandoffPending:
                legacyHandoffPending || stableRotationPending
        ) else {
            MerianLog.auth.debug(
                "Deferred external identity linking until the sign-out purchase destination is bound."
            )
            return false
        }
        let didLink = await ensureTelemetryLinkedIfNeeded(for: user)
        if let transition {
            guard ownsAuthTransition(transition),
                  client.auth.currentSession?.user.id == user.id else {
                return false
            }
        } else if let accountWorkLease {
            guard isAccountBoundWorkLeaseCurrent(accountWorkLease) else {
                return false
            }
        }
        return didLink
    }

    /// Repairs a fail-closed purchase-identity session when the app returns to
    /// the foreground. Auth-state delivery normally owns this work, but a
    /// transient resolver, account-cleanup, Keychain, or provider failure may
    /// finish without another SDK event. Retry only the exact current Auth
    /// generation and durable capability/handoff; never rotate either one.
    @discardableResult
    func retryPurchaseIdentityReadinessIfNeeded() async -> Bool {
        guard !TestExecutionCoordinator.isRunningTests,
              !AccountDeletionLocalCleanupStore.isPending(),
              !isSigningOut,
              isAuthenticated,
              let expectedUser = currentUser else {
            return false
        }
        guard let accountWorkLease = try? beginUnownedAccountBoundWork(
            expectedUserID: expectedUser.id
        ) else {
            return false
        }
        defer { finishAccountBoundWork(accountWorkLease) }

        let generation = authSessionGeneration
        let session: Session
        do {
            session = try await client.auth.session
        } catch {
            return false
        }
        guard !session.isExpired,
              session.user.id == expectedUser.id,
              isAccountBoundWorkLeaseCurrent(accountWorkLease),
              currentUser?.id == expectedUser.id,
              authSessionGeneration == generation else {
            return false
        }

        var legacyHandoffPending: Bool
        var stableRotationPending: Bool
        do {
            legacyHandoffPending = try loadPendingSignOutPurchaseHandoff() != nil
            stableRotationPending =
                try loadPendingPurchasePrincipalAuthRotation() != nil
        } catch {
            RevenueCatManager.shared.setPurchaseIdentityHandoffPending(true)
            return false
        }
        RevenueCatManager.shared.setPurchaseIdentityHandoffPending(
            legacyHandoffPending || stableRotationPending
        )

        if session.user.isAnonymous,
           legacyHandoffPending || stableRotationPending {
            return await completePendingSignOutPurchaseHandoffIfNeeded(
                expectedDestinationUserId: session.user.id.uuidString,
                expectedAuthGeneration: generation
            )
        }

        // A failed local sign-out can restore the linked source without
        // producing another Auth event. Retire only proofs issued by that exact
        // source, then re-read the durable fence before relinking anything.
        if !session.user.isAnonymous,
           legacyHandoffPending || stableRotationPending,
           !isUserSignOutTransitionInProgress {
            await abandonPendingPurchasePrincipalRotationIfSourceRestored(
                sourceUserId: session.user.id
            )
            await abandonPendingSignOutPurchaseHandoffIfSourceRestored(
                sourceUserId: session.user.id.uuidString
            )
            do {
                legacyHandoffPending =
                    try loadPendingSignOutPurchaseHandoff() != nil
                stableRotationPending =
                    try loadPendingPurchasePrincipalAuthRotation() != nil
            } catch {
                RevenueCatManager.shared
                    .setPurchaseIdentityHandoffPending(true)
                return false
            }
            RevenueCatManager.shared.setPurchaseIdentityHandoffPending(
                legacyHandoffPending || stableRotationPending
            )
            guard !legacyHandoffPending, !stableRotationPending else {
                return false
            }
        }

        let expectedAccountKind = RevenueCatAccountMutationPolicy.accountKind(
            isAnonymous: session.user.isAnonymous
        )
        let identityWasAlreadyReady =
            activePurchasePrincipalBinding != nil &&
            RevenueCatManager.shared.isIdentityReady &&
            RevenueCatManager.shared.linkedAuthUserID == session.user.id &&
            RevenueCatManager.shared.linkedAccountKind == expectedAccountKind
        if !identityWasAlreadyReady {
            _ = await ensureTelemetryLinkedWhenSafe(
                for: session.user
            )
        }

        guard currentUser?.id == session.user.id,
              authSessionGeneration == generation,
              activePurchasePrincipalBinding != nil,
              RevenueCatManager.shared.isIdentityReady,
              RevenueCatManager.shared.linkedAuthUserID == session.user.id,
              RevenueCatManager.shared.linkedAccountKind
                == expectedAccountKind else {
            return false
        }

        let entitlementIsReady: Bool
        if EntitlementManager.shared.activeAccountID == session.user.id,
           EntitlementManager.shared.isVerifiedForCurrentLaunch {
            entitlementIsReady = true
        } else {
            entitlementIsReady = await EntitlementManager.shared.beginSession(
                userID: session.user.id,
                client: client
            )
        }
        guard entitlementIsReady,
              isAccountBoundWorkLeaseCurrent(accountWorkLease),
              let verifiedSession = try? await client.auth.session,
              !verifiedSession.isExpired,
              verifiedSession.user.id == session.user.id,
              currentUser?.id == session.user.id,
              authSessionGeneration == generation,
              RevenueCatManager.shared.isIdentityReady,
              RevenueCatManager.shared.linkedAuthUserID == session.user.id else {
            return false
        }
        return true
    }

    private func cancelPurchasePrincipalLinkTask() {
        purchasePrincipalLinkTask?.cancel()
        purchasePrincipalLinkTask = nil
        purchasePrincipalLinkTaskId = nil
        purchasePrincipalLinkTaskUserId = nil
        purchasePrincipalLinkTaskGeneration = nil
        purchasePrincipalLinkTaskCapabilityFingerprint = nil
        purchasePrincipalLinkTaskAllowsCapabilityCreation = true
    }

    // MARK: - Ghost Session

    /// Creates an anonymous session for new users. Skips creation if a session exists or
    /// if the error is network/expiry — preserving any existing Apple Sign-In identity.
    @discardableResult
    func initializeGhostSession(
        ownedBy transition: AuthTransitionToken? = nil
    ) async -> User? {
        guard !TestExecutionCoordinator.isRunningTests else { return nil }
        guard !AccountDeletionLocalCleanupStore.isPending() else { return nil }

        if let signOutTask {
            await signOutTask.value
        }

        if let existingTask = ghostSessionTask {
            guard ghostSessionTaskAuthTransitionId == transition?.id
                    || transition == nil
                        && activeAuthTransition?.token.kind
                            == .anonymousBootstrap else {
                return nil
            }
            return await existingTask.value
        }

        if transition == nil,
           let currentSession = client.auth.currentSession,
           !currentSession.isExpired,
           currentUser?.id == currentSession.user.id,
           currentUser?.isAnonymous == currentSession.user.isAnonymous,
           isAuthenticated,
           let lease = try? beginUnownedAccountBoundWork(
                expectedUserID: currentSession.user.id
           ) {
            defer { finishAccountBoundWork(lease) }
            _ = await ensureTelemetryLinkedWhenSafe(for: currentSession.user)
            guard !Task.isCancelled,
                  isAccountBoundWorkLeaseCurrent(lease) else { return nil }
            return currentSession.user
        }

        let ownedTransition: AuthTransitionToken
        let finishesOwnedTransition: Bool
        if let transition {
            guard authTransitionAllows(transition) else { return nil }
            ownedTransition = transition
            finishesOwnedTransition = false
        } else {
            guard let bootstrap = beginAuthTransition(.anonymousBootstrap)
            else { return nil }
            ownedTransition = bootstrap
            finishesOwnedTransition = true
        }

        let taskId = UUID()
        let task = Task { @MainActor [weak self] () -> User? in
            guard let self else { return nil }
            defer {
                if finishesOwnedTransition {
                    self.finishAuthTransition(ownedTransition)
                }
                if self.ghostSessionTaskId == taskId {
                    self.ghostSessionTask = nil
                    self.ghostSessionTaskId = nil
                    self.ghostSessionTaskAuthTransitionId = nil
                }
            }
            let user = await self.performGhostSessionInitialization(
                ownedBy: ownedTransition
            )
            return user
        }
        ghostSessionTask = task
        ghostSessionTaskId = taskId
        ghostSessionTaskAuthTransitionId = ownedTransition.id
        return await task.value
    }

    private func performGhostSessionInitialization(
        ownedBy transition: AuthTransitionToken?
    ) async -> User? {
        guard !Task.isCancelled, authTransitionAllows(transition) else {
            return nil
        }
        if transition != nil {
            guard await awaitAccountBoundWorkQuiescenceForAuthTransition()
            else { return nil }
        }
        guard !Task.isCancelled, authTransitionAllows(transition) else {
            return nil
        }

        do {
            let session = try await client.auth.session
            guard !Task.isCancelled, authTransitionAllows(transition) else {
                return nil
            }
            if let transition {
                guard adoptAuthTransitionSession(
                    session.user,
                    for: transition
                ) else { return nil }
            }
            currentUser = session.user
            isAuthenticated = true
            MerianLog.auth.debug("Existing session resolved on device.")
            schedulePublicAuthorIdentityRefreshIfNeeded(for: session.user)
            _ = await ensureTelemetryLinkedWhenSafe(
                for: session.user,
                ownedBy: transition
            )
            return session.user
        } catch {
            let errString = String(describing: error)

            // Only create a new anonymous session if the session is genuinely missing —
            // never on network failure, to avoid overwriting a real Apple/Google identity.
            let isSessionMissing: Bool = {
                if let authError = error as? AuthError, case .sessionMissing = authError { return true }
                return errString.contains("sessionNotFound") || errString.contains("sessionMissing")
            }()

            if isSessionMissing {
                guard !Task.isCancelled, authTransitionAllows(transition) else {
                    return nil
                }
                do {
                    let authResponse = try await client.auth.signInAnonymously()
                    guard !Task.isCancelled, authTransitionAllows(transition)
                    else { return nil }
                    if let transition {
                        guard adoptAuthTransitionSession(
                            authResponse.user,
                            for: transition
                        ) else { return nil }
                    }
                    currentUser = authResponse.user
                    isAuthenticated = true
                    MerianLog.auth.debug("Signed-out session established.")
                    _ = await ensureTelemetryLinkedWhenSafe(
                        for: authResponse.user,
                        ownedBy: transition
                    )
                    return authResponse.user
                } catch {
                    MerianLog.auth.debug(
                        "Failed to establish a signed-out session; kind=\(MerianLog.errorKind(error), privacy: .public)"
                    )
                    return nil
                }
            } else {
                MerianLog.auth.debug("Skipped anonymous sign-in — preserving existing identity despite network or expiration error.")
                return nil
            }
        }
    }

    // MARK: - Session Utilities

    func signOut() async {
        guard let transition = beginAuthTransition(.recovery) else {
            if let signOutTask {
                await signOutTask.value
            }
            return
        }
        defer { finishAuthTransition(transition) }
        await performLocalSignOut(
            ownedBy: transition,
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
        guard let transition = beginAuthTransition(.recovery) else { return }
        defer { finishAuthTransition(transition) }
        await performLocalSignOut(
            ownedBy: transition,
            performRemoteSignOut: performRemoteSignOut,
            performExternalSignOut: performExternalSignOut
        )
    }

    /// Serializes backend account deletion with every other Auth mutation. The
    /// server receipt is the commit point: after acceptance, an identity-free
    /// local cleanup marker survives termination until SwiftData removal is
    /// confirmed on this launch or the next one.
    @discardableResult
    func deleteCurrentAccount(
        prepareDeletionV2: @MainActor @escaping (
            AuthTransitionToken,
            String,
            String
        ) async throws -> AccountDeletionPreparationReceipt = {
            try await MerianNetworkClient.shared
                .prepareAccountDeletionRecoveryV2(
                    recoveryCapability: $1,
                    acknowledgementCapability: $2,
                    ownedBy: $0
                )
        },
        commitDeletionV2: @MainActor @escaping (
            AuthTransitionToken,
            String
        ) async throws -> AccountDeletionReceipt = {
            try await MerianNetworkClient.shared
                .commitPreparedAccountDeletionV2(
                    recoveryCapability: $1,
                    ownedBy: $0
                )
        },
        recoverDeletionV2: @MainActor @escaping (String) async throws
            -> AccountDeletionReceipt = {
                try await MerianNetworkClient.shared
                    .recoverPreparedAccountDeletionV2(
                        recoveryCapability: $0
                    )
            },
        requestDeletion: @MainActor @escaping (
            AuthTransitionToken,
            String
        ) async throws -> AccountDeletionReceipt = {
                try await MerianNetworkClient.shared.safeDeleteAccount(
                    recoveryCapability: $1,
                    ownedBy: $0
                )
            },
        acknowledgeDeletion: @MainActor @escaping (String) async throws
            -> AccountDeletionReceipt = {
                try await MerianNetworkClient.shared
                    .recoverAcceptedAccountDeletion(
                        recoveryCapability: $0,
                        acknowledge: true
                    )
            },
        acknowledgeDeletionV2: @MainActor @escaping (String) async throws
            -> AccountDeletionReceipt = {
                try await MerianNetworkClient.shared
                    .acknowledgeAccountDeletionRecoveryV2(
                        acknowledgementCapability: $0
                    )
            },
        recoveryCapabilityStore: AccountDeletionRecoveryCapabilityStore =
            AccountDeletionRecoveryCapabilityStore(),
        recordManualProviderRevocation: @MainActor @escaping () -> Void = {
            ManualAppleRevocationNoticeStore.record()
        },
        purgeLocalData: @MainActor @escaping () -> Bool
    ) async throws -> AccountDeletionReceipt {
        guard !hasPendingPurchaseIdentityHandoffFailClosed() else {
            throw SupabaseAuthTransitionError.signOutPurchaseContinuityPending
        }
        guard !AccountDeletionLocalCleanupStore.isPending() else {
            throw SupabaseAuthTransitionError.accountDeletionRecoveryPending
        }
        guard let transition = beginAuthTransition(.accountDeletion) else {
            throw SupabaseAuthTransitionError.signOutInProgress
        }
        defer { finishAuthTransition(transition) }

        _ = updateAuthTransition(transition, phase: .deletingAccount)
        _ = try await verifiedExpectedSession(for: transition)
        try Task.checkCancellation()

        guard AccountDeletionLocalCleanupStore
            .recordCapabilityPreparationPending() else {
            throw SupabaseAuthTransitionError
                .accountDeletionRecoveryPersistenceFailed
        }
        let preparedCapability = try recoveryCapabilityStore.prepare()

        let receipt: AccountDeletionReceipt
        do {
            if preparedCapability.supportsPreparedCommit,
               let acknowledgementCapability =
                preparedCapability.acknowledgementValue {
                receipt = try await Self
                    .performPreparedAccountDeletionIntake(
                        prepareDeletion: {
                            try await prepareDeletionV2(
                                transition,
                                preparedCapability.recoveryValue,
                                acknowledgementCapability
                            )
                        },
                        verifyPreparationOwner: {
                            self.ownsAuthTransition(transition)
                        },
                        recordCapabilityPreparedPending: {
                            AccountDeletionLocalCleanupStore
                                .recordCapabilityPreparedPending()
                        },
                        recordIntakePending: {
                            AccountDeletionLocalCleanupStore
                                .recordIntakePending()
                        },
                        commitDeletion: {
                            try await commitDeletionV2(
                                transition,
                                preparedCapability.recoveryValue
                            )
                        },
                        verifyCommitOwner: {
                            self.ownsAuthTransition(transition)
                        }
                    )
            } else {
                receipt = try await Self.performDurableAccountDeletionIntake(
                    recordIntakePending: {
                        AccountDeletionLocalCleanupStore.recordIntakePending()
                    },
                    requestDeletion: {
                        try await requestDeletion(
                            transition,
                            preparedCapability.recoveryValue
                        )
                    },
                    verifyReceiptOwner: {
                        guard self.ownsAuthTransition(transition) else {
                            throw SupabaseAuthTransitionError
                                .signOutSessionChanged
                        }
                    },
                    clearIntakeAfterDefinitiveRejection: {
                        _ = Self
                            .performDefinitiveAccountDeletionIntakeRejectionRetirement(
                                recordRejectionRetirementPending: {
                                    AccountDeletionLocalCleanupStore
                                        .recordCapabilityRejectionRetirementPending()
                                },
                                retireRecoveryCapability: {
                                    do {
                                        try recoveryCapabilityStore
                                            .clearVerified()
                                        return true
                                    } catch {
                                        return false
                                    }
                                },
                                resolveCleanup: {
                                    AccountDeletionLocalCleanupStore.resolve()
                                }
                            )
                    }
                )
            }
        } catch {
            if preparedCapability.protocolVersion == 2,
               Self.isDefinitiveAccountDeletionIntakeRejection(error),
               let cancellation = try? await recoverDeletionV2(
                   preparedCapability.recoveryValue
               ), cancellation.status == .notCommitted {
                _ = Self
                    .performDefinitiveAccountDeletionIntakeRejectionRetirement(
                        recordRejectionRetirementPending: {
                            AccountDeletionLocalCleanupStore
                                .recordCapabilityRejectionRetirementPending()
                        },
                        retireRecoveryCapability: {
                            do {
                                try recoveryCapabilityStore.clearVerified()
                                return true
                            } catch {
                                return false
                            }
                        },
                        resolveCleanup: {
                            AccountDeletionLocalCleanupStore.resolve()
                        }
                    )
            }
            if preparedCapability.wasCreated,
               !AccountDeletionLocalCleanupStore.isPending() {
                try? recoveryCapabilityStore.clearVerified()
            }
            throw error
        }

        _ = updateAuthTransition(transition, phase: .finalizing)
        let didPurge = await Self.performAcceptedAccountDeletionCleanup(
            receipt: receipt,
            recordCleanupPending: {
                AccountDeletionLocalCleanupStore.recordCleanupPending()
            },
            recordManualProviderRevocation: recordManualProviderRevocation,
            performLocalSignOut: {
                await self.performVerifiedLocalSignOut(ownedBy: transition)
            },
            purgeLocalData: purgeLocalData,
            acknowledgeRecovery: {
                do {
                    let acknowledgement: AccountDeletionReceipt
                    if preparedCapability.protocolVersion == 2,
                       let acknowledgementCapability =
                        preparedCapability.acknowledgementValue {
                        acknowledgement = try await acknowledgeDeletionV2(
                            acknowledgementCapability
                        )
                    } else {
                        acknowledgement = try await acknowledgeDeletion(
                            preparedCapability.recoveryValue
                        )
                    }
                    return acknowledgement.recoveryAcknowledged == true
                } catch {
                    MerianLog.auth.error(
                        "Account deletion cleanup acknowledgement remains pending; kind=\(MerianLog.errorKind(error), privacy: .public)."
                    )
                    return false
                }
            },
            recordRecoveryRetirementPending: {
                AccountDeletionLocalCleanupStore
                    .recordCapabilityRetirementPending()
            },
            retireRecoveryCapability: {
                do {
                    try recoveryCapabilityStore.clearVerified()
                    return true
                } catch {
                    return false
                }
            },
            resolveCleanup: {
                AccountDeletionLocalCleanupStore.resolve()
            }
        )
        if !didPurge {
            MerianLog.auth.error(
                "Account deletion was accepted, but local cleanup remains pending."
            )
        }
        return receipt
    }

    nonisolated static func canRestoreDeferredDeletionBarrierSession(
        markerIsPending: Bool,
        sourceSession: AuthTransitionSession?,
        cachedUserID: UUID?,
        cachedUserIsAnonymous: Bool,
        cachedSessionIsExpired: Bool
    ) -> Bool {
        guard markerIsPending,
              !cachedSessionIsExpired,
              let sourceSession,
              let cachedUserID else {
            return false
        }
        return sourceSession.userID == cachedUserID
            && sourceSession.isAnonymous == cachedUserIsAnonymous
    }

    /// The transition coordinator must adopt the exact cached source before
    /// the durable deletion barrier is removed. Observable account state is
    /// published only after marker removal is read back successfully. Because
    /// every closure is synchronous on MainActor, ordinary account work cannot
    /// enter between these steps.
    static func performDeferredDeletionBarrierSessionRestoration(
        markerIsPending: @MainActor () -> Bool,
        adoptCachedSession: @MainActor () -> Bool,
        resolveCleanup: @MainActor () -> Bool,
        publishCachedSession: @MainActor () -> Bool
    ) -> Bool {
        guard markerIsPending(),
              adoptCachedSession(),
              resolveCleanup(),
              !markerIsPending() else {
            return false
        }
        return publishCachedSession()
    }

    /// An account-deletion barrier intentionally suppresses SDK Auth events.
    /// When recovery proves that no destructive commit won, adopt the exact
    /// cached source session while the cleanup transition still owns Auth. Do
    /// not bootstrap a replacement identity when that source is unavailable.
    private func restoreDeferredCachedSessionAndResolveDeletionBarrier(
        ownedBy transition: AuthTransitionToken
    ) async -> Bool {
        guard ownsAuthTransition(transition),
              AccountDeletionLocalCleanupStore.isPending(),
              let sourceSession = activeAuthTransition?.sourceSession else {
            return false
        }

        let session: Session
        do {
            session = try await client.auth.session
        } catch {
            return false
        }
        guard Self.canRestoreDeferredDeletionBarrierSession(
            markerIsPending: AccountDeletionLocalCleanupStore.isPending(),
            sourceSession: sourceSession,
            cachedUserID: session.user.id,
            cachedUserIsAnonymous: session.user.isAnonymous,
            cachedSessionIsExpired: session.isExpired
        ), ownsAuthTransition(transition),
           client.auth.currentSession?.user.id == session.user.id,
           client.auth.currentSession?.user.isAnonymous ==
            session.user.isAnonymous else {
            return false
        }

        let didRestore = Self
            .performDeferredDeletionBarrierSessionRestoration(
                markerIsPending: {
                    AccountDeletionLocalCleanupStore.isPending()
                },
                adoptCachedSession: {
                    guard self.ownsAuthTransition(transition),
                          self.client.auth.currentSession?.user.id ==
                            session.user.id,
                          self.client.auth.currentSession?.user.isAnonymous ==
                            session.user.isAnonymous else {
                        return false
                    }
                    return self.adoptAuthTransitionSession(
                        session.user,
                        for: transition
                    )
                },
                resolveCleanup: {
                    AccountDeletionLocalCleanupStore.resolve()
                },
                publishCachedSession: {
                    guard self.ownsAuthTransition(transition),
                          self.client.auth.currentSession?.user.id ==
                            session.user.id,
                          self.client.auth.currentSession?.user.isAnonymous ==
                            session.user.isAnonymous,
                          self.currentSessionMatchesAuthTransition(transition)
                    else {
                        return false
                    }
                    if self.currentUser?.id != session.user.id {
                        self.activePurchasePrincipalBinding = nil
                        self.lastLinkedUserId = nil
                    }
                    self.currentUser = session.user
                    self.isAuthenticated = true
                    ConsentManager.shared.observeSession(
                        userId: session.user.id
                    )
                    self.schedulePublicAuthorIdentityRefreshIfNeeded(
                        for: session.user
                    )
                    return true
                }
            )
        guard didRestore else {
            return false
        }

        if !TestExecutionCoordinator.isRunningTests {
            _ = await ensureTelemetryLinkedWhenSafe(
                for: session.user,
                ownedBy: transition
            )
        }
        guard ownsAuthTransition(transition),
              currentSessionMatchesAuthTransition(transition),
              currentUser?.id == session.user.id else {
            return false
        }
        await EntitlementManager.shared.beginSession(
            userID: session.user.id,
            client: client
        )
        return ownsAuthTransition(transition)
            && currentSessionMatchesAuthTransition(transition)
            && currentUser?.id == session.user.id
            && isAuthenticated
    }

    /// Resumes the local half of a server-accepted deletion before any cached
    /// session can be restored. The global marker is intentionally a barrier:
    /// no new account may sign in until both local auth cleanup and data purge
    /// complete, so a later account's cache can never be erased by this retry.
    @discardableResult
    func resumePendingAccountDeletionLocalCleanup(
        requestDeletion: @MainActor @escaping (
            AuthTransitionToken,
            String
        ) async throws -> AccountDeletionReceipt = {
                try await MerianNetworkClient.shared.safeDeleteAccount(
                    recoveryCapability: $1,
                    ownedBy: $0
                )
            },
        recoverDeletion: @MainActor @escaping (
            String,
            Bool
        ) async throws -> AccountDeletionReceipt = {
            try await MerianNetworkClient.shared
                .recoverAcceptedAccountDeletion(
                    recoveryCapability: $0,
                    acknowledge: $1
                )
        },
        recoverDeletionV2: @MainActor @escaping (String) async throws
            -> AccountDeletionReceipt = {
                try await MerianNetworkClient.shared
                    .recoverPreparedAccountDeletionV2(
                        recoveryCapability: $0
                    )
            },
        acknowledgeDeletionV2: @MainActor @escaping (String) async throws
            -> AccountDeletionReceipt = {
                try await MerianNetworkClient.shared
                    .acknowledgeAccountDeletionRecoveryV2(
                        acknowledgementCapability: $0
                    )
            },
        recoveryCapabilityStore: AccountDeletionRecoveryCapabilityStore =
            AccountDeletionRecoveryCapabilityStore(),
        recordManualProviderRevocation: @MainActor @escaping () -> Void = {
            ManualAppleRevocationNoticeStore.record()
        },
        purgeLocalData: @MainActor @escaping () -> Bool
    ) async -> Bool {
        guard let recoveryState = AccountDeletionLocalCleanupStore.state()
        else { return true }
        let transitionKind: AuthTransitionKind = recoveryState.isIntakePending
            ? .accountDeletion
            : .accountDeletionCleanup
        guard let transition = beginAuthTransition(transitionKind) else {
            return false
        }
        defer { finishAuthTransition(transition) }

        if recoveryState == .capabilityRejectionRetirementPending {
            let didRetireProof = Self
                .performRejectedAccountDeletionRecoveryProofRetirement(
                retireRecoveryCapability: {
                    do {
                        try recoveryCapabilityStore.clearVerified()
                        return true
                    } catch {
                        return false
                    }
                }
            )
            guard didRetireProof else { return false }
            return await restoreDeferredCachedSessionAndResolveDeletionBarrier(
                ownedBy: transition
            )
        }

        if recoveryState == .capabilityRetirementPending {
            return await Self.performAccountDeletionRecoveryRetirement(
                performLocalSignOut: {
                    await self.performVerifiedLocalSignOut(
                        ownedBy: transition
                    )
                },
                purgeLocalData: purgeLocalData,
                retireRecoveryCapability: {
                    do {
                        try recoveryCapabilityStore.clearVerified()
                        return true
                    } catch {
                        return false
                    }
                },
                resolveCleanup: {
                    AccountDeletionLocalCleanupStore.resolve()
                }
            )
        }

        let storedCapability: PreparedDeletionRecoveryCapability?
        do {
            storedCapability = try recoveryCapabilityStore
                .loadExistingIfPresent()
        } catch {
            return false
        }
        if let storedCapability,
           storedCapability.protocolVersion == 2 {
            return await resumeCapabilityBackedAccountDeletionV2(
                transition: transition,
                capability: storedCapability,
                recoverDeletion: recoverDeletionV2,
                acknowledgeDeletion: acknowledgeDeletionV2,
                recoveryCapabilityStore: recoveryCapabilityStore,
                recordManualProviderRevocation:
                    recordManualProviderRevocation,
                purgeLocalData: purgeLocalData
            )
        }
        if storedCapability == nil,
           recoveryState == .capabilityLookupPending ||
            recoveryState == .capabilityPreparationPending {
            return await restoreDeferredCachedSessionAndResolveDeletionBarrier(
                ownedBy: transition
            )
        }

        if recoveryState == .capabilityLookupPending {
            let capability: String?
            do {
                capability = try recoveryCapabilityStore
                    .loadExistingValueIfPresent()
            } catch {
                return false
            }
            guard capability != nil else {
                return await restoreDeferredCachedSessionAndResolveDeletionBarrier(
                    ownedBy: transition
                )
            }
            return await resumeCapabilityBackedAccountDeletion(
                transition: transition,
                requestDeletion: requestDeletion,
                recoverDeletion: recoverDeletion,
                recoveryCapabilityStore: recoveryCapabilityStore,
                recordManualProviderRevocation:
                    recordManualProviderRevocation,
                purgeLocalData: purgeLocalData,
                allowAuthenticatedIntakeReplay: false
            )
        }

        if recoveryState.isIntakePending {
            if !recoveryState.requiresRecoveryCapability {
                // Upgrade a pre-capability intake only while its exact cached
                // Auth session is still available. If Auth is already gone,
                // no new proof can be bound retroactively and recovery remains
                // fail-closed for support rather than guessing acceptance.
                guard client.auth.currentSession != nil else { return false }
                do {
                    _ = try recoveryCapabilityStore.prepare()
                    guard AccountDeletionLocalCleanupStore
                        .recordIntakePending() else {
                        return false
                    }
                } catch {
                    return false
                }
            }
            return await resumeCapabilityBackedAccountDeletion(
                transition: transition,
                requestDeletion: requestDeletion,
                recoverDeletion: recoverDeletion,
                recoveryCapabilityStore: recoveryCapabilityStore,
                recordManualProviderRevocation:
                    recordManualProviderRevocation,
                purgeLocalData: purgeLocalData,
                allowAuthenticatedIntakeReplay: true
            )
        }

        if recoveryState.requiresRecoveryCapability {
            return await resumeCapabilityBackedAccountDeletion(
                transition: transition,
                requestDeletion: requestDeletion,
                recoverDeletion: recoverDeletion,
                recoveryCapabilityStore: recoveryCapabilityStore,
                recordManualProviderRevocation:
                    recordManualProviderRevocation,
                purgeLocalData: purgeLocalData,
                allowAuthenticatedIntakeReplay: false
            )
        }

        return await Self.performPendingAccountDeletionLocalCleanup(
            performLocalSignOut: {
                await self.performVerifiedLocalSignOut(ownedBy: transition)
            },
            purgeLocalData: purgeLocalData,
            resolveCleanup: {
                AccountDeletionLocalCleanupStore.resolve()
            }
        )
    }

    private func resumeCapabilityBackedAccountDeletionV2(
        transition: AuthTransitionToken,
        capability: PreparedDeletionRecoveryCapability,
        recoverDeletion: @MainActor (String) async throws
            -> AccountDeletionReceipt,
        acknowledgeDeletion: @MainActor (String) async throws
            -> AccountDeletionReceipt,
        recoveryCapabilityStore: AccountDeletionRecoveryCapabilityStore,
        recordManualProviderRevocation: @MainActor () -> Void,
        purgeLocalData: @MainActor () -> Bool
    ) async -> Bool {
        guard capability.protocolVersion == 2,
              let acknowledgementCapability =
                capability.acknowledgementValue else {
            return false
        }

        _ = updateAuthTransition(transition, phase: .deletingAccount)
        let receipt: AccountDeletionReceipt
        do {
            receipt = try await recoverDeletion(
                capability.recoveryValue
            )
            guard ownsAuthTransition(transition),
                  receipt.protocolVersion == 2 else {
                return false
            }
        } catch {
            if Self.isUnknownAccountDeletionRecovery(error) {
                // A v2 destructive commit cannot run until its durable
                // preparation exists. Unknown proof therefore proves there is
                // no committed deletion receipt and authorizes proof-only
                // retirement after a missing or never-completed preparation.
                let didRetireProof = Self
                    .performDefinitiveAccountDeletionIntakeRejectionProofRetirement(
                        recordRejectionRetirementPending: {
                            AccountDeletionLocalCleanupStore
                                .recordCapabilityRejectionRetirementPending()
                        },
                        retireRecoveryCapability: {
                            do {
                                try recoveryCapabilityStore.clearVerified()
                                return true
                            } catch {
                                return false
                            }
                        }
                    )
                guard didRetireProof else { return false }
                return await restoreDeferredCachedSessionAndResolveDeletionBarrier(
                    ownedBy: transition
                )
            }
            if Self.isAcceptedExpiredAccountDeletionRecovery(error) {
                receipt = AccountDeletionReceipt(
                    success: true,
                    status: .pending,
                    manualProviderRevocationRequired: true,
                    protocolVersion: 2
                )
            } else {
                return false
            }
        }

        if receipt.status == .notCommitted {
            let didRetireProof = Self
                .performDefinitiveAccountDeletionIntakeRejectionProofRetirement(
                    recordRejectionRetirementPending: {
                        AccountDeletionLocalCleanupStore
                            .recordCapabilityRejectionRetirementPending()
                    },
                    retireRecoveryCapability: {
                        do {
                            try recoveryCapabilityStore.clearVerified()
                            return true
                        } catch {
                            return false
                        }
                    }
                )
            guard didRetireProof else { return false }
            return await restoreDeferredCachedSessionAndResolveDeletionBarrier(
                ownedBy: transition
            )
        }
        guard receipt.status == .pending || receipt.status == .completed else {
            return false
        }

        _ = updateAuthTransition(transition, phase: .finalizing)
        return await Self.performAcceptedAccountDeletionCleanup(
            receipt: receipt,
            recordCleanupPending: {
                AccountDeletionLocalCleanupStore.recordCleanupPending()
            },
            recordManualProviderRevocation: recordManualProviderRevocation,
            performLocalSignOut: {
                await self.performVerifiedLocalSignOut(ownedBy: transition)
            },
            purgeLocalData: purgeLocalData,
            acknowledgeRecovery: {
                do {
                    let acknowledgement = try await acknowledgeDeletion(
                        acknowledgementCapability
                    )
                    return acknowledgement.recoveryAcknowledged == true
                } catch {
                    return false
                }
            },
            recordRecoveryRetirementPending: {
                AccountDeletionLocalCleanupStore
                    .recordCapabilityRetirementPending()
            },
            retireRecoveryCapability: {
                do {
                    try recoveryCapabilityStore.clearVerified()
                    return true
                } catch {
                    return false
                }
            },
            resolveCleanup: {
                AccountDeletionLocalCleanupStore.resolve()
            }
        )
    }

    private func resumeCapabilityBackedAccountDeletion(
        transition: AuthTransitionToken,
        requestDeletion: @MainActor (
            AuthTransitionToken,
            String
        ) async throws -> AccountDeletionReceipt,
        recoverDeletion: @MainActor (
            String,
            Bool
        ) async throws -> AccountDeletionReceipt,
        recoveryCapabilityStore: AccountDeletionRecoveryCapabilityStore,
        recordManualProviderRevocation: @MainActor () -> Void,
        purgeLocalData: @MainActor () -> Bool,
        allowAuthenticatedIntakeReplay: Bool
    ) async -> Bool {
        let capability: String
        do {
            capability = try recoveryCapabilityStore.loadExistingValue()
        } catch {
            MerianLog.auth.error(
                "Account deletion recovery proof is unavailable; cleanup remains pending."
            )
            return false
        }

        _ = updateAuthTransition(transition, phase: .deletingAccount)
        let receipt: AccountDeletionReceipt
        do {
            if allowAuthenticatedIntakeReplay,
               AccountDeletionLocalCleanupStore.state()?.isIntakePending == true,
               client.auth.currentSession != nil {
                do {
                    _ = try await verifiedExpectedSession(for: transition)
                    receipt = try await requestDeletion(
                        transition,
                        capability
                    )
                } catch {
                    if Self.isDefinitiveAccountDeletionIntakeRejection(error) {
                        let didRetireProof = Self
                            .performDefinitiveAccountDeletionIntakeRejectionProofRetirement(
                                recordRejectionRetirementPending: {
                                    AccountDeletionLocalCleanupStore
                                        .recordCapabilityRejectionRetirementPending()
                                },
                                retireRecoveryCapability: {
                                    do {
                                        try recoveryCapabilityStore
                                            .clearVerified()
                                        return true
                                    } catch {
                                        return false
                                    }
                                }
                            )
                        guard didRetireProof else { return false }
                        return await restoreDeferredCachedSessionAndResolveDeletionBarrier(
                            ownedBy: transition
                        )
                    }
                    receipt = try await recoverDeletion(capability, false)
                }
            } else {
                receipt = try await recoverDeletion(capability, false)
            }
            guard ownsAuthTransition(transition) else {
                return false
            }
        } catch {
            let code = MerianNetworkClient.stableEdgeErrorCode(from: error)
            if Self.isAcceptedExpiredAccountDeletionRecovery(error) {
                // The server emits this code only after the hash matched a
                // durable deletion job. The expired proof cannot inspect the
                // job, but that positive match is sufficient to
                // finish local erasure. The post-cleanup acknowledge operation
                // remains valid and converts it to a permanent receipt.
                receipt = AccountDeletionReceipt(
                    success: true,
                    status: .pending,
                    manualProviderRevocationRequired: true
                )
            } else {
                // `account_deletion_recovery_invalid` is not a cancellation
                // receipt. Authenticated intake may still be committing after
                // an ambiguous transport failure, so retain both proof and
                // local barrier for a later retry or operator recovery.
                MerianLog.auth.error(
                    "Account deletion capability recovery remains pending; code=\((code ?? "unavailable"), privacy: .public)."
                )
                return false
            }
        }

        _ = updateAuthTransition(transition, phase: .finalizing)
        return await Self.performAcceptedAccountDeletionCleanup(
            receipt: receipt,
            recordCleanupPending: {
                AccountDeletionLocalCleanupStore.recordCleanupPending()
            },
            recordManualProviderRevocation: recordManualProviderRevocation,
            performLocalSignOut: {
                await self.performVerifiedLocalSignOut(ownedBy: transition)
            },
            purgeLocalData: purgeLocalData,
            acknowledgeRecovery: {
                do {
                    let acknowledgement = try await recoverDeletion(
                        capability,
                        true
                    )
                    return acknowledgement.recoveryAcknowledged == true
                } catch {
                    return false
                }
            },
            recordRecoveryRetirementPending: {
                AccountDeletionLocalCleanupStore
                    .recordCapabilityRetirementPending()
            },
            retireRecoveryCapability: {
                do {
                    try recoveryCapabilityStore.clearVerified()
                    return true
                } catch {
                    return false
                }
            },
            resolveCleanup: {
                AccountDeletionLocalCleanupStore.resolve()
            }
        )
    }

    /// Persists an identity-free intent before the first network suspension.
    /// A lost response therefore replays the server's idempotent intake instead
    /// of restoring the cached account. Only the received, definitive
    /// `409 purchase_continuity_pending` response may retire the intent without
    /// a server receipt; every ambiguous outcome stays fenced for foreground or
    /// cold-launch recovery.
    static func performDurableAccountDeletionIntake(
        recordIntakePending: @MainActor () -> Bool,
        requestDeletion: @MainActor () async throws -> AccountDeletionReceipt,
        verifyReceiptOwner: @MainActor () throws -> Void,
        clearIntakeAfterDefinitiveRejection: @MainActor () -> Void
    ) async throws -> AccountDeletionReceipt {
        guard recordIntakePending() else {
            throw SupabaseAuthTransitionError
                .accountDeletionRecoveryPersistenceFailed
        }
        do {
            let receipt = try await requestDeletion()
            try verifyReceiptOwner()
            return receipt
        } catch {
            if isDefinitiveAccountDeletionIntakeRejection(error) {
                clearIntakeAfterDefinitiveRejection()
            }
            throw error
        }
    }

    /// Promotes a non-destructive protocol-v2 preparation into destructive
    /// intake only after both recovery markers are durably persisted.
    static func performPreparedAccountDeletionIntake(
        prepareDeletion: @MainActor () async throws
            -> AccountDeletionPreparationReceipt,
        verifyPreparationOwner: @MainActor () -> Bool,
        recordCapabilityPreparedPending: @MainActor () -> Bool,
        recordIntakePending: @MainActor () -> Bool,
        commitDeletion: @MainActor () async throws
            -> AccountDeletionReceipt,
        verifyCommitOwner: @MainActor () -> Bool
    ) async throws -> AccountDeletionReceipt {
        let preparation = try await prepareDeletion()
        guard verifyPreparationOwner(),
              preparation.status == .prepared,
              preparation.protocolVersion == 2,
              recordCapabilityPreparedPending(),
              recordIntakePending() else {
            throw SupabaseAuthTransitionError
                .accountDeletionRecoveryPersistenceFailed
        }

        let receipt = try await commitDeletion()
        guard verifyCommitOwner(),
              receipt.protocolVersion == 2,
              receipt.status == .pending || receipt.status == .completed else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        return receipt
    }

    static func isDefinitiveAccountDeletionIntakeRejection(
        _ error: Error
    ) -> Bool {
        guard case let MerianError.httpError(statusCode, _) = error,
              statusCode == 409 else {
            return false
        }
        // This is the only public safe-delete rejection emitted after the
        // authenticated handler has proved that durable intake did not win.
        // Auth/gateway 4xx responses cannot exclude an earlier lost-response
        // commit and therefore remain fenced for recovery.
        return MerianNetworkClient.stableEdgeErrorCode(from: error)
            == "purchase_continuity_pending"
    }

    static func isAcceptedExpiredAccountDeletionRecovery(
        _ error: Error
    ) -> Bool {
        guard case let MerianError.httpError(statusCode, _) = error,
              statusCode == 410 else {
            return false
        }
        return MerianNetworkClient.stableEdgeErrorCode(from: error)
            == "account_deletion_recovery_expired"
    }

    static func isUnknownAccountDeletionRecovery(
        _ error: Error
    ) -> Bool {
        guard case let MerianError.httpError(statusCode, _) = error,
              statusCode == 404 else {
            return false
        }
        return MerianNetworkClient.stableEdgeErrorCode(from: error)
            == "account_deletion_recovery_invalid"
    }

    /// Once the server accepts deletion, record recovery state before the next
    /// suspension. A terminated task can then finish local erasure on launch.
    static func performAcceptedAccountDeletionCleanup(
        receipt: AccountDeletionReceipt,
        recordCleanupPending: @MainActor () -> Bool,
        recordManualProviderRevocation: @MainActor () -> Void,
        performLocalSignOut: @MainActor () async -> Bool,
        purgeLocalData: @MainActor () -> Bool,
        acknowledgeRecovery: @MainActor () async -> Bool = { true },
        recordRecoveryRetirementPending: @MainActor () -> Bool = { true },
        retireRecoveryCapability: @MainActor () -> Bool = { true },
        resolveCleanup: @MainActor () -> Bool
    ) async -> Bool {
        guard recordCleanupPending() else { return false }
        if receipt.manualProviderRevocationRequired {
            recordManualProviderRevocation()
        }
        guard await performLocalSignOut() else { return false }
        guard purgeLocalData() else { return false }
        guard await acknowledgeRecovery() else { return false }
        guard recordRecoveryRetirementPending() else { return false }
        guard retireRecoveryCapability() else { return false }
        return resolveCleanup()
    }

    static func performAccountDeletionRecoveryRetirement(
        performLocalSignOut: @MainActor () async -> Bool = { true },
        purgeLocalData: @MainActor () -> Bool = { true },
        retireRecoveryCapability: @MainActor () -> Bool,
        resolveCleanup: @MainActor () -> Bool
    ) async -> Bool {
        guard await performLocalSignOut() else { return false }
        guard purgeLocalData() else { return false }
        guard retireRecoveryCapability() else { return false }
        return resolveCleanup()
    }

    /// A definitive pre-commit rejection authorizes retirement of the unused
    /// proof only. Keeping this separate from accepted-deletion retirement is
    /// what prevents a crash from turning a rejected request into local data
    /// erasure on the next launch.
    static func performRejectedAccountDeletionRecoveryProofRetirement(
        retireRecoveryCapability: @MainActor () -> Bool
    ) -> Bool {
        retireRecoveryCapability()
    }

    static func performRejectedAccountDeletionRecoveryRetirement(
        retireRecoveryCapability: @MainActor () -> Bool,
        resolveCleanup: @MainActor () -> Bool
    ) -> Bool {
        guard performRejectedAccountDeletionRecoveryProofRetirement(
            retireRecoveryCapability: retireRecoveryCapability
        ) else { return false }
        return resolveCleanup()
    }

    /// A definitive intake rejection can retire the unused recovery proof, but
    /// the retirement phase must reach durable storage first. If the process is
    /// terminated after proof deletion and before marker removal, launch can
    /// then finish the proof-only cleanup instead of treating the absent proof
    /// as an ambiguous accepted deletion.
    static func performDefinitiveAccountDeletionIntakeRejectionProofRetirement(
        recordRejectionRetirementPending: @MainActor () -> Bool,
        retireRecoveryCapability: @MainActor () -> Bool
    ) -> Bool {
        guard recordRejectionRetirementPending() else { return false }
        return performRejectedAccountDeletionRecoveryProofRetirement(
            retireRecoveryCapability: retireRecoveryCapability
        )
    }

    static func performDefinitiveAccountDeletionIntakeRejectionRetirement(
        recordRejectionRetirementPending: @MainActor () -> Bool,
        retireRecoveryCapability: @MainActor () -> Bool,
        resolveCleanup: @MainActor () -> Bool
    ) -> Bool {
        guard performDefinitiveAccountDeletionIntakeRejectionProofRetirement(
            recordRejectionRetirementPending:
                recordRejectionRetirementPending,
            retireRecoveryCapability: retireRecoveryCapability
        ) else { return false }
        return resolveCleanup()
    }

    static func performPendingAccountDeletionLocalCleanup(
        performLocalSignOut: @MainActor () async -> Bool,
        purgeLocalData: @MainActor () -> Bool,
        resolveCleanup: @MainActor () -> Bool
    ) async -> Bool {
        guard await performLocalSignOut() else { return false }
        guard purgeLocalData() else { return false }
        return resolveCleanup()
    }

    private func performLocalSignOut(
        ownedBy transition: AuthTransitionToken
    ) async {
        await performLocalSignOut(
            ownedBy: transition,
            performRemoteSignOut: { [client] in
                try await client.auth.signOut(scope: .local)
            },
            performExternalSignOut: {
                await RevenueCatManager.shared.handleSupabaseSignOut()
            }
        )
    }

    /// Account deletion may retire its recovery marker only after the SDK has
    /// actually discarded the cached session. The ordinary sign-out helper is
    /// intentionally best-effort for recoverable flows, so deletion adds this
    /// exact postcondition and keeps the marker on any uncertainty.
    private func performVerifiedLocalSignOut(
        ownedBy transition: AuthTransitionToken
    ) async -> Bool {
        await performLocalSignOut(ownedBy: transition)
        guard ownsAuthTransition(transition),
              client.auth.currentSession == nil,
              currentUser == nil,
              !isAuthenticated else {
            MerianLog.auth.error(
                "Local authentication cleanup could not be verified; account deletion recovery remains pending."
            )
            return false
        }
        return true
    }

    private func performLocalSignOut(
        ownedBy transition: AuthTransitionToken,
        performRemoteSignOut: @MainActor @escaping () async throws -> Void,
        performExternalSignOut: @MainActor @escaping () async -> Void
    ) async {
        guard ownsAuthTransition(transition) else { return }
        guard await awaitAccountBoundWorkQuiescenceForAuthTransition()
        else { return }
        guard ownsAuthTransition(transition) else { return }
        if let signOutTask {
            await signOutTask.value
            return
        }

        let cancelledGhostSessionTask = beginLocalSignOutTransition()
        _ = updateAuthTransition(transition, phase: .installingSession)
        _ = adoptAuthTransitionSession(nil, for: transition)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.isSigningOut = false
                self.signOutTask = nil
            }

            if let cancelledGhostSessionTask {
                _ = await cancelledGhostSessionTask.value
            }
            guard self.ownsAuthTransition(transition) else { return }

            do {
                try await performRemoteSignOut()
            } catch {
                MerianLog.auth.debug(
                    "Supabase sign-out failed; continuing local cleanup; kind=\(MerianLog.errorKind(error), privacy: .public)"
                )
            }

            await performExternalSignOut()
            MerianLog.auth.debug("User signed out.")
        }
        signOutTask = task
        await task.value
    }

    /// Replaces the active account with a fresh anonymous identity. Linked
    /// accounts first persist a one-use purchase-continuity proof; the proof is
    /// removed only after RevenueCat and the server verify the new identity.
    @discardableResult
    func transitionToGhostSession() async -> Bool {
        await userSignOutSingleFlight.run { [weak self] in
            guard let self,
                  let transition = self.beginAuthTransition(.signOut) else {
                return false
            }
            defer {
                self.finishAuthTransition(transition)
            }
            return await self.performTransitionToGhostSession(
                ownedBy: transition
            )
        }
    }

    private func performTransitionToGhostSession(
        ownedBy transition: AuthTransitionToken
    ) async -> Bool {
        guard ownsAuthTransition(transition) else { return false }
        guard await awaitAccountBoundWorkQuiescenceForAuthTransition()
        else { return false }
        guard ownsAuthTransition(transition) else { return false }

        let pendingHandoff: PendingSignOutPurchaseHandoff?
        let pendingPrincipalRotation: PendingPurchasePrincipalAuthRotation?
        do {
            pendingHandoff = try loadPendingSignOutPurchaseHandoff()
            pendingPrincipalRotation = try loadPendingPurchasePrincipalAuthRotation()
        } catch {
            RevenueCatManager.shared.setPurchaseIdentityHandoffPending(true)
            MerianLog.auth.error(
                "Refused sign-out because the purchase handoff proof is unreadable."
            )
            return false
        }

        let startingUser: User?
        do {
            let session = try await client.auth.session
            startingUser = session.user
        } catch {
            // A known linked identity must never be closed without first
            // securing its authoritative RevenueCat snapshot.
            if currentUser?.isAnonymous == false
                || KeychainManager.shared.bool(
                    forKey: KeychainKeys.hasAuthenticatedOAuth
                ) {
                MerianLog.auth.debug(
                    "Refused sign-out because the linked session could not be verified."
                )
                return false
            }
            startingUser = currentUser
        }

        if let pendingPrincipalRotation {
            RevenueCatManager.shared.setPurchaseIdentityHandoffPending(true)
            if let startingUser, startingUser.isAnonymous {
                return await completePendingSignOutPurchaseHandoffIfNeeded(
                    expectedDestinationUserId: startingUser.id.uuidString,
                    ownedBy: transition
                )
            }
            if startingUser == nil {
                guard let destination = await initializeGhostSession(
                    ownedBy: transition
                ),
                      destination.isAnonymous else {
                    return false
                }
                return await completePendingSignOutPurchaseHandoffIfNeeded(
                    expectedDestinationUserId: destination.id.uuidString,
                    ownedBy: transition
                )
            }
            guard startingUser?.id.uuidString.lowercased()
                    == pendingPrincipalRotation.sourceUserId.lowercased() else {
                MerianLog.auth.error(
                    "Refused to replace an unrelated account while stable purchase identity rotation is pending."
                )
                return false
            }
            guard let startingUser else { return false }
            await abandonPendingPurchasePrincipalRotationIfSourceRestored(
                sourceUserId: startingUser.id,
                ownedBy: transition
            )
            do {
                guard try loadPendingPurchasePrincipalAuthRotation() == nil else {
                    return false
                }
                RevenueCatManager.shared.setPurchaseIdentityHandoffPending(
                    pendingHandoff != nil
                )
            } catch {
                return false
            }
        }

        if let pendingHandoff {
            RevenueCatManager.shared.setPurchaseIdentityHandoffPending(true)
            if let startingUser, startingUser.isAnonymous {
                return await completePendingSignOutPurchaseHandoffIfNeeded(
                    expectedDestinationUserId: startingUser.id.uuidString,
                    ownedBy: transition
                )
            }
            if startingUser == nil {
                guard let destination = await initializeGhostSession(
                    ownedBy: transition
                ),
                      destination.isAnonymous else {
                    return false
                }
                return await completePendingSignOutPurchaseHandoffIfNeeded(
                    expectedDestinationUserId: destination.id.uuidString,
                    ownedBy: transition
                )
            }
            guard startingUser?.id.uuidString.lowercased()
                    == pendingHandoff.sourceUserId.lowercased() else {
                MerianLog.auth.error(
                    "Refused to replace an unrelated account while purchase continuity is pending."
                )
                return false
            }
            await abandonPendingSignOutPurchaseHandoffIfSourceRestored(
                sourceUserId: pendingHandoff.sourceUserId,
                ownedBy: transition
            )
            do {
                guard try loadPendingSignOutPurchaseHandoff() == nil else {
                    return false
                }
            } catch {
                RevenueCatManager.shared
                    .setPurchaseIdentityHandoffPending(true)
                return false
            }
        }

        guard let startingUser, !startingUser.isAnonymous else {
            return await Self.performUserSignOutTransition(
                performSignOut: { [weak self] in
                    await self?.performLocalSignOut(ownedBy: transition)
                },
                initializeAnonymousSession: { [weak self] in
                    guard let user = await self?.initializeGhostSession(
                        ownedBy: transition
                    ) else {
                        return false
                    }
                    return user.isAnonymous
                }
            )
        }

        let sourceAuthGeneration = authSessionGeneration
        guard currentUser?.id == startingUser.id,
              !startingUser.isAnonymous else {
            return false
        }
        _ = await ensureTelemetryLinkedWhenSafe(
            for: startingUser,
            ownedBy: transition
        )
        guard currentUser?.id == startingUser.id,
              authSessionGeneration == sourceAuthGeneration,
              let verifiedSourceSession = try? await client.auth.session,
              verifiedSourceSession.user.id == startingUser.id,
              !verifiedSourceSession.user.isAnonymous,
              let binding = activePurchasePrincipalBinding else {
            return false
        }
        switch binding.mode {
        case .stable:
            guard RevenueCatManager.shared.isIdentityReady,
                  RevenueCatManager.shared.linkedAuthUserID == startingUser.id else {
                // Stable mode is already server-authoritative. Preserve the
                // linked Auth session and retry resolution/linking instead of
                // entering the incompatible legacy receipt-transfer path.
                return false
            }
            RevenueCatManager.shared.setPurchaseIdentityHandoffPending(true)
            let completed = await Self.performPurchaseSafeSignOutTransition(
                prepareAndPersistHandoff: { [weak self] in
                    guard let self else {
                        throw SupabaseAuthTransitionError.signOutSessionChanged
                    }
                    let verified = try await self.client.auth.session
                    guard !verified.user.isAnonymous,
                          verified.user.id == startingUser.id,
                          self.currentUser?.id == startingUser.id,
                          self.authSessionGeneration == sourceAuthGeneration else {
                        throw SupabaseAuthTransitionError.signOutSessionChanged
                    }
                    try await self
                        .prepareAndPersistPendingPurchasePrincipalAuthRotation(
                        sourceUserId: startingUser.id,
                        binding: binding
                    )
                    let reverified = try await self.client.auth.session
                    guard !reverified.user.isAnonymous,
                          reverified.user.id == startingUser.id,
                          self.currentUser?.id == startingUser.id,
                          self.authSessionGeneration == sourceAuthGeneration else {
                        throw SupabaseAuthTransitionError.signOutSessionChanged
                    }
                },
                performSignOut: { [weak self] in
                    await self?.performLocalSignOut(ownedBy: transition)
                },
                initializeAnonymousSession: { [weak self] in
                    guard let user = await self?.initializeGhostSession(
                        ownedBy: transition
                    ) else {
                        return false
                    }
                    return user.isAnonymous
                },
                completeHandoff: { [weak self] in
                    guard let self,
                          await self
                            .completePendingSignOutPurchaseHandoffIfNeeded(
                                ownedBy: transition
                            )
                    else {
                        throw SupabaseAuthTransitionError
                            .signOutPurchaseContinuityPending
                    }
                }
            )
            if !completed {
                await abandonPendingPurchasePrincipalRotationIfSourceRestored(
                    sourceUserId: startingUser.id,
                    ownedBy: transition
                )
                await restoreSourceIdentityAfterFailedSignOutIfPossible(
                    sourceUserId: startingUser.id,
                    ownedBy: transition
                )
            }
            return completed
        case .legacy:
            break
        }

        let sourceUserId = startingUser.id.uuidString.lowercased()
        RevenueCatManager.shared.setPurchaseIdentityHandoffPending(true)
        let completed = await Self.performPurchaseSafeSignOutTransition(
            prepareAndPersistHandoff: { [weak self] in
                guard let self else {
                    throw SupabaseAuthTransitionError.signOutSessionChanged
                }
                try await self.prepareSignOutPurchaseHandoff(
                    sourceUserId: sourceUserId,
                    ownedBy: transition
                )
            },
            performSignOut: { [weak self] in
                await self?.performLocalSignOut(ownedBy: transition)
            },
            initializeAnonymousSession: { [weak self] in
                guard let user = await self?.initializeGhostSession(
                    ownedBy: transition
                ) else {
                    return false
                }
                return user.isAnonymous
            },
            completeHandoff: { [weak self] in
                guard let self,
                      await self.completePendingSignOutPurchaseHandoffIfNeeded(
                        ownedBy: transition
                      )
                else {
                    throw SupabaseAuthTransitionError
                        .signOutPurchaseContinuityPending
                }
            }
        )

        if !completed {
            await abandonPendingSignOutPurchaseHandoffIfSourceRestored(
                sourceUserId: sourceUserId,
                ownedBy: transition
            )
            await restoreSourceIdentityAfterFailedSignOutIfPossible(
                sourceUserId: startingUser.id,
                ownedBy: transition
            )
        }
        return completed
    }

    /// Explicit foreground retry for an anonymous session whose device-durable
    /// purchase handoff did not finish during the original sign-out.
    @discardableResult
    func retryPendingSignOutPurchaseHandoff() async -> Bool {
        guard let transition = beginAuthTransition(.recovery) else {
            return false
        }
        defer { finishAuthTransition(transition) }
        guard let session = try? await client.auth.session,
              session.user.isAnonymous,
              currentSessionMatchesAuthTransition(transition) else {
            return false
        }
        _ = updateAuthTransition(transition, phase: .bindingPurchases)
        return await completePendingSignOutPurchaseHandoffIfNeeded(
            expectedDestinationUserId: session.user.id.uuidString,
            ownedBy: transition
        )
    }

    /// Test seam for the user-facing composite transition. The lower-level
    /// sign-out and anonymous-session routines retain their own single-flight
    /// guards; this boundary proves their order and propagates readiness.
    static func performUserSignOutTransition(
        performSignOut: @MainActor () async -> Void,
        initializeAnonymousSession: @MainActor () async -> Bool
    ) async -> Bool {
        await performSignOut()
        return await initializeAnonymousSession()
    }

    /// Testable ordering contract for linked-account sign-out. Preparation is
    /// the commit point: if it fails, the original session is never closed; if
    /// any later step fails, the persisted proof is deliberately retained.
    static func performPurchaseSafeSignOutTransition(
        prepareAndPersistHandoff: @MainActor () async throws -> Void,
        performSignOut: @MainActor () async -> Void,
        initializeAnonymousSession: @MainActor () async -> Bool,
        completeHandoff: @MainActor () async throws -> Void
    ) async -> Bool {
        do {
            try await prepareAndPersistHandoff()
            await performSignOut()
            guard await initializeAnonymousSession() else { return false }
            try await completeHandoff()
            return true
        } catch {
            MerianLog.auth.debug(
                "Purchase-safe sign-out remains incomplete; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
            return false
        }
    }

    /// Exact post-sign-out ordering. The durable proof is the final mutation;
    /// every provider/server/session check must succeed before it is removed.
    static func finalizeSignOutPurchaseHandoff(
        bindDestination: @MainActor () async throws -> Void,
        verifyBoundDestinationSession: @MainActor () async throws -> Void,
        linkProviderIdentity: @MainActor () async throws -> Void,
        verifyLinkedDestinationSession: @MainActor () async throws -> Void,
        synchronizeStorePurchases: @MainActor () async throws -> Void,
        completeServerHandoff: @MainActor () async throws -> Void,
        refreshServerEntitlement: @MainActor () async throws -> Bool,
        verifyFinalDestinationSession: @MainActor () async throws -> Void,
        clearPendingHandoff: @MainActor () throws -> Void
    ) async throws {
        try await bindDestination()
        try Task.checkCancellation()
        try await verifyBoundDestinationSession()
        try Task.checkCancellation()
        try await linkProviderIdentity()
        try Task.checkCancellation()
        try await verifyLinkedDestinationSession()
        try Task.checkCancellation()
        try await synchronizeStorePurchases()
        try Task.checkCancellation()
        try await completeServerHandoff()
        try Task.checkCancellation()
        guard try await refreshServerEntitlement() else {
            throw SupabaseAuthTransitionError
                .signOutPurchaseContinuityPending
        }
        try Task.checkCancellation()
        try await verifyFinalDestinationSession()
        try Task.checkCancellation()
        try clearPendingHandoff()
    }

    @discardableResult
    private func beginLocalSignOutTransition() -> Task<User?, Never>? {
        isSigningOut = true
        authSessionGeneration &+= 1
        currentUser = nil
        isAuthenticated = false
        activePurchasePrincipalBinding = nil
        lastLinkedUserId = nil
        lastPublicAuthorIdentityRefreshUserId = nil
        RevenueCatManager.shared.beginPurchaseIdentityResolution()
        EntitlementManager.shared.handleSignOut()

        let cancelledGhostSessionTask = ghostSessionTask
        cancelledGhostSessionTask?.cancel()
        ghostSessionTask = nil
        ghostSessionTaskId = nil
        ghostSessionTaskAuthTransitionId = nil

        publicAuthorIdentityRefreshTask?.cancel()
        publicAuthorIdentityRefreshTask = nil
        cancelGhostProfileMergeTask()
        cancelPurchasePrincipalLinkTask()
        KeychainManager.shared.removeObject(forKey: KeychainKeys.hasAuthenticatedOAuth)
        KeychainManager.shared.removeObject(forKey: KeychainKeys.legacyGhostModeUserID)
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
        guard let transition = beginAuthTransition(.recovery) else {
            return false
        }
        defer { finishAuthTransition(transition) }
        return await refreshActiveSessionForRetry(ownedBy: transition)
    }

    private func refreshActiveSessionForRetry(
        ownedBy transition: AuthTransitionToken
    ) async -> Bool {
        guard ownsAuthTransition(transition), !isSigningOut else {
            return false
        }
        guard await awaitAccountBoundWorkQuiescenceForAuthTransition()
        else { return false }
        guard ownsAuthTransition(transition), !isSigningOut else {
            return false
        }

        do {
            let session = try await client.auth.refreshSession()
            guard ownsAuthTransition(transition), !isSigningOut,
                  adoptAuthTransitionSession(
                    session.user,
                    for: transition
                  ) else { return false }
            currentUser = session.user
            isAuthenticated = true
            schedulePublicAuthorIdentityRefreshIfNeeded(for: session.user)
            _ = await ensureTelemetryLinkedWhenSafe(
                for: session.user,
                ownedBy: transition
            )
            MerianLog.auth.debug("Supabase session refreshed after auth failure.")
            return true
        } catch {
            MerianLog.auth.debug(
                "Supabase session refresh after auth failure failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
            return false
        }
    }

    /// Refreshes the JWT for an authenticated request already owned by the
    /// active Auth transition. Unlike ordinary recovery, this cannot start a
    /// nested transition or relink RevenueCat/analytics/profile state. It may
    /// only renew the exact expected SDK identity and is therefore safe behind
    /// a capability-backed account-deletion intake fence.
    func refreshExpectedSessionForAuthenticatedRequest(
        ownedBy transition: AuthTransitionToken
    ) async -> Bool {
        guard ownsAuthTransition(transition),
              let expected = authTransitionCoordinator.active?.expectedSession
        else {
            return false
        }
        guard await awaitAccountBoundWorkQuiescenceForAuthTransition()
        else { return false }
        guard ownsAuthTransition(transition),
              authTransitionCoordinator.active?.expectedSession == expected
        else {
            return false
        }

        do {
            let session = try await client.auth.refreshSession()
            guard ownsAuthTransition(transition),
                  transitionSession(from: session.user) == expected,
                  adoptAuthTransitionSession(session.user, for: transition),
                  currentSessionMatchesAuthTransition(transition) else {
                return false
            }
            currentUser = session.user
            isAuthenticated = true
            MerianLog.auth.debug(
                "Refreshed the exact session owned by an authentication transition."
            )
            return true
        } catch {
            MerianLog.auth.debug(
                "Transition-owned session refresh failed; kind=\(MerianLog.errorKind(error), privacy: .public)."
            )
            return false
        }
    }

    /// Clears a broken anonymous session and creates a fresh ghost identity.
    @discardableResult
    func resetGhostSessionForRetry() async -> Bool {
        guard let transition = beginAuthTransition(.recovery) else {
            return false
        }
        defer { finishAuthTransition(transition) }
        guard !hasPendingPurchaseIdentityHandoffFailClosed() else {
            MerianLog.auth.error(
                "Refused to rotate an anonymous session while purchase continuity is pending."
            )
            return false
        }
        guard await performTransitionToGhostSession(ownedBy: transition) else {
            return false
        }

        do {
            let session = try await client.auth.session
            let generation = authSessionGeneration
            _ = await ensureTelemetryLinkedWhenSafe(
                for: session.user,
                ownedBy: transition
            )
            guard session.user.isAnonymous,
                  currentUser?.id == session.user.id,
                  authSessionGeneration == generation,
                  activePurchasePrincipalBinding != nil,
                  RevenueCatManager.shared.isIdentityReady,
                  RevenueCatManager.shared.linkedAuthUserID == session.user.id else {
                MerianLog.auth.debug(
                    "Anonymous session regenerated, but purchase identity is not ready for request replay."
                )
                return false
            }
            guard await EntitlementManager.shared.beginSession(
                userID: session.user.id,
                client: client,
                authTransitionOwner: transition
            ) else {
                throw SupabaseAuthTransitionError
                    .signOutPurchaseContinuityPending
            }
            let verifiedSession = try await client.auth.session
            guard verifiedSession.user.isAnonymous,
                  verifiedSession.user.id == session.user.id,
                  currentUser?.id == session.user.id,
                  authSessionGeneration == generation else {
                return false
            }
            currentUser = session.user
            isAuthenticated = true
            MerianLog.auth.debug("Anonymous session regenerated after auth failure.")
            return true
        } catch {
            MerianLog.auth.debug(
                "Signed-out session regeneration after auth failure failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
            return false
        }
    }

    func clearLocalSessionAfterAuthFailure() async {
        guard let transition = beginAuthTransition(.recovery) else { return }
        defer { finishAuthTransition(transition) }
        await clearLocalSessionAfterAuthFailure(ownedBy: transition)
    }

    private func clearLocalSessionAfterAuthFailure(
        ownedBy transition: AuthTransitionToken
    ) async {
        guard ownsAuthTransition(transition) else { return }
        guard await awaitAccountBoundWorkQuiescenceForAuthTransition()
        else { return }
        guard ownsAuthTransition(transition) else { return }
        guard !hasPendingPurchaseIdentityHandoffFailClosed() else {
            MerianLog.auth.error(
                "Preserved the exact local auth session because purchase continuity is pending."
            )
            return
        }

        _ = updateAuthTransition(transition, phase: .installingSession)
        _ = adoptAuthTransitionSession(nil, for: transition)
        do {
            try await client.auth.signOut(scope: .local)
        } catch {
            MerianLog.auth.debug(
                "Local Supabase sign-out after auth failure failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
        }

        currentUser = nil
        isAuthenticated = false
        lastLinkedUserId = nil
        lastPublicAuthorIdentityRefreshUserId = nil
        publicAuthorIdentityRefreshTask?.cancel()
        publicAuthorIdentityRefreshTask = nil
        cancelGhostProfileMergeTask()
        KeychainManager.shared.removeObject(forKey: KeychainKeys.hasAuthenticatedOAuth)
        KeychainManager.shared.removeObject(forKey: KeychainKeys.legacyGhostModeUserID)
        PostHogManager.shared.reset()
        await RevenueCatManager.shared.handleSupabaseSignOut()
        MerianLog.auth.debug("Cleared local Supabase session after auth failure.")
    }

    /// Builds authenticated REST headers, initializing a ghost session if no token exists.
    func getValidAuthHeaders(
        ownedBy transition: AuthTransitionToken? = nil,
        expectedUserID: UUID? = nil
    ) async throws -> [String: String] {
        guard !isSigningOut,
              Self.allowsAuthenticatedRequest(
                activeTransition: activeAuthTransition?.token,
                requestOwner: transition,
                accountDeletionCleanupPending:
                    AccountDeletionLocalCleanupStore.isPending()
              ) else {
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
                guard !hasPendingPurchaseIdentityHandoffFailClosed() else {
                    throw SupabaseAuthTransitionError
                        .signOutPurchaseContinuityPending
                }
                _ = await self.initializeGhostSession(ownedBy: transition)
                token = try await self.getActiveJWT()
            } else {
                throw error
            }
        }

        guard !isSigningOut,
              Self.allowsAuthenticatedRequest(
                activeTransition: activeAuthTransition?.token,
                requestOwner: transition,
                accountDeletionCleanupPending:
                    AccountDeletionLocalCleanupStore.isPending()
              ) else {
            throw SupabaseAuthTransitionError.signOutInProgress
        }
        guard let sessionUserID = client.auth.currentSession?.user.id,
              expectedUserID.map({ $0 == sessionUserID }) ?? true else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        if let transition {
            guard currentSessionMatchesAuthTransition(transition) else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }
        }

        return [
            "Authorization": "Bearer \(token)",
            "apikey": MerianEnvironment.supabaseAnonKey,
            "Content-Type": "application/json"
        ]
    }

    /// Handles the SDK's fallback auth URL without allowing it to bypass the
    /// same transition owner used by Apple, Google, sign-out, and recovery.
    /// Product account upgrades remain Apple/Google-only: a callback may
    /// establish a session from no local session or refresh the exact existing
    /// linked account, but it may not replace an anonymous or different account.
    func handleAuthenticationCallbackURL(_ url: URL) async {
        guard !hasPendingPurchaseIdentityHandoffFailClosed(),
              let transition = beginAuthTransition(.authenticationCallback)
        else {
            MerianLog.auth.debug(
                "Ignored an authentication callback while another identity transition is pending."
            )
            return
        }
        defer { finishAuthTransition(transition) }

        let sourceSession = activeAuthTransition?.sourceSession
        guard sourceSession?.isAnonymous != true,
              currentSessionMatchesAuthTransition(transition) else {
            MerianLog.auth.debug(
                "Ignored an authentication callback that cannot replace the current signed-out profile."
            )
            return
        }

        var didInstallSession = false
        do {
            _ = try await verifiedExpectedSessionIfPresent(for: transition)
            _ = updateAuthTransition(transition, phase: .installingSession)
            let session = try await Self.performOAuthSessionReplacement(
                suspendAnalytics: {
                    self.analyticsGeneration(for: transition)
                },
                installSession: {
                    let installed = try await self.client.auth.session(from: url)
                    didInstallSession = true
                    return installed
                },
                currentSession: {
                    self.client.auth.currentSession
                },
                reconcileSession: { _, installed in
                    self.reconcileOAuthSessionReplacement(
                        session: installed,
                        transition: transition
                    )
                }
            )
            let target = transitionSession(from: session.user)!
            guard ownsAuthTransition(transition),
                  Self.acceptsAuthenticationCallbackTarget(
                    sourceSession: sourceSession,
                    targetSession: target
                  ),
                  adoptAuthTransitionSession(session.user, for: transition),
                  currentSessionMatchesAuthTransition(transition) else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }

            currentUser = session.user
            isAuthenticated = true
            _ = updateAuthTransition(transition, phase: .bindingPurchases)
            _ = await ensureTelemetryLinkedWhenSafe(
                for: session.user,
                ownedBy: transition
            )
            guard currentSessionMatchesAuthTransition(transition),
                  RevenueCatManager.shared.linkedAuthUserID == session.user.id,
                  RevenueCatManager.shared.isIdentityReady else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }
            await EntitlementManager.shared.beginSession(
                userID: session.user.id,
                client: client,
                authTransitionOwner: transition
            )
            _ = try await verifiedExpectedSession(for: transition)
            _ = updateAuthTransition(transition, phase: .finalizing)
            KeychainManager.shared.set(
                !session.user.isAnonymous,
                forKey: KeychainKeys.hasAuthenticatedOAuth
            )
        } catch {
            if Self.shouldClearOAuthSessionAfterFailure(
                observedSessionMutation: didInstallSession,
                sourceSession: sourceSession,
                currentSession: transitionSession(
                    from: client.auth.currentSession?.user
                )
            ) {
                await clearLocalSessionAfterAuthFailure(ownedBy: transition)
            }
            MerianLog.auth.debug(
                "Authentication callback failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
        }
    }

    // MARK: - Google Sign-In

    func signInWithGoogle() async {
        guard let transition = beginAuthTransition(.oauth(.google)) else {
            MerianLog.auth.debug(
                "Ignored Google Sign-In because another authentication transition owns the session."
            )
            return
        }
        _ = updateAuthTransition(transition, phase: .awaitingProvider)
        defer { finishAuthTransition(transition) }

        guard let rootVC = getRootViewController() else {
            MerianLog.auth.debug("Failed to find root view controller for Google Sign-In.")
            return
        }

        let sourceSession = activeAuthTransition?.sourceSession
        var didInstallGoogleSession = false
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
            _ = try await verifiedExpectedSessionIfPresent(for: transition)
            guard let idToken = result.user.idToken?.tokenString else {
                MerianLog.auth.debug("Google Sign-In: no ID token returned.")
                return
            }
            let accessToken = result.user.accessToken.tokenString

            let completion = try await self.finalizeOAuthLogin(
                provider: .google,
                idToken: idToken,
                accessToken: accessToken,
                nonce: nil,
                transition: transition,
                didMutateSession: {
                    didInstallGoogleSession = true
                }
            )
            let didPersistGoogleMetadata = await updateGoogleUserMetadataIfAvailable(
                from: result.user,
                expectedUserID: completion.session.user.id,
                transition: transition
            )
            let session = try await verifiedExpectedSession(for: transition)
            currentUser = session.user
            isAuthenticated = true
            _ = updateAuthTransition(transition, phase: .bindingPurchases)
            _ = await ensureTelemetryLinkedWhenSafe(
                for: session.user,
                ownedBy: transition
            )
            guard currentSessionMatchesAuthTransition(transition),
                  RevenueCatManager.shared.linkedAuthUserID == session.user.id,
                  RevenueCatManager.shared.isIdentityReady else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }
            await EntitlementManager.shared.beginSession(
                userID: session.user.id,
                client: client,
                authTransitionOwner: transition
            )
            _ = try await verifiedExpectedSession(for: transition)
            if didPersistGoogleMetadata {
                _ = await refreshPublicAuthorIdentity(
                    expectedUserID: session.user.id,
                    ownedBy: transition
                )
            }
            _ = updateAuthTransition(transition, phase: .finalizing)
            _ = try await verifiedExpectedSession(for: transition)
            publishPublicAuthorIdentityChanged(
                previousUserId: completion.previousUserId,
                currentUserId: session.user.id.uuidString
            )

            KeychainManager.shared.set(true, forKey: KeychainKeys.hasAuthenticatedOAuth)
            MerianLog.auth.debug("Google Sign-In complete.")
        } catch {
            if Self.shouldClearOAuthSessionAfterFailure(
                observedSessionMutation: didInstallGoogleSession,
                sourceSession: sourceSession,
                currentSession: transitionSession(
                    from: client.auth.currentSession?.user
                )
            ) {
                await clearLocalSessionAfterAuthFailure(ownedBy: transition)
            }
            MerianLog.auth.debug(
                "Google Sign-In failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
        }
    }

    // MARK: - Apple Sign-In

    func startAppleSignIn() {
        guard let transition = beginAuthTransition(.oauth(.apple)) else {
            MerianLog.auth.debug(
                "Ignored Apple Sign-In because another authentication transition owns the session."
            )
            return
        }
        _ = updateAuthTransition(transition, phase: .awaitingProvider)

        let nonce: String
        do {
            nonce = try randomNonceString()
        } catch {
            finishAuthTransition(transition)
            MerianLog.auth.error(
                "Apple Sign-In bootstrap failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
            return
        }

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        guard keyWindowAnchor() != nil else {
            finishAuthTransition(transition)
            MerianLog.auth.error("Apple Sign-In aborted because no presentation anchor is available.")
            return
        }

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        // Retained strongly to avoid deallocation during the sign-in flow.
        activeAppleSignInAttempt = AppleSignInAttempt(
            transition: transition,
            nonce: nonce,
            controller: controller
        )
        controller.performRequests()
    }

    // MARK: - Private OAuth Helpers

    private func finalizeOAuthLogin(
        provider: OpenIDConnectCredentials.Provider,
        idToken: String,
        accessToken: String?,
        nonce: String?,
        transition: AuthTransitionToken,
        didMutateSession: @MainActor () -> Void
    ) async throws -> OAuthLoginCompletion {
        guard ownsAuthTransition(transition), !isSigningOut else {
            throw SupabaseAuthTransitionError.signOutInProgress
        }

        let previousSession = try await verifiedExpectedSessionIfPresent(
            for: transition
        )
        let previousUserId = previousSession?.user.id.uuidString

        if previousSession?.user.isAnonymous == true {
            guard await completePendingSignOutPurchaseHandoffIfNeeded(
                expectedDestinationUserId: previousUserId,
                ownedBy: transition
            ) else {
                throw SupabaseAuthTransitionError
                    .signOutPurchaseContinuityPending
            }
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
                didMutateSession()
                guard ownsAuthTransition(transition) else {
                    throw SupabaseAuthTransitionError.signOutSessionChanged
                }
                if let previousUserId {
                    try clearPendingGhostProfileMerges(
                        ghostUserId: previousUserId
                    )
                }
            } catch {
                guard Self.requiresProviderBoundGhostMerge(after: error) else {
                    throw error
                }
                guard ownsAuthTransition(transition), !isSigningOut else {
                    throw SupabaseAuthTransitionError.signOutInProgress
                }
                guard let ghostId = previousUserId?.lowercased() else {
                    throw SupabaseAuthTransitionError.guestMergeSessionChanged
                }

                let currentGuestSession = try await verifiedExpectedSession(
                    for: transition
                )
                guard currentGuestSession.user.isAnonymous,
                      currentGuestSession.user.id.uuidString.lowercased() == ghostId else {
                    throw SupabaseAuthTransitionError.guestMergeSessionChanged
                }

                let providerSubject = try Self.oauthProviderSubject(from: idToken)
                _ = try await prepareGhostProfileMerge(
                    ghostUserId: ghostId,
                    provider: provider,
                    providerSubject: providerSubject,
                    ownedBy: transition
                )

                _ = try await verifiedExpectedSession(for: transition)
                _ = updateAuthTransition(
                    transition,
                    phase: .installingSession
                )

                let targetSession = try await installOAuthSessionReplacingCurrentAccount(
                    credentials: credentials,
                    transition: transition
                )
                didMutateSession()
                guard adoptAuthTransitionSession(
                    targetSession.user,
                    for: transition
                ), currentSessionMatchesAuthTransition(transition) else {
                    throw SupabaseAuthTransitionError.signOutSessionChanged
                }
                if targetSession.user.id.uuidString.lowercased() == ghostId {
                    try clearPendingGhostProfileMerges(ghostUserId: ghostId)
                } else {
                    _ = await completePendingGhostProfileMergeIfNeeded(
                        expectedTargetUserId: targetSession.user.id.uuidString,
                        ownedBy: transition
                    )
                }
            }
        } else {
            _ = updateAuthTransition(transition, phase: .installingSession)
            let targetSession = try await installOAuthSessionReplacingCurrentAccount(
                credentials: .init(
                    provider: provider,
                    idToken: idToken,
                    accessToken: accessToken,
                    nonce: nonce
                ),
                transition: transition
            )
            didMutateSession()
            guard adoptAuthTransitionSession(
                targetSession.user,
                for: transition
            ), currentSessionMatchesAuthTransition(transition) else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }
        }

        let targetSession = try await client.auth.session
        guard ownsAuthTransition(transition) else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        if authTransitionCoordinator.active?.expectedSession ==
            transitionSession(from: previousSession?.user) {
            guard adoptAuthTransitionSession(
                targetSession.user,
                for: transition
            ) else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }
        }
        guard currentSessionMatchesAuthTransition(transition) else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        return OAuthLoginCompletion(
            previousUserId: previousUserId,
            session: targetSession
        )
    }

    private func registerAppleRevocationCredential(
        registrationId: UUID,
        authorizationCode: String,
        identityToken: String,
        expectedUserID: UUID,
        ownedBy transition: AuthTransitionToken
    ) async throws {
        try await Self.performAppleCredentialRegistrationWithRetry {
            guard self.currentSessionMatchesAuthTransition(transition),
                  self.client.auth.currentSession?.user.id
                    == expectedUserID else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }
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
            guard response.success,
                  response.status == "registered" else {
                throw AppleSignInBootstrapError.invalidCredentialRegistrationReceipt
            }
            guard self.currentSessionMatchesAuthTransition(transition),
                  self.client.auth.currentSession?.user.id
                    == expectedUserID else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
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
        credentials: OpenIDConnectCredentials,
        transition: AuthTransitionToken
    ) async throws -> Session {
        try await Self.performOAuthSessionReplacement(
            suspendAnalytics: {
                self.analyticsGeneration(for: transition)
            },
            installSession: {
                try await self.client.auth.signInWithIdToken(
                    credentials: credentials
                )
            },
            currentSession: {
                self.client.auth.currentSession
            },
            reconcileSession: { _, session in
                self.reconcileOAuthSessionReplacement(
                    session: session,
                    transition: transition
                )
            }
        )
    }

    private func reconcileOAuthSessionReplacement(
        session: Session?,
        transition: AuthTransitionToken
    ) {
        guard ownsAuthTransition(transition) else { return }
        let resolvedSession = client.auth.currentSession ?? session
        let activeSession = !isSigningOut && resolvedSession?.isExpired == false
            ? resolvedSession
            : nil
        currentUser = activeSession?.user
        isAuthenticated = activeSession != nil
    }

    @discardableResult
    private func prepareGhostProfileMerge(
        ghostUserId: String,
        provider: OpenIDConnectCredentials.Provider,
        providerSubject: String,
        ownedBy transition: AuthTransitionToken
    ) async throws -> PendingGhostProfileMerge {
        guard currentSessionMatchesAuthTransition(transition),
              client.auth.currentSession?.user.id.uuidString.lowercased()
                == ghostUserId.lowercased() else {
            throw SupabaseAuthTransitionError.guestMergeSessionChanged
        }
        let response: GhostProfileMergePrepareResponse = try await client.functions.invoke(
            "merge-ghost-profile",
            options: .init(
                body: GhostProfileMergePreparePayload(
                    provider: provider.rawValue,
                    provider_subject: providerSubject
                )
            )
        )
        guard currentSessionMatchesAuthTransition(transition),
              client.auth.currentSession?.user.id.uuidString.lowercased()
                == ghostUserId.lowercased() else {
            throw SupabaseAuthTransitionError.guestMergeSessionChanged
        }

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
        expectedTargetUserId: String? = nil,
        ownedBy transition: AuthTransitionToken? = nil
    ) async -> Bool {
        let expectedUserID = expectedTargetUserId.flatMap(UUID.init(uuidString:))
            ?? currentUser?.id
        guard let expectedUserID else { return false }
        let accountWorkLease: AccountBoundWorkLease?
        if let transition {
            guard ownsAuthTransition(transition),
                  currentSessionMatchesAuthTransition(transition),
                  client.auth.currentSession?.user.id == expectedUserID else {
                return false
            }
            accountWorkLease = nil
        } else {
            guard let lease = try? beginUnownedAccountBoundWork(
                expectedUserID: expectedUserID
            ) else { return false }
            accountWorkLease = lease
        }
        defer {
            if let accountWorkLease {
                finishAccountBoundWork(accountWorkLease)
            }
        }

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
                expectedTargetUserId: expectedTargetUserId,
                ownedBy: transition
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
        expectedTargetUserId: String?,
        ownedBy transition: AuthTransitionToken?
    ) async -> Bool {
        guard !Task.isCancelled, !isSigningOut else { return false }
        let pendingHandoffs: [PendingGhostProfileMerge]
        do {
            pendingHandoffs = try loadPendingGhostProfileMergeQueue()
        } catch {
            ConsentManager.shared.setAnalyticsSuppressedForGhostHandoff(true)
            MerianLog.auth.error(
                "Signed-out profile upgrade remains pending because its durable queue is unreadable; kind=\(MerianLog.errorKind(error), privacy: .public)"
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
            if let transition,
               !currentSessionMatchesAuthTransition(transition) {
                return false
            }
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
                    if let transition,
                       !currentSessionMatchesAuthTransition(transition) {
                        return false
                    }
                    guard let ghostUUID = UUID(uuidString: pending.ghostUserId) else {
                        throw SupabaseAuthTransitionError.guestMergeSessionChanged
                    }
                    try await Self.finalizeGhostProfileHandoff(
                        completeServerHandoff: {
                            guard self.currentUser?.id == targetUUID,
                                  self.client.auth.currentSession?.user.id
                                    == targetUUID,
                                  transition.map(
                                    self.currentSessionMatchesAuthTransition
                                  ) ?? true else {
                                throw SupabaseAuthTransitionError
                                    .guestMergeSessionChanged
                            }
                            try await self.client.functions.invoke(
                                "merge-ghost-profile",
                                options: .init(
                                    body: GhostProfileMergeCompletePayload(
                                        handoff_id: pending.handoffId,
                                        handoff_secret: pending.handoffSecret
                                    )
                                )
                            )
                            guard self.currentUser?.id == targetUUID,
                                  self.client.auth.currentSession?.user.id
                                    == targetUUID,
                                  transition.map(
                                    self.currentSessionMatchesAuthTransition
                                  ) ?? true else {
                                throw SupabaseAuthTransitionError
                                    .guestMergeSessionChanged
                            }
                        },
                        synchronizeProviderPurchases: {
                            guard self.currentUser?.id == targetUUID,
                                  self.client.auth.currentSession?.user.id
                                    == targetUUID,
                                  transition.map(
                                    self.currentSessionMatchesAuthTransition
                                  ) ?? true else {
                                throw SupabaseAuthTransitionError
                                    .guestMergeSessionChanged
                            }
                            try await RevenueCatManager.shared
                                .synchronizePurchasesAfterAccountMerge()
                        },
                        rebindAndSynchronizeLocalEvidence: {
                            guard self.currentUser?.id == targetUUID,
                                  self.client.auth.currentSession?.user.id
                                    == targetUUID,
                                  transition.map(
                                    self.currentSessionMatchesAuthTransition
                                  ) ?? true else {
                                throw SupabaseAuthTransitionError
                                    .guestMergeSessionChanged
                            }
                            try await ConsentManager.shared
                                .rebindAndSynchronizeGhostEvidence(
                                    from: ghostUUID,
                                    to: targetUUID
                                )
                        },
                        clearPendingHandoff: {
                            guard !self.isSigningOut,
                                  self.currentUser?.id == targetUUID,
                                  self.client.auth.currentSession?.user.id
                                    == targetUUID,
                                  transition.map(
                                    self.currentSessionMatchesAuthTransition
                                  ) ?? true,
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
                    guard !Task.isCancelled, !isSigningOut,
                          transition.map(currentSessionMatchesAuthTransition)
                            ?? true else { return false }
                    MerianLog.auth.debug("Signed-out profile upgrade finalized.")
                } catch {
                    if Self.shouldDiscardPendingGhostProfileMerge(after: error) {
                        do {
                            // Terminal handoffs are never rebound locally, but
                            // the permanent account must still be authoritative
                            // before removing the durable suppression marker.
                            if let transition {
                                try await ConsentManager.shared
                                    .synchronizeWithCurrentSession(
                                        ownedBy: transition
                                    )
                            } else {
                                try await ConsentManager.shared
                                    .synchronizeWithCurrentSession()
                            }
                            try Task.checkCancellation()
                            guard !isSigningOut,
                                  currentUser?.id == targetUUID,
                                  client.auth.currentSession?.user.id
                                    == targetUUID,
                                  transition.map(
                                    currentSessionMatchesAuthTransition
                                  ) ?? true,
                                  ConsentManager.shared.currentSessionUserId
                                    == targetUUID else {
                                throw SupabaseAuthTransitionError
                                    .guestMergeSessionChanged
                            }
                            try clearPendingGhostProfileMerge(
                                handoffId: pending.handoffId
                            )
                            MerianLog.auth.error(
                                "Discarded a terminal signed-out profile handoff; kind=\(MerianLog.errorKind(error), privacy: .public)"
                            )
                        } catch {
                            allHandoffsResolved = false
                            MerianLog.auth.error(
                                "Terminal signed-out handoff cleanup remains pending; kind=\(MerianLog.errorKind(error), privacy: .public)"
                            )
                        }
                    } else {
                        allHandoffsResolved = false
                        MerianLog.auth.error(
                            "Signed-out profile upgrade remains pending and will retry; kind=\(MerianLog.errorKind(error), privacy: .public)"
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
                "Signed-out profile upgrade retry could not read the active session; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
            return false
        }
    }

    @discardableResult
    private func refreshPublicAuthorIdentity(
        expectedUserID: UUID,
        ownedBy transition: AuthTransitionToken? = nil
    ) async -> Bool {
        let accountWorkLease: AccountBoundWorkLease?
        if let transition {
            guard ownsAuthTransition(transition),
                  currentSessionMatchesAuthTransition(transition),
                  client.auth.currentSession?.user.id == expectedUserID else {
                return false
            }
            accountWorkLease = nil
        } else {
            guard let lease = try? beginUnownedAccountBoundWork(
                expectedUserID: expectedUserID
            ) else { return false }
            accountWorkLease = lease
        }
        defer {
            if let accountWorkLease {
                finishAccountBoundWork(accountWorkLease)
            }
        }

        do {
            try await client.functions.invoke(
                "merge-ghost-profile",
                options: .init(body: GhostProfileIdentityRefreshPayload())
            )
            if let transition {
                return currentSessionMatchesAuthTransition(transition)
                    && client.auth.currentSession?.user.id == expectedUserID
            }
            return accountWorkLease.map(isAccountBoundWorkLeaseCurrent)
                ?? false
        } catch {
            MerianLog.auth.debug(
                "Public author identity refresh failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
            return false
        }
    }

    private func prepareSignOutPurchaseHandoff(
        sourceUserId: String,
        ownedBy transition: AuthTransitionToken
    ) async throws {
        let normalizedSourceUserId = sourceUserId.lowercased()
        let startingSession = try await client.auth.session
        guard currentSessionMatchesAuthTransition(transition),
              !startingSession.user.isAnonymous,
              startingSession.user.id.uuidString.lowercased()
                == normalizedSourceUserId else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }

        let response: SignOutPurchasePrepareResponse = try await client.functions.invoke(
            "transfer-signout-purchases",
            options: .init(body: SignOutPurchasePreparePayload())
        )
        guard response.success,
              UUID(uuidString: response.handoff_id) != nil,
              response.handoff_secret.range(
                of: #"^[A-Za-z0-9_-]{43}$"#,
                options: .regularExpression
              ) != nil,
              ISO8601DateFormatter().date(from: response.expires_at) != nil else {
            throw SupabaseAuthTransitionError
                .signOutPurchaseHandoffPersistenceFailed
        }

        let pending = PendingSignOutPurchaseHandoff(
            sourceUserId: normalizedSourceUserId,
            handoffId: response.handoff_id.lowercased(),
            handoffSecret: response.handoff_secret,
            expiresAt: response.expires_at
        )
        try persistPendingSignOutPurchaseHandoff(pending)

        let verifiedSession = try await client.auth.session
        guard currentSessionMatchesAuthTransition(transition),
              !verifiedSession.user.isAnonymous,
              verifiedSession.user.id.uuidString.lowercased()
                == normalizedSourceUserId else {
            // The durable proof remains available if a concurrent session
            // transition already reached the anonymous destination.
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
        MerianLog.auth.debug("Secured purchase continuity before sign-out.")
    }

    @discardableResult
    private func completePendingSignOutPurchaseHandoffIfNeeded(
        expectedDestinationUserId: String? = nil,
        expectedAuthGeneration: UInt64? = nil,
        ownedBy transition: AuthTransitionToken? = nil
    ) async -> Bool {
        let normalizedExpected = expectedDestinationUserId?.lowercased()
            ?? (currentUser?.isAnonymous == true
                ? currentUser?.id.uuidString.lowercased()
                : nil)
        let accountWorkLease: AccountBoundWorkLease?
        if let transition {
            guard ownsAuthTransition(transition) else { return false }
            accountWorkLease = nil
        } else {
            let expectedUserID = normalizedExpected.flatMap {
                UUID(uuidString: $0)
            }
            guard let lease = try? beginUnownedAccountBoundWork(
                expectedUserID: expectedUserID
            ) else { return false }
            accountWorkLease = lease
        }
        defer {
            if let accountWorkLease {
                finishAccountBoundWork(accountWorkLease)
            }
        }

        let generation = expectedAuthGeneration ?? authSessionGeneration
        if let existingTask = signOutPurchaseHandoffTask {
            if signOutPurchaseHandoffTargetUserId == normalizedExpected,
               signOutPurchaseHandoffAuthGeneration == generation {
                return await existingTask.value
            }
            cancelSignOutPurchaseHandoffTask()
        }

        let taskId = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            do {
                if try self.loadPendingSignOutPurchaseHandoff() == nil,
                   try self.loadPendingPurchasePrincipalAuthRotation() != nil {
                    return await self
                        .completePendingPurchasePrincipalAuthRotationIfNeeded(
                            expectedDestinationUserId: normalizedExpected,
                            expectedAuthGeneration: generation,
                            ownedBy: transition
                        )
                }
            } catch {
                RevenueCatManager.shared
                    .setPurchaseIdentityHandoffPending(true)
                return false
            }
            return await self.performPendingSignOutPurchaseHandoff(
                expectedDestinationUserId: normalizedExpected,
                ownedBy: transition
            )
        }
        signOutPurchaseHandoffTaskId = taskId
        signOutPurchaseHandoffTargetUserId = normalizedExpected
        signOutPurchaseHandoffAuthGeneration = generation
        signOutPurchaseHandoffTask = task
        let result = await task.value
        if signOutPurchaseHandoffTaskId == taskId {
            signOutPurchaseHandoffTask = nil
            signOutPurchaseHandoffTaskId = nil
            signOutPurchaseHandoffTargetUserId = nil
            signOutPurchaseHandoffAuthGeneration = nil
        }
        return result
    }

    private func completePendingPurchasePrincipalAuthRotationIfNeeded(
        expectedDestinationUserId: String?,
        expectedAuthGeneration: UInt64?,
        ownedBy transition: AuthTransitionToken?
    ) async -> Bool {
        let pending: ServerPrincipalRotation
        do {
            guard let loaded = try loadPendingPurchasePrincipalAuthRotation() else {
                let legacyPending = try loadPendingSignOutPurchaseHandoff() != nil
                RevenueCatManager.shared.setPurchaseIdentityHandoffPending(
                    legacyPending
                )
                return true
            }
            guard case let .server(serverRotation) = loaded,
                  serverRotation.localState == .prepared else {
                // A legacy client-only marker or a preparation that never
                // durably received its server expiry cannot authorize an Auth
                // destination. Keep the purchase boundary closed.
                RevenueCatManager.shared
                    .setPurchaseIdentityHandoffPending(true)
                return false
            }
            pending = serverRotation
        } catch {
            RevenueCatManager.shared.setPurchaseIdentityHandoffPending(true)
            return false
        }

        RevenueCatManager.shared.setPurchaseIdentityHandoffPending(true)
        let generation = expectedAuthGeneration ?? authSessionGeneration
        do {
            let session = try await client.auth.session
            let destinationUserId = session.user.id.uuidString.lowercased()
            guard session.user.isAnonymous,
                  destinationUserId != pending.sourceUserId.lowercased(),
                  expectedDestinationUserId.map({
                      $0.lowercased() == destinationUserId
                  }) ?? true,
                  authSessionGeneration == generation,
                  currentUser?.id == session.user.id else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }

            guard let rotationId = UUID(uuidString: pending.rotationId) else {
                throw SupabaseAuthTransitionError
                    .purchasePrincipalRotationPersistenceFailed
            }
            let binding = try await purchasePrincipalResolver
                .claimSignoutRotation(
                    rotationId: rotationId,
                    rotationSecret: pending.rotationSecret,
                    expectedCapabilityFingerprint:
                        pending.installationCapabilityFingerprint
                )
            guard authSessionGeneration == generation,
                  currentUser?.id == session.user.id,
                  client.auth.currentSession?.user.id == session.user.id,
                  binding.mode == .stable,
                  binding.purchasePrincipalId?.uuidString.lowercased()
                    == pending.purchasePrincipalId.lowercased(),
                  binding.revenueCatAppUserId == pending.revenueCatAppUserId,
                  binding.bindingGeneration.map({
                      $0 > pending.bindingGeneration
                  }) == true else {
                throw SupabaseAuthTransitionError
                    .signOutPurchaseContinuityPending
            }

            activePurchasePrincipalBinding = binding
            RevenueCatManager.shared.beginPurchaseIdentityResolution()
            await RevenueCatManager.shared.linkResolvedPurchasePrincipal(
                binding,
                authUserID: session.user.id,
                accountKind: RevenueCatAccountMutationPolicy.accountKind(
                    isAnonymous: true
                )
            )
            guard RevenueCatManager.shared.isIdentityReady,
                  RevenueCatManager.shared.linkedAuthUserID == session.user.id,
                  authSessionGeneration == generation else {
                throw SupabaseAuthTransitionError
                    .signOutPurchaseContinuityPending
            }

            guard await EntitlementManager.shared.beginSession(
                userID: session.user.id,
                client: client,
                authTransitionOwner: transition
            ) else {
                throw SupabaseAuthTransitionError
                    .signOutPurchaseContinuityPending
            }
            let verifiedSession = try await client.auth.session
            guard verifiedSession.user.isAnonymous,
                  verifiedSession.user.id == session.user.id,
                  authSessionGeneration == generation,
                  currentUser?.id == session.user.id else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }
            try clearPendingPurchasePrincipalAuthRotation()
            let legacyPending = try loadPendingSignOutPurchaseHandoff() != nil
            RevenueCatManager.shared.setPurchaseIdentityHandoffPending(
                legacyPending
            )
            if !legacyPending {
                await RevenueCatManager.shared.refreshCustomerInfo()
            }
            lastLinkedUserId = session.user.id
            MerianLog.auth.debug(
                "Claimed the server-authorized stable purchase identity after sign-out."
            )
            return true
        } catch {
            RevenueCatManager.shared.setPurchaseIdentityHandoffPending(true)
            MerianLog.auth.debug(
                "Stable purchase identity rotation remains pending; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
            return false
        }
    }

    private func performPendingSignOutPurchaseHandoff(
        expectedDestinationUserId: String?,
        ownedBy transition: AuthTransitionToken?
    ) async -> Bool {
        guard !Task.isCancelled, !isSigningOut else { return false }

        let pending: PendingSignOutPurchaseHandoff
        do {
            guard let loaded = try loadPendingSignOutPurchaseHandoff() else {
                let stablePending = try loadPendingPurchasePrincipalAuthRotation()
                    != nil
                RevenueCatManager.shared.setPurchaseIdentityHandoffPending(
                    stablePending
                )
                return true
            }
            pending = loaded
        } catch {
            RevenueCatManager.shared.setPurchaseIdentityHandoffPending(true)
            MerianLog.auth.error(
                "Purchase continuity remains pending because its device proof is unreadable; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
            return false
        }
        RevenueCatManager.shared.setPurchaseIdentityHandoffPending(true)

        do {
            let session = try await client.auth.session
            let destinationUserId = session.user.id.uuidString.lowercased()
            guard session.user.isAnonymous else {
                if destinationUserId == pending.sourceUserId.lowercased() {
                    await abandonPendingSignOutPurchaseHandoffIfSourceRestored(
                        sourceUserId: pending.sourceUserId,
                        ownedBy: transition
                    )
                }
                return false
            }
            if let expectedDestinationUserId,
               destinationUserId != expectedDestinationUserId {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }

            try await Self.finalizeSignOutPurchaseHandoff(
                bindDestination: {
                    let bound: SignOutPurchaseBindResponse = try await self.client.functions.invoke(
                        "transfer-signout-purchases",
                        options: .init(
                            body: SignOutPurchaseContinuePayload(
                                operation: "bind",
                                handoff_id: pending.handoffId,
                                handoff_secret: pending.handoffSecret
                            )
                        )
                    )
                    guard bound.success,
                          bound.handoff_id.caseInsensitiveCompare(
                            pending.handoffId
                          ) == .orderedSame,
                          bound.destination_user_id.lowercased()
                            == destinationUserId else {
                        throw SupabaseAuthTransitionError
                            .signOutSessionChanged
                    }
                },
                verifyBoundDestinationSession: {
                    try await self.verifyActiveAnonymousSession(
                        userId: destinationUserId
                    )
                },
                linkProviderIdentity: {
                    try await self
                        .linkLegacyRevenueCatIdentityForSignOutHandoff(
                            user: session.user
                        )
                },
                verifyLinkedDestinationSession: {
                    try await self.verifyActiveAnonymousSession(
                        userId: destinationUserId
                    )
                },
                synchronizeStorePurchases: {
                    try await RevenueCatManager.shared
                        .synchronizePurchasesAfterIdentityHandoff(
                            expectedUserId: session.user.id
                        )
                },
                completeServerHandoff: {
                    let completed: SignOutPurchaseOperationResponse = try await self.client.functions.invoke(
                        "transfer-signout-purchases",
                        options: .init(
                            body: SignOutPurchaseContinuePayload(
                                operation: "complete",
                                handoff_id: pending.handoffId,
                                handoff_secret: pending.handoffSecret
                            )
                        )
                    )
                    guard completed.success,
                          completed.handoff_id.caseInsensitiveCompare(
                            pending.handoffId
                          ) == .orderedSame else {
                        throw SupabaseAuthTransitionError
                            .signOutSessionChanged
                    }
                },
                refreshServerEntitlement: {
                    await EntitlementManager.shared.beginSession(
                        userID: session.user.id,
                        client: self.client,
                        authTransitionOwner: transition
                    )
                },
                verifyFinalDestinationSession: {
                    try await self.verifyActiveAnonymousSession(
                        userId: destinationUserId
                    )
                },
                clearPendingHandoff: {
                    try self.clearPendingSignOutPurchaseHandoff()
                }
            )
            let stableRotationPending =
                try loadPendingPurchasePrincipalAuthRotation() != nil
            RevenueCatManager.shared.setPurchaseIdentityHandoffPending(
                stableRotationPending
            )
            // Compatibility completion is the safety boundary. Once its proof
            // is gone, a stable rollout may adopt/rebind this installation
            // without changing which customer the completed handoff verified.
            _ = await ensureTelemetryLinkedWhenSafe(
                for: session.user,
                ownedBy: transition
            )
            MerianLog.auth.debug(
                "Verified purchase continuity for the signed-out session."
            )
            return true
        } catch {
            if Self.shouldDiscardPendingSignOutPurchaseHandoff(after: error) {
                do {
                    try clearPendingSignOutPurchaseHandoff()
                    let stableRotationPending =
                        try loadPendingPurchasePrincipalAuthRotation() != nil
                    RevenueCatManager.shared.setPurchaseIdentityHandoffPending(
                        stableRotationPending
                    )
                } catch {
                    RevenueCatManager.shared
                        .setPurchaseIdentityHandoffPending(true)
                }
            }
            MerianLog.auth.debug(
                "Purchase continuity retry remains pending; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
            return false
        }
    }

    /// Re-reads the device proof before any operation that could replace the
    /// active Auth identity. An unreadable Keychain value is treated as an
    /// unresolved handoff so a transient device-access failure cannot strand
    /// the one destination already bound on the server.
    func hasPendingPurchaseIdentityHandoffFailClosed() -> Bool {
        do {
            let pendingLegacyHandoff = try loadPendingSignOutPurchaseHandoff()
            let pendingStableRotation = try loadPendingPurchasePrincipalAuthRotation()
            let pending = pendingLegacyHandoff != nil || pendingStableRotation != nil
            RevenueCatManager.shared.setPurchaseIdentityHandoffPending(pending)
            return pending
        } catch {
            RevenueCatManager.shared.setPurchaseIdentityHandoffPending(true)
            MerianLog.auth.error(
                "Could not verify the purchase handoff proof; preserving the active identity."
            )
            return true
        }
    }

    private func loadPendingSignOutPurchaseHandoff() throws
        -> PendingSignOutPurchaseHandoff? {
        guard let data = try KeychainManager.shared.dataOrThrow(
            forKey: KeychainKeys.pendingSignOutPurchaseHandoff
        ) else {
            return nil
        }
        guard let pending = try? JSONDecoder().decode(
            PendingSignOutPurchaseHandoff.self,
            from: data
        ),
        UUID(uuidString: pending.sourceUserId) != nil,
        UUID(uuidString: pending.handoffId) != nil,
        pending.handoffSecret.range(
            of: #"^[A-Za-z0-9_-]{43}$"#,
            options: .regularExpression
        ) != nil,
        ISO8601DateFormatter().date(from: pending.expiresAt) != nil else {
            throw SupabaseAuthTransitionError
                .signOutPurchaseHandoffPersistenceFailed
        }
        return pending
    }

    private func persistPendingSignOutPurchaseHandoff(
        _ pending: PendingSignOutPurchaseHandoff
    ) throws {
        let encoded = try JSONEncoder().encode(pending)
        guard KeychainManager.shared.set(
            encoded,
            forKey: KeychainKeys.pendingSignOutPurchaseHandoff,
            accessibility: .whenUnlockedThisDeviceOnly
        ),
        try KeychainManager.shared.dataOrThrow(
            forKey: KeychainKeys.pendingSignOutPurchaseHandoff
        ) == encoded else {
            throw SupabaseAuthTransitionError
                .signOutPurchaseHandoffPersistenceFailed
        }
    }

    private func clearPendingSignOutPurchaseHandoff() throws {
        try KeychainManager.shared.removeObjectVerified(
            forKey: KeychainKeys.pendingSignOutPurchaseHandoff
        )
    }

    private func loadPendingPurchasePrincipalAuthRotation() throws
        -> PendingPurchasePrincipalAuthRotation? {
        guard let data = try KeychainManager.shared.dataOrThrow(
            forKey: KeychainKeys.pendingPurchasePrincipalAuthRotation
        ) else {
            return nil
        }
        if let pending = try? JSONDecoder().decode(
            ServerPrincipalRotation.self,
            from: data
        ) {
            guard pending.protocolVersion == 3,
                  UUID(uuidString: pending.rotationId) != nil,
                  pending.rotationSecret.range(
                    of: #"^[A-Za-z0-9_-]{43}$"#,
                    options: .regularExpression
                  ) != nil,
                  UUID(uuidString: pending.sourceUserId) != nil,
                  UUID(uuidString: pending.purchasePrincipalId) != nil,
                  pending.bindingGeneration > 0,
                  PurchasePrincipalBinding.isValidRevenueCatAppUserId(
                    pending.revenueCatAppUserId
                  ),
                  PurchasePrincipalCapabilityPolicy.isValidFingerprint(
                    pending.installationCapabilityFingerprint
                  ),
                  ISO8601DateFormatter().date(from: pending.startedAt) != nil,
                  (pending.localState == .preparing && pending.expiresAt == nil)
                    || (
                        pending.localState == .prepared
                            && pending.expiresAt.map(
                                PurchasePrincipalBinding.isValidServerTimestamp
                            ) == true
                    ) else {
                throw SupabaseAuthTransitionError
                    .purchasePrincipalRotationPersistenceFailed
            }
            return .server(pending)
        }
        if let legacy = try? JSONDecoder().decode(
            LegacyPrincipalRotation.self,
            from: data
        ),
        UUID(uuidString: legacy.sourceUserId) != nil,
        UUID(uuidString: legacy.purchasePrincipalId) != nil,
        PurchasePrincipalBinding.isValidRevenueCatAppUserId(
            legacy.revenueCatAppUserId
        ),
        PurchasePrincipalCapabilityPolicy.isValidFingerprint(
            legacy.installationCapabilityFingerprint
        ),
        ISO8601DateFormatter().date(from: legacy.startedAt) != nil {
            // Protocol-v1 was client-only evidence. It may be retired only
            // from its exact restored source; it can never authorize a new
            // anonymous binding.
            return .legacy(legacy)
        }
        throw SupabaseAuthTransitionError
            .purchasePrincipalRotationPersistenceFailed
    }

    private func persistPendingPurchasePrincipalAuthRotation(
        _ pending: ServerPrincipalRotation
    ) throws {
        let data = try JSONEncoder().encode(pending)
        guard KeychainManager.shared.set(
            data,
            forKey: KeychainKeys.pendingPurchasePrincipalAuthRotation,
            accessibility: .whenUnlockedThisDeviceOnly
        ),
        try KeychainManager.shared.dataOrThrow(
            forKey: KeychainKeys.pendingPurchasePrincipalAuthRotation
        ) == data else {
            throw SupabaseAuthTransitionError
                .purchasePrincipalRotationPersistenceFailed
        }
    }

    private func prepareAndPersistPendingPurchasePrincipalAuthRotation(
        sourceUserId: UUID,
        binding: PurchasePrincipalBinding
    ) async throws {
        guard binding.mode == .stable,
              let principalId = binding.purchasePrincipalId,
              let appUserId = binding.revenueCatAppUserId,
              let bindingGeneration = binding.bindingGeneration,
              bindingGeneration > 0 else {
            throw SupabaseAuthTransitionError
                .purchasePrincipalRotationPersistenceFailed
        }
        let capabilityFingerprint = try purchasePrincipalResolver
            .currentInstallationCapabilityFingerprint()
        let rotationId = UUID()
        let rotationSecret = try PurchasePrincipalResolver
            .generateSignoutRotationSecret()
        let draft = ServerPrincipalRotation(
            protocolVersion: 3,
            localState: .preparing,
            rotationId: rotationId.uuidString.lowercased(),
            rotationSecret: rotationSecret,
            sourceUserId: sourceUserId.uuidString.lowercased(),
            purchasePrincipalId: principalId.uuidString.lowercased(),
            revenueCatAppUserId: appUserId,
            bindingGeneration: bindingGeneration,
            installationCapabilityFingerprint: capabilityFingerprint,
            startedAt: ISO8601DateFormatter().string(from: Date()),
            expiresAt: nil
        )
        // Persist the idempotency key and proof before network I/O. The Auth
        // session is still intact, and a relaunch can safely cancel an absent,
        // in-flight, or already-prepared server reservation with the same ID.
        try persistPendingPurchasePrincipalAuthRotation(draft)
        let preparation = try await purchasePrincipalResolver
            .prepareSignoutRotation(
                rotationId: rotationId,
                rotationSecret: rotationSecret,
                expectedBinding: binding,
                expectedCapabilityFingerprint: capabilityFingerprint
            )
        let prepared = ServerPrincipalRotation(
            protocolVersion: 3,
            localState: .prepared,
            rotationId: rotationId.uuidString.lowercased(),
            rotationSecret: rotationSecret,
            sourceUserId: sourceUserId.uuidString.lowercased(),
            purchasePrincipalId:
                preparation.purchasePrincipalId.uuidString.lowercased(),
            revenueCatAppUserId: preparation.revenueCatAppUserId,
            bindingGeneration: preparation.bindingGeneration,
            installationCapabilityFingerprint: capabilityFingerprint,
            startedAt: draft.startedAt,
            expiresAt: preparation.expiresAt
        )
        try persistPendingPurchasePrincipalAuthRotation(prepared)
    }

    private func clearPendingPurchasePrincipalAuthRotation() throws {
        try KeychainManager.shared.removeObjectVerified(
            forKey: KeychainKeys.pendingPurchasePrincipalAuthRotation
        )
    }

    private func abandonPendingPurchasePrincipalRotationIfSourceRestored(
        sourceUserId: UUID,
        ownedBy transition: AuthTransitionToken? = nil
    ) async {
        let accountWorkLease: AccountBoundWorkLease?
        if let transition {
            guard ownsAuthTransition(transition),
                  currentSessionMatchesAuthTransition(transition),
                  client.auth.currentSession?.user.id == sourceUserId else {
                return
            }
            accountWorkLease = nil
        } else {
            guard let lease = try? beginUnownedAccountBoundWork(
                expectedUserID: sourceUserId
            ) else { return }
            accountWorkLease = lease
        }
        defer {
            if let accountWorkLease {
                finishAccountBoundWork(accountWorkLease)
            }
        }

        guard let session = try? await client.auth.session,
              !session.user.isAnonymous,
              session.user.id == sourceUserId else {
            return
        }
        do {
            if let pending = try loadPendingPurchasePrincipalAuthRotation(),
               pending.sourceUserId.lowercased()
                == sourceUserId.uuidString.lowercased() {
                switch pending {
                case .legacy:
                    // The pre-v3 marker never created server state. It is safe
                    // to retire only because its exact source is still active.
                    break
                case let .server(rotation):
                    guard let rotationId = UUID(
                        uuidString: rotation.rotationId
                    ) else {
                        return
                    }
                    _ = try await purchasePrincipalResolver
                        .cancelSignoutRotation(
                            rotationId: rotationId,
                            rotationSecret: rotation.rotationSecret,
                            expectedCapabilityFingerprint:
                                rotation.installationCapabilityFingerprint
                        )
                }
                guard transition.map(ownsAuthTransition) ??
                        accountWorkLease.map(isAccountBoundWorkLeaseCurrent)
                        ?? false,
                      client.auth.currentSession?.user.id == sourceUserId,
                      let reverified = try? await client.auth.session,
                      !reverified.user.isAnonymous,
                      reverified.user.id == sourceUserId else {
                    return
                }
                try clearPendingPurchasePrincipalAuthRotation()
            }
            let legacyPending = try loadPendingSignOutPurchaseHandoff() != nil
            let stablePending = try loadPendingPurchasePrincipalAuthRotation()
                != nil
            RevenueCatManager.shared.setPurchaseIdentityHandoffPending(
                legacyPending || stablePending
            )
        } catch {
            RevenueCatManager.shared.setPurchaseIdentityHandoffPending(true)
        }
    }

    /// A local sign-out error can leave the original linked Supabase session
    /// intact after local RevenueCat/Auth readiness was already cleared. Once
    /// every unused handoff is definitively absent, restore that exact source
    /// session instead of leaving paid operations disabled until a later Auth
    /// event happens to arrive.
    private func restoreSourceIdentityAfterFailedSignOutIfPossible(
        sourceUserId: UUID,
        ownedBy transition: AuthTransitionToken
    ) async {
        guard ownsAuthTransition(transition) else { return }
        guard let session = try? await client.auth.session else {
            return
        }

        let purchaseContinuityPending: Bool
        do {
            let legacyPending = try loadPendingSignOutPurchaseHandoff() != nil
            let stablePending = try loadPendingPurchasePrincipalAuthRotation() != nil
            purchaseContinuityPending = legacyPending || stablePending
        } catch {
            RevenueCatManager.shared.setPurchaseIdentityHandoffPending(true)
            return
        }
        guard Self.shouldRestoreSourceIdentityAfterFailedSignOut(
            activeUserId: session.user.id,
            activeUserIsAnonymous: session.user.isAnonymous,
            sourceUserId: sourceUserId,
            purchaseContinuityPending: purchaseContinuityPending
        ) else {
            if purchaseContinuityPending {
                RevenueCatManager.shared.setPurchaseIdentityHandoffPending(true)
            }
            return
        }

        RevenueCatManager.shared.setPurchaseIdentityHandoffPending(false)
        currentUser = session.user
        isAuthenticated = true
        KeychainManager.shared.set(
            true,
            forKey: KeychainKeys.hasAuthenticatedOAuth
        )
        ConsentManager.shared.observeSession(userId: sourceUserId)
        schedulePublicAuthorIdentityRefreshIfNeeded(for: session.user)

        let generation = authSessionGeneration
        _ = await ensureTelemetryLinkedWhenSafe(
            for: session.user,
            ownedBy: transition
        )
        guard currentUser?.id == sourceUserId,
              authSessionGeneration == generation else {
            return
        }
        await EntitlementManager.shared.beginSession(
            userID: sourceUserId,
            client: client,
            authTransitionOwner: transition
        )
        MerianLog.auth.debug(
            "Restored the linked purchase identity after local sign-out failed."
        )
    }

    private func abandonPendingSignOutPurchaseHandoffIfSourceRestored(
        sourceUserId: String,
        ownedBy transition: AuthTransitionToken? = nil
    ) async {
        let normalizedSourceUserId = sourceUserId.lowercased()
        guard let sourceUserUUID = UUID(uuidString: normalizedSourceUserId)
        else { return }
        let accountWorkLease: AccountBoundWorkLease?
        if let transition {
            guard ownsAuthTransition(transition),
                  currentSessionMatchesAuthTransition(transition),
                  client.auth.currentSession?.user.id == sourceUserUUID else {
                return
            }
            accountWorkLease = nil
        } else {
            guard let lease = try? beginUnownedAccountBoundWork(
                expectedUserID: sourceUserUUID
            ) else { return }
            accountWorkLease = lease
        }
        defer {
            if let accountWorkLease {
                finishAccountBoundWork(accountWorkLease)
            }
        }

        guard let session = try? await client.auth.session,
              !session.user.isAnonymous,
              session.user.id.uuidString.lowercased()
                == normalizedSourceUserId else {
            return
        }

        do {
            guard let pending = try loadPendingSignOutPurchaseHandoff() else {
                let stableRotation = try loadPendingPurchasePrincipalAuthRotation()
                RevenueCatManager.shared
                    .setPurchaseIdentityHandoffPending(stableRotation != nil)
                return
            }
            guard pending.sourceUserId.lowercased()
                    == normalizedSourceUserId else {
                return
            }
            let cancelled: SignOutPurchaseOperationResponse = try await client.functions.invoke(
                "transfer-signout-purchases",
                options: .init(
                    body: SignOutPurchaseContinuePayload(
                        operation: "cancel",
                        handoff_id: pending.handoffId,
                        handoff_secret: pending.handoffSecret
                    )
                )
            )
            guard cancelled.success,
                  cancelled.handoff_id.caseInsensitiveCompare(
                    pending.handoffId
                  ) == .orderedSame,
                  transition.map(ownsAuthTransition) ??
                    accountWorkLease.map(isAccountBoundWorkLeaseCurrent)
                    ?? false,
                  client.auth.currentSession?.user.id == sourceUserUUID else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }
            try clearPendingSignOutPurchaseHandoff()
            let stableRotationPending =
                try loadPendingPurchasePrincipalAuthRotation() != nil
            RevenueCatManager.shared.setPurchaseIdentityHandoffPending(
                stableRotationPending
            )
            MerianLog.auth.debug(
                "Abandoned an unused sign-out purchase proof after the source account was restored."
            )
        } catch {
            RevenueCatManager.shared.setPurchaseIdentityHandoffPending(true)
            MerianLog.auth.error(
                "Could not clear an unused sign-out purchase proof; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
        }
    }

    private func cancelSignOutPurchaseHandoffTask() {
        signOutPurchaseHandoffTask?.cancel()
        signOutPurchaseHandoffTask = nil
        signOutPurchaseHandoffTaskId = nil
        signOutPurchaseHandoffTargetUserId = nil
        signOutPurchaseHandoffAuthGeneration = nil
    }

    private func verifyActiveAnonymousSession(userId: String) async throws {
        let session = try await client.auth.session
        guard session.user.isAnonymous,
              session.user.id.uuidString.lowercased() == userId.lowercased()
        else {
            throw SupabaseAuthTransitionError.signOutSessionChanged
        }
    }

    nonisolated static func shouldDiscardPendingSignOutPurchaseHandoff(
        after error: Error
    ) -> Bool {
        guard case let FunctionsError.httpError(_, data) = error,
              let payload = try? JSONDecoder().decode(
                SignOutPurchaseErrorPayload.self,
                from: data
              ) else {
            return false
        }
        return payload.code == "handoff_expired"
            || payload.code == "handoff_invalid"
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
                    "Could not migrate the signed-out profile handoff queue; kind=\(MerianLog.errorKind(error), privacy: .public)"
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
    private func updateGoogleUserMetadataIfAvailable(
        from googleUser: GIDGoogleUser,
        expectedUserID: UUID,
        transition: AuthTransitionToken
    ) async -> Bool {
        guard Self.allowsOAuthMetadataMutation(
            transitionIsCurrent:
                currentSessionMatchesAuthTransition(transition),
            transitionExpectedUserID:
                authTransitionCoordinator.active?.expectedSession?.userID,
            currentSessionUserID: client.auth.currentSession?.user.id,
            expectedUserID: expectedUserID
        ) else {
            return false
        }
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
            guard Self.allowsOAuthMetadataMutation(
                transitionIsCurrent:
                    currentSessionMatchesAuthTransition(transition),
                transitionExpectedUserID:
                    authTransitionCoordinator.active?.expectedSession?.userID,
                currentSessionUserID: client.auth.currentSession?.user.id,
                expectedUserID: expectedUserID,
                updatedUserID: updatedUser.id
            ) else {
                return false
            }
            currentUser = updatedUser
            MerianLog.auth.debug("Google profile metadata persisted for public author identity.")
            return true
        } catch {
            MerianLog.auth.debug(
                "Google profile metadata update failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
            return false
        }
    }

    @discardableResult
    private func updateAppleUserMetadataIfAvailable(
        from components: PersonNameComponents?,
        expectedUserID: UUID,
        transition: AuthTransitionToken
    ) async -> Bool {
        guard Self.allowsOAuthMetadataMutation(
            transitionIsCurrent:
                currentSessionMatchesAuthTransition(transition),
            transitionExpectedUserID:
                authTransitionCoordinator.active?.expectedSession?.userID,
            currentSessionUserID: client.auth.currentSession?.user.id,
            expectedUserID: expectedUserID
        ) else {
            return false
        }
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
            guard Self.allowsOAuthMetadataMutation(
                transitionIsCurrent:
                    currentSessionMatchesAuthTransition(transition),
                transitionExpectedUserID:
                    authTransitionCoordinator.active?.expectedSession?.userID,
                currentSessionUserID: client.auth.currentSession?.user.id,
                expectedUserID: expectedUserID,
                updatedUserID: updatedUser.id
            ) else {
                return false
            }
            currentUser = updatedUser
            MerianLog.auth.debug("Apple profile metadata persisted for public author identity.")
            return true
        } catch {
            MerianLog.auth.debug(
                "Apple profile metadata update failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
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
        guard !TestExecutionCoordinator.isRunningTests,
              !isAuthTransitionInProgress,
              !user.isAnonymous else { return }

        let userId = user.id.uuidString.lowercased()
        guard userId != lastPublicAuthorIdentityRefreshUserId else { return }

        lastPublicAuthorIdentityRefreshUserId = userId
        publicAuthorIdentityRefreshTask?.cancel()
        publicAuthorIdentityRefreshTask = Task { [weak self] in
            await self?.refreshPublicAuthorIdentityForRestoredSession(userId: userId)
        }
    }

    private func refreshPublicAuthorIdentityForRestoredSession(userId: String) async {
        guard let expectedUserID = UUID(uuidString: userId),
              let accountWorkLease = try? beginUnownedAccountBoundWork(
                expectedUserID: expectedUserID
              ) else {
            return
        }
        defer { finishAccountBoundWork(accountWorkLease) }
        defer {
            if currentUser?.id.uuidString.lowercased() == userId || currentUser == nil {
                publicAuthorIdentityRefreshTask = nil
            }
        }

        guard !Task.isCancelled else { return }
        _ = await completePendingGhostProfileMergeIfNeeded(
            expectedTargetUserId: userId
        )
        guard !Task.isCancelled,
              isAccountBoundWorkLeaseCurrent(accountWorkLease) else {
            return
        }
        guard await refreshPublicAuthorIdentity(
            expectedUserID: expectedUserID
        ) else { return }
        guard !Task.isCancelled,
              isAccountBoundWorkLeaseCurrent(accountWorkLease) else {
            return
        }
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
        guard let attempt = activeAppleSignInAttempt,
              Self.shouldAcceptAppleSignInCallback(
                activeTransitionID: activeAuthTransition?.token.id,
                attemptTransitionID: attempt.transition.id,
                controllerMatches: controller === attempt.controller
              ) else {
            MerianLog.auth.error(
                "Ignored a stale Apple Sign-In callback that no longer owns the authentication transition."
            )
            return
        }
        activeAppleSignInAttempt = nil
        let transition = attempt.transition

        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finishAuthTransition(transition)
            return
        }

        let nonce = attempt.nonce
        guard let appleIDToken = appleIDCredential.identityToken else {
            MerianLog.auth.debug("Apple Sign-In: unable to fetch identity token.")
            finishAuthTransition(transition)
            return
        }
        guard let appleAuthorizationCode = appleIDCredential.authorizationCode else {
            MerianLog.auth.error("Apple Sign-In: unable to fetch the authorization code required for durable token revocation.")
            finishAuthTransition(transition)
            return
        }
        guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            MerianLog.auth.debug("Apple Sign-In: failed to serialize token string.")
            finishAuthTransition(transition)
            return
        }
        guard let authorizationCodeString = String(
            data: appleAuthorizationCode,
            encoding: .utf8
        ), !authorizationCodeString.isEmpty else {
            MerianLog.auth.error("Apple Sign-In: failed to serialize the authorization code required for durable token revocation.")
            finishAuthTransition(transition)
            return
        }
        let credentialRegistrationId = UUID()

        Task {
            defer { self.finishAuthTransition(transition) }
            let sourceSession = self.activeAuthTransition?.sourceSession
            var didInstallAppleSession = false
            do {
                let completion = try await self.finalizeOAuthLogin(
                    provider: .apple,
                    idToken: idTokenString,
                    accessToken: nil,
                    nonce: nonce,
                    transition: transition,
                    didMutateSession: {
                        didInstallAppleSession = true
                    }
                )
                _ = try await self.verifiedExpectedSession(for: transition)
                try await self.registerAppleRevocationCredential(
                    registrationId: credentialRegistrationId,
                    authorizationCode: authorizationCodeString,
                    identityToken: idTokenString,
                    expectedUserID: completion.session.user.id,
                    ownedBy: transition
                )
                let didPersistAppleMetadata = await updateAppleUserMetadataIfAvailable(
                    from: appleIDCredential.fullName,
                    expectedUserID: completion.session.user.id,
                    transition: transition
                )
                let session = try await verifiedExpectedSession(
                    for: transition
                )
                currentUser = session.user
                isAuthenticated = true
                _ = updateAuthTransition(transition, phase: .bindingPurchases)
                _ = await ensureTelemetryLinkedWhenSafe(
                    for: session.user,
                    ownedBy: transition
                )
                guard currentSessionMatchesAuthTransition(transition),
                      RevenueCatManager.shared.linkedAuthUserID
                        == session.user.id,
                      RevenueCatManager.shared.isIdentityReady else {
                    throw SupabaseAuthTransitionError.signOutSessionChanged
                }
                await EntitlementManager.shared.beginSession(
                    userID: session.user.id,
                    client: client,
                    authTransitionOwner: transition
                )
                _ = try await verifiedExpectedSession(for: transition)
                if didPersistAppleMetadata {
                    _ = await refreshPublicAuthorIdentity(
                        expectedUserID: session.user.id,
                        ownedBy: transition
                    )
                }
                _ = updateAuthTransition(transition, phase: .finalizing)
                _ = try await verifiedExpectedSession(for: transition)
                publishPublicAuthorIdentityChanged(
                    previousUserId: completion.previousUserId,
                    currentUserId: session.user.id.uuidString
                )
                KeychainManager.shared.set(true, forKey: KeychainKeys.hasAuthenticatedOAuth)
                MerianLog.auth.debug("Apple Sign-In complete.")
            } catch {
                if Self.shouldClearOAuthSessionAfterFailure(
                    observedSessionMutation: didInstallAppleSession,
                    sourceSession: sourceSession,
                    currentSession: self.transitionSession(
                        from: self.client.auth.currentSession?.user
                    )
                ) {
                    await self.clearLocalSessionAfterAuthFailure(
                        ownedBy: transition
                    )
                }
                MerianLog.auth.debug(
                    "Apple Sign-In failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
                )
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        guard let attempt = activeAppleSignInAttempt,
              Self.shouldAcceptAppleSignInCallback(
                activeTransitionID: activeAuthTransition?.token.id,
                attemptTransitionID: attempt.transition.id,
                controllerMatches: controller === attempt.controller
              ) else {
            return
        }
        activeAppleSignInAttempt = nil
        finishAuthTransition(attempt.transition)
        MerianLog.auth.debug(
            "Apple Sign-In failed before completion; kind=\(MerianLog.errorKind(error), privacy: .public)"
        )
    }
}

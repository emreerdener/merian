import Foundation
import Observation
import os
import Supabase

// MARK: - Supabase Manager

/// Manages the global Supabase connection, auth state, and OAuth sign-in flows.
@MainActor
@Observable final class SupabaseManager: NSObject {
    // MARK: - Singleton Architecture
    static let shared = SupabaseManager()

    // MARK: - Client
    let client: SupabaseClient
    private let appleOAuthCredentialRegistrationService:
        AppleOAuthCredentialRegistrationService
    private let authSessionBootstrapLiveService:
        AuthSessionBootstrapLiveService
    private let supabaseAuthSessionService: SupabaseAuthSessionService
    private let purchasePrincipalResolver: PurchasePrincipalResolver
    private let purchaseIdentitySessionLiveService:
        PurchaseIdentitySessionLiveService
    private let ghostProfileMergeStore: GhostProfileMergeStore
    private let ghostProfileMergeRemoteService:
        GhostProfileMergeRemoteService
    private let purchaseIdentityHandoffJournal:
        PurchaseIdentityHandoffAuthJournal
    private let legacyPurchaseHandoffRemoteService:
        LegacyPurchaseHandoffRemoteService
    @ObservationIgnored private let authRuntimeState = AuthRuntimeState()

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

    var activeAuthTransition: AuthTransitionState? {
        authRuntimeState.activeTransition
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
            && AuthTransitionPolicy.allowsAuthenticatedRequest(
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
        return authRuntimeState.beginAccountWork(
            session: transitionSession(from: sdkUser)!
        )
    }

    func isAccountBoundWorkLeaseCurrent(
        _ lease: AccountBoundWorkLease
    ) -> Bool {
        authRuntimeState.accountWorkLeaseIsCurrent(
            lease,
            publishedSession: transitionSession(from: currentUser),
            sdkSession: transitionSession(
                from: client.auth.currentSession?.user
            )
        )
    }

    func finishAccountBoundWork(_ lease: AccountBoundWorkLease) {
        authRuntimeState.finishAccountWork(lease)
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

    // MARK: - Session Deduplication
    /// Invalidates suspended Auth-session work whenever the SDK emits a new
    /// lifecycle event, including a same-user refresh.
    private var authSessionGeneration: UInt64 {
        authRuntimeState.sessionGeneration
    }

    /// Owns the live Supabase Auth stream task and deferred current-state replay.
    @ObservationIgnored private let authSessionLifecycleLiveProvider:
        AuthSessionLifecycleLiveProvider
    /// Retains listener-admitted historical synchronization through teardown.
    @ObservationIgnored private let authHistoricalSessionSyncLiveService:
        AuthHistoricalSessionSyncLiveService
    /// Owns existing-session resolution and anonymous-bootstrap single-flight.
    @ObservationIgnored private let authSessionBootstrapCoordinator =
        AuthSessionBootstrapCoordinator()
    /// Owns local sign-out task lifetime and sequencing after transition
    /// admission closes authenticated request creation.
    @ObservationIgnored private let authLocalSignOutCoordinator =
        AuthLocalSignOutCoordinator()
    /// Owns durable preparation and keyed completion for Ghost merges.
    @ObservationIgnored private let ghostProfileMergeCoordinator =
        GhostProfileMergeCoordinator()
    /// Owns keyed single-flight completion for a durable signed-out purchase
    /// handoff observed by interactive and restored-session paths.
    @ObservationIgnored private let purchaseIdentityHandoffCoordinator =
        PurchaseIdentityHandoffCoordinator()
    @ObservationIgnored private let purchaseIdentitySessionCoordinator =
        PurchaseIdentitySessionCoordinator()
    /// Owns the keyed restored-session public-author identity refresh task.
    @ObservationIgnored private let publicAuthorIdentityRefreshCoordinator =
        PublicAuthorIdentityRefreshCoordinator()
    /// Owns generation-fenced Apple credential-revocation revalidation.
    @ObservationIgnored private let appleCredentialRevocationCoordinator =
        AppleCredentialRevocationCoordinator()
    /// Owns the Apple framework notification and credential-state lookup.
    @ObservationIgnored private let appleCredentialRevocationLiveProvider =
        AppleCredentialRevocationLiveProvider()
    /// Owns provider-presentation admission and Apple completion-task lifetime.
    @ObservationIgnored private let oauthProviderSignInCoordinator =
        OAuthProviderSignInCoordinator()
    /// Owns the Google SDK presentation and provider-value mapping surface.
    @ObservationIgnored private let googleOAuthAuthorizationLiveProvider =
        GoogleOAuthAuthorizationLiveProvider()
    /// Owns Apple authorization-controller retention and delegate callbacks.
    @ObservationIgnored private let appleOAuthAuthorizationLiveProvider =
        AppleOAuthAuthorizationLiveProvider()
    /// Serializes purchase-safe transitions from a linked user to a fresh
    /// anonymous identity.
    @ObservationIgnored private let userSignOutSingleFlight =
        AuthTransitionSingleFlight()
    @ObservationIgnored private weak var appRouteSessionController: (any AppRouteSessionControlling)?
    @ObservationIgnored private weak var milestoneToastSessionController: (any MilestoneToastSessionControlling)?
    var isSigningOut: Bool {
        authRuntimeState.isSigningOut
    }

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
        self.authSessionLifecycleLiveProvider = .live(client: client)
        self.authHistoricalSessionSyncLiveService =
            AuthHistoricalSessionSyncLiveService(dependencies: .live)
        self.authSessionBootstrapLiveService = .live(client: client)
        self.appleOAuthCredentialRegistrationService = .live(client: client)
        self.supabaseAuthSessionService = .live(client: client)
        let purchasePrincipalResolver = PurchasePrincipalResolver(
            client: client
        )
        self.purchasePrincipalResolver = purchasePrincipalResolver
        let legacyPurchaseIdentityProfileService =
            LegacyPurchaseIdentityProfileService.live(client: client)
        self.purchaseIdentitySessionLiveService = .live(
            client: client,
            resolver: purchasePrincipalResolver,
            legacyProfileService: legacyPurchaseIdentityProfileService
        )
        let keychain = KeychainManager.shared
        self.ghostProfileMergeStore = GhostProfileMergeStore(
            dependencies: .live(keychain: keychain)
        )
        self.ghostProfileMergeRemoteService = .live(client: client)
        self.purchaseIdentityHandoffJournal =
            PurchaseIdentityHandoffAuthJournal(
                store: PurchaseIdentityHandoffStore(
                    dependencies: .live(keychain: keychain)
                )
            )
        self.legacyPurchaseHandoffRemoteService = .live(
            client: client
        )

        super.init()

        // Remove the retired presentation-only logout marker. Linked sessions
        // must restore as linked accounts; ordinary logout creates a new
        // anonymous session instead of masking an authenticated one.
        keychain.removeObject(forKey: KeychainKeys.legacyGhostModeUserID)
        do {
            try purchaseIdentitySourceHandoffCoordinator()
                .loadAndPublishPendingState()
        } catch {
            // Keychain uncertainty is not evidence that a purchase handoff is
            // absent. Keep provider mutations fail-closed until it is resolved.
            publishPurchaseIdentityHandoffPending(true)
        }
        self.authSessionLifecycleLiveProvider.start(
            dependencies: authSessionLifecycleLiveDependencies()
        )
        self.appleCredentialRevocationLiveProvider.startObserving { [weak self] in
            guard let self else { return }
            appleCredentialRevocationCoordinator
                .handleRevocationNotification(
                    dependencies: appleCredentialRevocationDependencies()
                )
        }
    }

    isolated deinit {
        authSessionLifecycleLiveProvider.cancel()
        authHistoricalSessionSyncLiveService.cancel()
        authSessionBootstrapCoordinator.cancel()
        ghostProfileMergeCoordinator.cancel()
        purchaseIdentityHandoffCoordinator.cancel()
        purchaseIdentitySessionCoordinator.cancelResolution()
        authLocalSignOutCoordinator.cancel()
        publicAuthorIdentityRefreshCoordinator.cancel()
        appleCredentialRevocationCoordinator.cancel()
        appleCredentialRevocationLiveProvider.stopObserving()
        oauthProviderSignInCoordinator.cancel()
        appleOAuthAuthorizationLiveProvider.cancel()
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

    private func hasCurrentPublishedSession(
        _ user: User,
        expectedAuthGeneration: UInt64? = nil,
        ownedBy transition: AuthTransitionToken? = nil
    ) -> Bool {
        guard !Task.isCancelled,
              expectedAuthGeneration.map({ $0 == authSessionGeneration })
                ?? true,
              currentUser?.id == user.id,
              currentUser?.isAnonymous == user.isAnonymous,
              isAuthenticated,
              let sdkSession = client.auth.currentSession,
              !sdkSession.isExpired,
              sdkSession.user.id == user.id,
              sdkSession.user.isAnonymous == user.isAnonymous else {
            return false
        }
        if let transition {
            return currentSessionMatchesAuthTransition(transition)
        }
        return activeAuthTransition == nil
    }

    private func beginAuthTransition(
        _ kind: AuthTransitionKind
    ) -> AuthTransitionToken? {
        if let deletionRecoveryState =
            AccountDeletionLocalCleanupStore.state() {
            guard AuthTransitionPolicy
                .allowsAuthTransitionDuringAccountDeletionRecovery(
                recoveryState: deletionRecoveryState,
                kind: kind
            ) else { return nil }
        }
        let sourceUser = client.auth.currentSession?.user ?? currentUser
        guard let token = authRuntimeState.beginTransition(
            kind: kind,
            sourceSession: transitionSession(from: sourceUser)
        ) else {
            return nil
        }
        authSessionLifecycleLiveProvider.authTransitionWillBegin()
        appleCredentialRevocationCoordinator.authContextWillChange()
        AppDIContainer.shared.inferenceEngine.beginAuthTransitionWriteFence()
        _ = authRuntimeState.recordAnalyticsGeneration(
            ConsentManager.shared.beginAnalyticsAccountTransition(),
            for: token
        )
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

    func ownsAuthTransition(_ token: AuthTransitionToken) -> Bool {
        authRuntimeState.ownsTransition(token)
    }

    private func authTransitionAllows(
        _ token: AuthTransitionToken?
    ) -> Bool {
        authRuntimeState.transitionAllows(token)
    }

    @discardableResult
    private func updateAuthTransition(
        _ token: AuthTransitionToken,
        phase: AuthTransitionPhase
    ) -> Bool {
        authRuntimeState.updateTransition(token, phase: phase)
    }

    @discardableResult
    private func adoptAuthTransitionSession(
        _ session: User?,
        for token: AuthTransitionToken
    ) -> Bool {
        authRuntimeState.adoptTransitionSession(
            transitionSession(from: session),
            for: token
        )
    }

    private func finishAuthTransition(_ token: AuthTransitionToken) {
        guard let completion = authRuntimeState.finishTransition(token) else {
            return
        }
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
        if let analyticsGeneration = completion.analyticsGeneration {
            _ = ConsentManager.shared.resolveAnalyticsAccountTransition(
                generation: analyticsGeneration,
                userId: finalUserID
            )
        }
        if let finalUser = currentUser,
           finalUser.id == finalUserID {
            schedulePublicAuthorIdentityRefreshIfNeeded(for: finalUser)
        }
        guard authSessionLifecycleLiveProvider
            .scheduleCurrentSessionReconciliation(
                authGeneration: authSessionGeneration,
                dependencies: authSessionLifecycleLiveDependencies()
            ) else {
            appleCredentialRevocationCoordinator.resumeDeferredIfNeeded(
                dependencies: appleCredentialRevocationDependencies()
            )
            return
        }
    }

    private func analyticsGeneration(
        for transition: AuthTransitionToken
    ) -> UInt {
        guard ownsAuthTransition(transition),
              let generation = authRuntimeState.analyticsGeneration(
                  for: transition
              ) else {
            // This path is defensive: a valid owner always receives its
            // generation atomically in `beginAuthTransition`.
            return 0
        }
        return generation
    }

    func currentSessionMatchesAuthTransition(
        _ token: AuthTransitionToken
    ) -> Bool {
        authRuntimeState.transitionMatchesCurrentSession(
            transitionSession(from: client.auth.currentSession?.user),
            token: token
        )
    }

    private func awaitAccountBoundWorkQuiescenceForAuthTransition() async
        -> Bool {
        // Closing the Auth transition happens synchronously before this drain,
        // so no new ordinary lease or collection mutation can enter. Existing
        // work completes against the preserved source session.
        await ConsentManager.shared
            .cancelAndAwaitAccountBoundWorkForAuthTransition()
        await AppDIContainer.shared.inferenceEngine
            .awaitAuthTransitionWriteQuiescence()
        await OfflineQueueManager.shared
            .cancelAndAwaitInferenceFundingSettlementForAuthTransition()
        guard await OfflineQueueManager.shared
            .quiesceBackgroundAccountWorkForAuthTransition(
                sourceUserID:
                    authRuntimeState.activeSourceUserID
            ) else {
            MerianLog.auth.error(
                "Authentication transition stopped because background account work could not be durably paused."
            )
            return false
        }
        await OfflineQueueManager.shared
            .awaitCollectionSyncQuiescenceForAuthTransition()
        await authRuntimeState.awaitAccountWorkDrain()
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
              authRuntimeState.transitionMatchesCurrentSession(
                transitionSession(from: session.user),
                token: token
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
        guard let expected = authRuntimeState.activeExpectedSession
        else {
            guard ownsAuthTransition(token),
                  client.auth.currentSession == nil,
                  authRuntimeState.transitionMatchesCurrentSession(
                    nil,
                    token: token
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

    private func appleCredentialRevocationIdentity()
        -> AppleCredentialRevocationIdentity? {
        guard isAuthenticated,
              let user = currentUser,
              let sdkSession = client.auth.currentSession,
              !sdkSession.isExpired,
              sdkSession.user.id == user.id,
              sdkSession.user.isAnonymous == user.isAnonymous,
              let session = transitionSession(from: user),
              let providerSubject = user.identities?.first(where: {
                  $0.provider == "apple" && !$0.id.isEmpty
              })?.id else {
            return nil
        }
        return AppleCredentialRevocationIdentity(
            session: session,
            providerSubject: providerSubject
        )
    }

    private func appleCredentialRevocationDependencies()
        -> AppleCredentialRevocationDependencies {
        let liveProvider = appleCredentialRevocationLiveProvider
        return AppleCredentialRevocationDependencies(
            session: .init(
                hasActiveTransition: { [weak self] in
                    self?.isAuthTransitionInProgress ?? false
                },
                currentIdentity: { [weak self] in
                    self?.appleCredentialRevocationIdentity()
                }
            ),
            operations: .init(
                lookupCredentialState: { providerSubject in
                    await liveProvider
                        .lookupCredentialState(
                            forProviderSubject: providerSubject
                        )
                },
                clearLocalSessionIfCurrent: { [weak self] expectedIdentity in
                    guard let self,
                          !self.isAuthTransitionInProgress,
                          self.appleCredentialRevocationIdentity()
                            == expectedIdentity else {
                        return .contextChanged
                    }
                    switch await self.clearLocalSessionAfterAuthFailure() {
                    case .cleared:
                        return .cleared
                    case .rejected, .blockedByPurchaseHandoff:
                        return .deferred
                    }
                }
            ),
            diagnose: { diagnostic in
                AppleCredentialRevocationLiveDiagnostics.report(
                    diagnostic
                )
            }
        )
    }

    private func authSessionLifecycleLiveDependencies()
        -> AuthSessionLifecycleLiveDependencies {
        AuthSessionLifecycleLiveDependencies(
            advanceAuthGeneration: { [weak self] in
                self?.authRuntimeState.advanceSessionGeneration()
            },
            authContextWillChange: { [weak self] in
                self?.appleCredentialRevocationCoordinator
                    .authContextWillChange()
            },
            observeAuthSession: { [weak self] session in
                self?.authRuntimeState.observeAuthEvent(session: session)
            },
            accountDeletionCleanupPending: {
                AccountDeletionLocalCleanupStore.isPending()
            },
            hasActiveTransition: { [weak self] in
                self?.activeAuthTransition != nil
            },
            reconciliationContextIsCurrent: { [weak self] generation in
                guard let self else { return false }
                return activeAuthTransition == nil
                    && authSessionGeneration == generation
            },
            makeLifecycleDependencies: { [weak self] sdkUser in
                self?.authSessionLifecycleDependencies(sdkUser: sdkUser)
            },
            resumeDeferredCredentialRevocation: { [weak self] in
                guard let self else { return }
                appleCredentialRevocationCoordinator.resumeDeferredIfNeeded(
                    dependencies: appleCredentialRevocationDependencies()
                )
            }
        )
    }

    private func authSessionLifecycleDependencies(sdkUser: User?)
        -> AuthSessionLifecycleDependencies {
        AuthSessionLifecycleDependencies(
            state: AuthSessionLifecycleStateBoundary(
                accountDeletionCleanupPending: {
                    AccountDeletionLocalCleanupStore.isPending()
                },
                hasActiveTransition: { [weak self] in
                    self?.activeAuthTransition != nil
                },
                isSigningOut: { [weak self] in
                    self?.isSigningOut ?? true
                },
                isUserSignOutTransitionInProgress: { [weak self] in
                    self?.isUserSignOutTransitionInProgress ?? false
                },
                publishedSession: { [weak self] in
                    guard let self else { return nil }
                    return transitionSession(from: currentUser)
                },
                publishSDKSession: { [weak self] session in
                    guard let self else { return false }
                    guard let sdkUser,
                          transitionSession(from: sdkUser) == session,
                          let currentSDKSession = client.auth.currentSession,
                          !currentSDKSession.isExpired,
                          transitionSession(from: currentSDKSession.user)
                            == session else {
                        return false
                    }
                    currentUser = sdkUser
                    isAuthenticated = true
                    return true
                },
                clearPublishedSession: { [weak self] in
                    self?.currentUser = nil
                    self?.isAuthenticated = false
                },
                clearPurchasePrincipalBinding: { [weak self] in
                    self?.purchaseIdentitySessionCoordinator.clearBinding()
                },
                clearLinkedUser: { [weak self] in
                    self?.purchaseIdentitySessionCoordinator.clearLinkedUser()
                },
                beginPurchaseIdentityResolution: {
                    RevenueCatManager.shared.beginPurchaseIdentityResolution()
                },
                beginAccountSession: { [weak self] userID, origin in
                    self?.beginAccountSession(userID: userID, origin: origin)
                },
                observeConsentSession: { userID in
                    ConsentManager.shared.observeSession(userId: userID)
                },
                schedulePublicAuthorIdentityRefresh: { [weak self] session in
                    guard let self else { return }
                    guard let sdkUser,
                          transitionSession(from: sdkUser) == session else {
                        return
                    }
                    schedulePublicAuthorIdentityRefreshIfNeeded(for: sdkUser)
                },
                clearPublicAuthorIdentityRefreshMarker: { [weak self] in
                    self?.publicAuthorIdentityRefreshCoordinator
                        .clearCompletedUser()
                },
                cancelPublicAuthorIdentityRefresh: { [weak self] in
                    self?.publicAuthorIdentityRefreshCoordinator.cancel()
                },
                cancelAppleCredentialRevocation: { [weak self] in
                    self?.appleCredentialRevocationCoordinator.cancel()
                },
                cancelGhostProfileMerge: { [weak self] in
                    self?.ghostProfileMergeCoordinator.cancel()
                },
                isCurrentPublishedSession: { [weak self] session, generation in
                    guard let self else { return false }
                    guard let sdkUser,
                          transitionSession(from: sdkUser) == session else {
                        return false
                    }
                    return hasCurrentPublishedSession(
                        sdkUser,
                        expectedAuthGeneration: generation
                    )
                },
                isCurrentLifecycleSession: { [weak self] session, generation in
                    guard let self else { return false }
                    guard !Task.isCancelled,
                          generation == authSessionGeneration,
                          activeAuthTransition == nil else {
                        return false
                    }
                    let sdkSession = client.auth.currentSession
                    guard transitionSession(from: sdkSession?.user)
                        == session else {
                        return false
                    }
                    if let sdkSession, sdkSession.isExpired {
                        return false
                    }
                    return transitionSession(from: currentUser) == session
                        && isAuthenticated == (session != nil)
                }
            ),
            durability: AuthSessionLifecycleDurabilityBoundary(
                hasPendingGhostProfileMerge: { [weak self] in
                    guard let self else { return true }
                    return try ghostProfileMergeCoordinator.hasPendingHandoffs(
                        dependencies: ghostProfileMergeDependencies()
                    )
                },
                setAnalyticsSuppressedForGhostHandoff: { isSuppressed in
                    ConsentManager.shared.setAnalyticsSuppressedForGhostHandoff(
                        isSuppressed
                    )
                },
                hasPendingPurchaseIdentityHandoff: { [weak self] in
                    guard let self else { return true }
                    return try purchaseIdentitySourceHandoffCoordinator()
                        .hasPendingHandoff()
                },
                setPurchaseIdentityHandoffPending: { [weak self] isPending in
                    self?.publishPurchaseIdentityHandoffPending(isPending)
                }
            ),
            identity: AuthSessionLifecycleIdentityBoundary(
                isTestExecution: { TestExecutionCoordinator.isRunningTests },
                isPurchaseIdentityHandoffPending: {
                    RevenueCatManager.shared.isPurchaseIdentityHandoffPending
                },
                completePendingPurchaseIdentityHandoff: { [weak self] session, generation in
                    guard let self else { return }
                    _ = await completePendingSignOutPurchaseHandoffIfNeeded(
                        expectedDestinationUserId:
                            session.userID.uuidString,
                        expectedAuthGeneration: generation
                    )
                },
                ensureTelemetryLinked: { [weak self] session in
                    guard let self else { return false }
                    guard let sdkUser,
                          transitionSession(from: sdkUser) == session else {
                        return false
                    }
                    return await ensurePurchaseIdentityReady(for: sdkUser)
                },
                abandonRestoredSourceHandoffs: { [weak self] session in
                    guard let self else { return }
                    let coordinator =
                        purchaseIdentitySourceHandoffCoordinator()
                    await coordinator
                        .abandonStableRotationIfSourceRestored(
                            sourceUserID: session.userID
                        )
                    await coordinator
                        .abandonLegacyHandoffIfSourceRestored(
                            sourceUserID: session.userID.uuidString
                        )
                },
                clearEntitlementSession: {
                    EntitlementManager.shared.handleSignOut()
                },
                beginEntitlementSession: { [weak self] session in
                    guard let self else { return }
                    await EntitlementManager.shared.beginSession(
                        userID: session.userID,
                        client: client
                    )
                },
                handleSupabaseSignOut: {
                    await RevenueCatManager.shared.handleSupabaseSignOut()
                },
                scheduleHistoricalSync: { [weak self] session, generation in
                    guard let self else { return }
                    guard let sdkUser,
                          transitionSession(from: sdkUser) == session else {
                        return
                    }
                    authHistoricalSessionSyncLiveService.schedule { [weak self] in
                        self?.hasCurrentPublishedSession(
                            sdkUser,
                            expectedAuthGeneration: generation
                        ) ?? false
                    }
                }
            ),
            diagnose: { diagnostic, error in
                AuthSessionLifecycleLiveDiagnostics.report(
                    diagnostic,
                    error: error
                )
            }
        )
    }

    private func beginAccountSession(
        userID: UUID?, origin: AuthSessionLifecycleOrigin
    ) {
        let routeOrigin: AppRouteAccountSessionOrigin = switch origin {
        case .initialRestoration: .initialRestoration
        case .runtimeTransition: .runtimeTransition
        }
        appRouteSessionController?.beginAccountSession(
            accountID: userID?.uuidString,
            origin: routeOrigin,
            now: Date()
        )
        milestoneToastSessionController?.beginAccountSession(
            accountID: userID?.uuidString,
            origin: routeOrigin,
            now: Date()
        )
    }

    /// An already-issued v1 sign-out proof is bound to the destination Auth
    /// UUID's RevenueCat customer. Finish that immutable compatibility
    /// contract before allowing a concurrent stable-principal rollout to
    /// adopt the installation. Otherwise receipt sync could target the new
    /// principal while server completion still verifies the legacy UUID.
    private func linkLegacyPurchaseIdentityForSignOutHandoff(
        user: User
    ) async throws {
        await purchaseIdentitySessionLiveService
            .linkLegacyProviderIdentity(
                for: purchaseIdentityLegacySessionProfile(for: user)
            )
        guard purchaseIdentitySessionLiveService.legacyProviderIsReady(
            for: user.id
        ) else {
            throw SupabaseAuthTransitionError
                .signOutPurchaseContinuityPending
        }
        purchaseIdentitySessionCoordinator.recordBinding(.legacyFallback)
    }

    private func purchaseIdentitySessionContext(
        for user: User,
        authGeneration: UInt64? = nil
    ) -> PurchaseIdentitySessionContext {
        PurchaseIdentitySessionContext(
            userID: user.id,
            isAnonymous: user.isAnonymous,
            authGeneration: authGeneration ?? authSessionGeneration
        )
    }

    private func purchaseIdentitySessionSnapshot(
        for user: User,
        isExpired: Bool = false
    ) -> PurchaseIdentitySessionSnapshot {
        purchaseIdentitySessionLiveService.snapshot(
            for: purchaseIdentityLegacySessionProfile(for: user),
            isExpired: isExpired
        )
    }

    private func purchaseIdentityLegacySessionProfile(
        for user: User
    ) -> PurchaseIdentityLegacySessionProfile {
        PurchaseIdentityLegacySessionProfile(
            userID: user.id,
            isAnonymous: user.isAnonymous,
            email: user.email,
            fullName: user.userMetadata["full_name"]?.stringValue,
            name: user.userMetadata["name"]?.stringValue,
            avatarURL: user.userMetadata["avatar_url"]?.stringValue,
            pictureURL: user.userMetadata["picture"]?.stringValue
        )
    }

    @discardableResult
    private func ensurePurchaseIdentityReady(
        for user: User,
        ownedBy transition: AuthTransitionToken? = nil
    ) async -> Bool {
        let accountWorkLease: AccountBoundWorkLease?
        if let transition {
            guard currentSessionMatchesAuthTransition(transition),
                  transitionSession(from: client.auth.currentSession?.user) ==
                    transitionSession(from: user) else {
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

        let context = purchaseIdentitySessionContext(for: user)
        let snapshot = purchaseIdentitySessionSnapshot(for: user)
        return await purchaseIdentitySessionCoordinator.ensureIdentity(
            for: snapshot,
            context: context,
            isAdmissionCurrent: { [weak self] in
                guard let self else { return false }
                if let transition {
                    return self.currentSessionMatchesAuthTransition(
                        transition
                    ) && self.transitionSession(
                        from: self.client.auth.currentSession?.user
                    ) == self.transitionSession(from: user)
                }
                return accountWorkLease.map(
                    self.isAccountBoundWorkLeaseCurrent
                ) ?? false
            },
            dependencies: purchaseIdentitySessionDependencies()
        )
    }

    /// Repairs a fail-closed purchase-identity session when the app returns to
    /// the foreground. Auth-state delivery normally owns this work, but a
    /// transient resolver, account-cleanup, Keychain, or provider failure may
    /// finish without another SDK event. Retry only the exact current Auth
    /// generation and durable capability/handoff; never rotate either one.
    @discardableResult
    func retryPurchaseIdentityReadinessIfNeeded() async -> Bool {
        await PurchaseIdentityReadinessCoordinator(
            sessionCoordinator: purchaseIdentitySessionCoordinator,
            dependencies: purchaseIdentitySessionDependencies()
        ).repair()
    }

    private func purchaseIdentitySessionDependencies()
        -> PurchaseIdentitySessionDependencies {
        let state = PurchaseIdentitySessionStateBoundary(
            isTestExecution: {
                TestExecutionCoordinator.isRunningTests
            },
            accountDeletionCleanupPending: {
                AccountDeletionLocalCleanupStore.isPending()
            },
            isSigningOut: { [weak self] in
                self?.isSigningOut ?? true
            },
            isAuthenticated: { [weak self] in
                self?.isAuthenticated ?? false
            },
            isUserSignOutTransitionInProgress: { [weak self] in
                self?.isUserSignOutTransitionInProgress ?? true
            },
            currentPublishedSession: { [weak self] in
                guard let self, let user = self.currentUser else {
                    return nil
                }
                return self.purchaseIdentitySessionContext(for: user)
            },
            isCurrentPublishedSession: { [weak self] context in
                guard let self, let user = self.currentUser else {
                    return false
                }
                return user.id == context.userID
                    && user.isAnonymous == context.isAnonymous
                    && self.authSessionGeneration == context.authGeneration
            },
            beginAccountWork: { [weak self] userID in
                guard let self,
                      let lease = try? self.beginUnownedAccountBoundWork(
                          expectedUserID: userID
                      ) else {
                    return nil
                }
                return PurchaseIdentityAccountWorkLease(
                    isCurrent: { [weak self] in
                        self?.isAccountBoundWorkLeaseCurrent(lease) ?? false
                    },
                    finish: { [weak self] in
                        self?.finishAccountBoundWork(lease)
                    }
                )
            },
            loadSDKSession: { [weak self] in
                guard let self else {
                    throw SupabaseAuthTransitionError
                        .signOutSessionChanged
                }
                let session = try await self.client.auth.session
                return self.purchaseIdentitySessionSnapshot(
                    for: session.user,
                    isExpired: session.isExpired
                )
            }
        )
        let handoff = PurchaseIdentitySessionHandoffBoundary(
            loadPending: { [weak self] in
                guard let self else {
                    throw SupabaseAuthTransitionError
                        .signOutSessionChanged
                }
                return try self
                    .purchaseIdentitySourceHandoffCoordinator()
                    .hasPendingHandoff()
            },
            setPending: { [weak self] pending in
                self?.publishPurchaseIdentityHandoffPending(pending)
            },
            completePending: { [weak self] context in
                guard let self else { return false }
                return await self
                    .completePendingSignOutPurchaseHandoffIfNeeded(
                        expectedDestinationUserId:
                            context.userID.uuidString,
                        expectedAuthGeneration: context.authGeneration
                    )
            },
            abandonRestoredSource: { [weak self] context in
                guard let self else { return }
                let coordinator = self
                    .purchaseIdentitySourceHandoffCoordinator()
                await coordinator
                    .abandonStableRotationIfSourceRestored(
                        sourceUserID: context.userID
                    )
                await coordinator
                    .abandonLegacyHandoffIfSourceRestored(
                        sourceUserID: context.userID.uuidString
                    )
            }
        )
        return purchaseIdentitySessionLiveService.dependencies(
            state: state,
            handoff: handoff
        )
    }

    // MARK: - Auth Session Bootstrap

    /// Resolves the current Auth session or creates an anonymous session for a
    /// signed-out user. Network and expiry failures preserve any existing identity.
    @discardableResult
    func initializeGhostSession(
        ownedBy transition: AuthTransitionToken? = nil
    ) async -> User? {
        guard let identity = await authSessionBootstrapCoordinator.initialize(
            ownedBy: transition,
            dependencies: authSessionBootstrapDependencies()
        ), let session = authSessionBootstrapLiveService.currentSession(),
           session.identity == identity else {
            return nil
        }
        return session.user
    }

    private func authSessionBootstrapDependencies()
        -> AuthSessionBootstrapDependencies {
        AuthSessionBootstrapDependencies(
            state: AuthSessionBootstrapStateBoundary(
                isTestExecution: {
                    TestExecutionCoordinator.isRunningTests
                },
                isAccountDeletionCleanupPending: {
                    AccountDeletionLocalCleanupStore.isPending()
                },
                isAuthenticated: { [self] in isAuthenticated },
                currentPublishedSession: { [self] in
                    transitionSession(from: currentUser)
                },
                awaitSignOutCompletion: { [self] in
                    await authLocalSignOutCoordinator.waitForCompletion()
                }
            ),
            transition: AuthSessionBootstrapTransitionBoundary(
                activeTransition: { [self] in
                    activeAuthTransition?.token
                },
                beginAnonymousBootstrap: { [self] in
                    beginAuthTransition(.anonymousBootstrap)
                },
                allows: { [self] transition in
                    authTransitionAllows(transition)
                },
                adopt: { [self] session, transition in
                    guard let current = authSessionBootstrapLiveService
                        .currentSession(),
                        current.identity == session else {
                        return false
                    }
                    return adoptAuthTransitionSession(
                        current.user,
                        for: transition
                    )
                },
                finish: { [self] transition in
                    finishAuthTransition(transition)
                },
                awaitAccountWorkQuiescence: { [self] in
                    await awaitAccountBoundWorkQuiescenceForAuthTransition()
                }
            ),
            work: AuthSessionBootstrapWorkBoundary(
                beginUnownedAccountWork: { [self] userID in
                    try? beginUnownedAccountBoundWork(
                        expectedUserID: userID
                    )
                },
                isAccountWorkCurrent: { [self] lease in
                    isAccountBoundWorkLeaseCurrent(lease)
                },
                finishAccountWork: { [self] lease in
                    finishAccountBoundWork(lease)
                }
            ),
            operations: AuthSessionBootstrapOperationBoundary(
                currentSDKSession: { [self] in
                    authSessionBootstrapLiveService.currentSession().map(
                        authSessionBootstrapSnapshot
                    )
                },
                loadSDKSession: { [self] in
                    authSessionBootstrapSnapshot(
                        try await authSessionBootstrapLiveService.loadSession()
                    )
                },
                createAnonymousSession: { [self] in
                    authSessionBootstrapSnapshot(
                        try await authSessionBootstrapLiveService
                            .createAnonymousSession()
                    )
                },
                isSessionMissingError: { [self] error in
                    authSessionBootstrapLiveService
                        .isSessionMissingError(error)
                }
            ),
            diagnose: { diagnostic, error in
                AuthSessionBootstrapLiveDiagnostics.report(
                    diagnostic,
                    error: error
                )
            }
        )
    }

    private func authSessionBootstrapSnapshot(
        _ session: AuthSessionBootstrapLiveSession
    ) -> AuthSessionBootstrapSnapshot {
        let user = session.user
        return AuthSessionBootstrapSnapshot(
            identity: session.identity,
            isExpired: session.isExpired,
            publish: { [self] in
                currentUser = user
                isAuthenticated = true
            },
            schedulePublicAuthorIdentityRefresh: { [self] in
                schedulePublicAuthorIdentityRefreshIfNeeded(for: user)
            },
            ensurePurchaseIdentityReady: { [self] transition in
                _ = await ensurePurchaseIdentityReady(
                    for: user,
                    ownedBy: transition
                )
            },
            isCurrentPublishedSession: { [self] transition in
                hasCurrentPublishedSession(
                    user,
                    ownedBy: transition
                )
            }
        )
    }

    // MARK: - Session Utilities

    func signOut() async {
        guard let transition = beginAuthTransition(.recovery) else {
            await authLocalSignOutCoordinator.waitForCompletion()
            return
        }
        defer { finishAuthTransition(transition) }
        await performLocalSignOut(
            ownedBy: transition,
            performRemoteSignOut: { [supabaseAuthSessionService] in
                try await supabaseAuthSessionService.signOutLocal()
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
        try await AccountDeletionCoordinator(
            dependencies: accountDeletionDependencies()
        ).deleteCurrentAccount(
            prepareDeletionV2: prepareDeletionV2,
            commitDeletionV2: commitDeletionV2,
            recoverDeletionV2: recoverDeletionV2,
            requestDeletion: requestDeletion,
            acknowledgeDeletion: acknowledgeDeletion,
            acknowledgeDeletionV2: acknowledgeDeletionV2,
            recoveryCapabilityStore: recoveryCapabilityStore,
            recordManualProviderRevocation: recordManualProviderRevocation,
            purgeLocalData: purgeLocalData
        )
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
        await AccountDeletionRecoveryCoordinator(
            dependencies: accountDeletionDependencies()
        ).resumePendingLocalCleanup(
            requestDeletion: requestDeletion,
            recoverDeletion: recoverDeletion,
            recoverDeletionV2: recoverDeletionV2,
            acknowledgeDeletionV2: acknowledgeDeletionV2,
            recoveryCapabilityStore: recoveryCapabilityStore,
            recordManualProviderRevocation: recordManualProviderRevocation,
            purgeLocalData: purgeLocalData
        )
    }

    private func accountDeletionDependencies()
        -> AccountDeletionCoordinationDependencies {
        let localState = AccountDeletionLocalStateBoundary(
            state: {
                AccountDeletionLocalCleanupStore.state()
            },
            isPending: {
                AccountDeletionLocalCleanupStore.isPending()
            },
            recordCapabilityPreparationPending: {
                AccountDeletionLocalCleanupStore
                    .recordCapabilityPreparationPending()
            },
            recordCapabilityPreparedPending: {
                AccountDeletionLocalCleanupStore
                    .recordCapabilityPreparedPending()
            },
            recordIntakePending: {
                AccountDeletionLocalCleanupStore.recordIntakePending()
            },
            recordCleanupPending: {
                AccountDeletionLocalCleanupStore.recordCleanupPending()
            },
            recordCapabilityRetirementPending: {
                AccountDeletionLocalCleanupStore
                    .recordCapabilityRetirementPending()
            },
            recordCapabilityRejectionRetirementPending: {
                AccountDeletionLocalCleanupStore
                    .recordCapabilityRejectionRetirementPending()
            },
            resolve: {
                AccountDeletionLocalCleanupStore.resolve()
            }
        )
        let session = AccountDeletionSessionBoundary(
            beginTransition: { kind in
                self.beginAuthTransition(kind)
            },
            finishTransition: { transition in
                self.finishAuthTransition(transition)
            },
            updateTransition: { transition, phase in
                _ = self.updateAuthTransition(transition, phase: phase)
            },
            ownsTransition: { transition in
                self.ownsAuthTransition(transition)
            },
            verifyExpectedSession: { transition in
                _ = try await self.verifiedExpectedSession(for: transition)
            },
            currentSessionMatchesTransition: { transition in
                self.currentSessionMatchesAuthTransition(transition)
            },
            sourceSession: { transition in
                guard self.ownsAuthTransition(transition),
                      self.activeAuthTransition?.token == transition else {
                    return nil
                }
                return self.activeAuthTransition?.sourceSession
            },
            loadCachedSession: {
                let session = try await self.client.auth.session
                return AccountDeletionCachedSession(
                    identity: AuthTransitionSession(
                        userID: session.user.id,
                        isAnonymous: session.user.isAnonymous
                    ),
                    isExpired: session.isExpired
                )
            },
            currentCachedSession: {
                guard let user = self.client.auth.currentSession?.user else {
                    return nil
                }
                return AuthTransitionSession(
                    userID: user.id,
                    isAnonymous: user.isAnonymous
                )
            },
            adoptCachedSession: { expected, transition in
                guard let user = self.client.auth.currentSession?.user,
                      AuthTransitionSession(
                          userID: user.id,
                          isAnonymous: user.isAnonymous
                      ) == expected else {
                    return false
                }
                return self.adoptAuthTransitionSession(
                    user,
                    for: transition
                )
            },
            publishCachedSession: { expected in
                guard let user = self.client.auth.currentSession?.user,
                      AuthTransitionSession(
                          userID: user.id,
                          isAnonymous: user.isAnonymous
                      ) == expected else {
                    return
                }
                if self.currentUser?.id != user.id {
                    self.purchaseIdentitySessionCoordinator.clearBinding()
                    self.purchaseIdentitySessionCoordinator.clearLinkedUser()
                }
                self.currentUser = user
                self.isAuthenticated = true
                ConsentManager.shared.observeSession(userId: user.id)
                self.schedulePublicAuthorIdentityRefreshIfNeeded(for: user)
            },
            performVerifiedLocalSignOut: { transition in
                await self.performVerifiedLocalSignOut(
                    ownedBy: transition
                )
            }
        )
        let diagnostics = AccountDeletionDiagnostics(
            reportAcknowledgementPending: { error in
                MerianLog.auth.error(
                    "Account deletion cleanup acknowledgement remains pending; kind=\(MerianLog.errorKind(error), privacy: .public)."
                )
            },
            reportAcceptedCleanupPending: {
                MerianLog.auth.error(
                    "Account deletion was accepted, but local cleanup remains pending."
                )
            },
            reportRecoveryProofUnavailable: {
                MerianLog.auth.error(
                    "Account deletion recovery proof is unavailable; cleanup remains pending."
                )
            },
            reportCapabilityRecoveryPending: { error in
                let code = EdgeFunctionErrorPolicy.stableCode(from: error)
                MerianLog.auth.error(
                    "Account deletion capability recovery remains pending; code=\((code ?? "unavailable"), privacy: .public)."
                )
            }
        )
        return AccountDeletionCoordinationDependencies(
            hasPendingPurchaseIdentityHandoff: {
                self.hasPendingPurchaseIdentityHandoffFailClosed()
            },
            localState: localState,
            session: session,
            diagnostics: diagnostics
        )
    }

    private func performLocalSignOut(
        ownedBy transition: AuthTransitionToken
    ) async {
        await performLocalSignOut(
            ownedBy: transition,
            performRemoteSignOut: { [supabaseAuthSessionService] in
                try await supabaseAuthSessionService.signOutLocal()
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
        await authLocalSignOutCoordinator.signOut(
            ownedBy: transition,
            dependencies: authLocalSignOutDependencies(
                performRemoteSignOut: performRemoteSignOut,
                performExternalSignOut: performExternalSignOut
            )
        )
    }

    /// Replaces the active account with a fresh anonymous identity. Linked
    /// accounts first persist a one-use purchase-continuity proof; the proof is
    /// removed only after RevenueCat and the server verify the new identity.
    @discardableResult
    func transitionToGhostSession() async -> Bool {
        await userSignOutSingleFlight.run { [weak self] in
            guard let self else { return false }
            return await PurchaseIdentitySignOutCoordinator(
                dependencies: purchaseIdentitySignOutDependencies()
            ).transitionToGhostSession()
        }
    }

    /// Explicit foreground retry for an anonymous session whose device-durable
    /// purchase handoff did not finish during the original sign-out.
    @discardableResult
    func retryPendingSignOutPurchaseHandoff() async -> Bool {
        await PurchaseIdentitySignOutCoordinator(
            dependencies: purchaseIdentitySignOutDependencies()
        ).retryPendingHandoff()
    }

    private func purchaseIdentitySignOutDependencies()
        -> PurchaseSignOutDependencies {
        let session = PurchaseIdentitySignOutSessionBoundary(
            beginTransition: { kind in
                self.beginAuthTransition(kind)
            },
            finishTransition: { transition in
                self.finishAuthTransition(transition)
            },
            updateTransition: { transition, phase in
                _ = self.updateAuthTransition(transition, phase: phase)
            },
            ownsTransition: { transition in
                self.ownsAuthTransition(transition)
            },
            awaitAccountBoundWorkQuiescence: {
                await self.awaitAccountBoundWorkQuiescenceForAuthTransition()
            },
            loadSDKSession: {
                let session = try await self.client.auth.session
                let user = session.user
                return PurchaseIdentitySignOutSessionSnapshot(
                    identity: AuthTransitionSession(
                        userID: user.id,
                        isAnonymous: user.isAnonymous
                    ),
                    ensureTelemetryLinked: { transition in
                        _ = await self.ensurePurchaseIdentityReady(
                            for: user,
                            ownedBy: transition
                        )
                    }
                )
            },
            fallbackPublishedSession: {
                guard let user = self.currentUser else { return nil }
                return PurchaseIdentitySignOutSessionSnapshot(
                    identity: AuthTransitionSession(
                        userID: user.id,
                        isAnonymous: user.isAnonymous
                    ),
                    ensureTelemetryLinked: { transition in
                        _ = await self.ensurePurchaseIdentityReady(
                            for: user,
                            ownedBy: transition
                        )
                    }
                )
            },
            hasKnownLinkedIdentity: {
                self.currentUser?.isAnonymous == false
                    || KeychainManager.shared.bool(
                        forKey: KeychainKeys.hasAuthenticatedOAuth
                    )
            },
            initializeAnonymousSession: { transition in
                guard let user = await self.initializeGhostSession(
                    ownedBy: transition
                ) else {
                    return nil
                }
                return AuthTransitionSession(
                    userID: user.id,
                    isAnonymous: user.isAnonymous
                )
            },
            performLocalSignOut: { transition in
                await self.performLocalSignOut(ownedBy: transition)
            },
            resolveLinkedSourceContext: { starting, transition in
                let identity = starting.identity
                let sourceAuthGeneration = self.authSessionGeneration
                guard self.currentSessionMatchesAuthTransition(transition),
                      self.currentUser?.id == identity.userID,
                      !identity.isAnonymous else {
                    return nil
                }
                await starting.ensureTelemetryLinked(transition)
                guard self.currentSessionMatchesAuthTransition(transition),
                      self.currentUser?.id == identity.userID,
                      self.authSessionGeneration == sourceAuthGeneration,
                      let verifiedSourceSession =
                        try? await self.client.auth.session,
                      verifiedSourceSession.user.id == identity.userID,
                      !verifiedSourceSession.user.isAnonymous,
                      let binding = self.purchaseIdentitySessionCoordinator
                        .activeBinding else {
                    return nil
                }
                return PurchaseIdentitySignOutSourceContext(
                    session: identity,
                    authGeneration: sourceAuthGeneration,
                    binding: binding,
                    purchaseProviderIsReady:
                        RevenueCatManager.shared.isIdentityReady
                            && RevenueCatManager.shared.linkedAuthUserID
                                == identity.userID
                )
            },
            currentSessionMatchesTransition: { transition in
                self.currentSessionMatchesAuthTransition(transition)
            }
        )
        let journal = PurchaseIdentitySignOutJournalBoundary(
            loadLegacyHandoff: {
                try self.purchaseIdentityHandoffJournal
                    .loadLegacyHandoff()
            },
            loadStableRotation: {
                try self.purchaseIdentityHandoffJournal
                    .loadStableRotation()
            },
            setHandoffPending: { [weak self] isPending in
                self?.publishPurchaseIdentityHandoffPending(isPending)
            },
            completePendingHandoff: { destinationUserID, transition in
                await self.completePendingSignOutPurchaseHandoffIfNeeded(
                    expectedDestinationUserId: destinationUserID,
                    ownedBy: transition
                )
            },
            abandonStableRotationIfSourceRestored: { sourceUserID, transition in
                await self.purchaseIdentitySourceHandoffCoordinator()
                    .abandonStableRotationIfSourceRestored(
                        sourceUserID: sourceUserID,
                        ownedBy: transition
                    )
            },
            abandonLegacyHandoffIfSourceRestored: { sourceUserID, transition in
                await self.purchaseIdentitySourceHandoffCoordinator()
                    .abandonLegacyHandoffIfSourceRestored(
                        sourceUserID: sourceUserID,
                        ownedBy: transition
                    )
            },
            prepareStableRotation: { source, transition in
                try await self.purchaseIdentitySourceHandoffCoordinator()
                    .prepareStableRotation(
                        source: source,
                        ownedBy: transition
                    )
            },
            prepareLegacyHandoff: { sourceUserID, transition in
                try await self.purchaseIdentitySourceHandoffCoordinator()
                    .prepareLegacyHandoff(
                        sourceUserID: sourceUserID,
                        ownedBy: transition
                    )
            },
            restoreSourceIdentityAfterFailedSignOut: { sourceUserID, transition in
                await self.purchaseIdentitySourceHandoffCoordinator()
                    .restoreSourceIdentityAfterFailedSignOut(
                        sourceUserID: sourceUserID,
                        ownedBy: transition
                    )
            }
        )
        let diagnostics = PurchaseIdentitySignOutDiagnostics(
            reportUnreadableJournal: {
                MerianLog.auth.error(
                    "Refused sign-out because the purchase handoff proof is unreadable."
                )
            },
            reportUnverifiedLinkedSession: {
                MerianLog.auth.debug(
                    "Refused sign-out because the linked session could not be verified."
                )
            },
            reportUnrelatedStableRotation: {
                MerianLog.auth.error(
                    "Refused to replace an unrelated account while stable purchase identity rotation is pending."
                )
            },
            reportUnrelatedLegacyHandoff: {
                MerianLog.auth.error(
                    "Refused to replace an unrelated account while purchase continuity is pending."
                )
            },
            reportTransitionFailure: { error in
                MerianLog.auth.debug(
                    "Purchase-safe sign-out remains incomplete; kind=\(MerianLog.errorKind(error), privacy: .public)"
                )
            }
        )
        return PurchaseSignOutDependencies(
            session: session,
            journal: journal,
            diagnostics: diagnostics
        )
    }

    private func authLocalSignOutDependencies(
        performRemoteSignOut: @MainActor @escaping () async throws -> Void,
        performExternalSignOut: @MainActor @escaping () async -> Void
    ) -> AuthLocalSignOutDependencies {
        AuthLocalSignOutDependencies(
            state: AuthLocalSignOutStateBoundary(
                begin: { [weak self] in
                    guard let self else {
                        return AuthLocalSignOutPreparation(
                            awaitCancelledBootstrap: {}
                        )
                    }
                    return prepareLocalSignOutState()
                },
                finish: { [weak self] in
                    self?.authRuntimeState.finishSignOut()
                }
            ),
            transition: AuthLocalSignOutTransitionBoundary(
                owns: { [weak self] transition in
                    self?.ownsAuthTransition(transition) ?? false
                },
                awaitAccountWorkQuiescence: { [weak self] in
                    guard let self else { return false }
                    return await awaitAccountBoundWorkQuiescenceForAuthTransition()
                },
                updateForSessionInstallation: { [weak self] transition in
                    _ = self?.updateAuthTransition(
                        transition,
                        phase: .installingSession
                    )
                },
                adoptSignedOutSession: { [weak self] transition in
                    _ = self?.adoptAuthTransitionSession(nil, for: transition)
                }
            ),
            operations: AuthLocalSignOutOperationBoundary(
                signOutSDKSession: performRemoteSignOut,
                finishExternalSignOut: performExternalSignOut
            ),
            diagnose: { diagnostic, error in
                AuthLocalSignOutLiveDiagnostics.report(
                    diagnostic,
                    error: error
                )
            }
        )
    }

    private func prepareLocalSignOutState() -> AuthLocalSignOutPreparation {
        authRuntimeState.beginSignOut()
        appleCredentialRevocationCoordinator.cancel()
        currentUser = nil
        isAuthenticated = false
        purchaseIdentitySessionCoordinator.clearBinding()
        purchaseIdentitySessionCoordinator.clearLinkedUser()
        publicAuthorIdentityRefreshCoordinator.clearCompletedUser()
        RevenueCatManager.shared.beginPurchaseIdentityResolution()
        EntitlementManager.shared.handleSignOut()

        let cancelledBootstrapTask = authSessionBootstrapCoordinator.cancel()

        publicAuthorIdentityRefreshCoordinator.cancel()
        ghostProfileMergeCoordinator.cancel()
        purchaseIdentitySessionCoordinator.cancelResolution()
        KeychainManager.shared.removeObject(forKey: KeychainKeys.hasAuthenticatedOAuth)
        KeychainManager.shared.removeObject(forKey: KeychainKeys.legacyGhostModeUserID)
        PostHogManager.shared.reset()
        return AuthLocalSignOutPreparation(
            awaitCancelledBootstrap: {
                if let cancelledBootstrapTask {
                    _ = await cancelledBootstrapTask.value
                }
            }
        )
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
        await AuthSessionRecoveryCoordinator(
            dependencies: authSessionRecoveryDependencies()
        ).refreshActiveSessionForRetry()
    }

    /// Refreshes the JWT for an authenticated request already owned by the
    /// active Auth transition. Unlike ordinary recovery, this cannot start a
    /// nested transition or relink RevenueCat/analytics/profile state. It may
    /// only renew the exact expected SDK identity and is therefore safe behind
    /// a capability-backed account-deletion intake fence.
    func refreshExpectedSessionForAuthenticatedRequest(
        ownedBy transition: AuthTransitionToken
    ) async -> Bool {
        await AuthSessionRecoveryCoordinator(
            dependencies: authSessionRecoveryDependencies()
        ).refreshExpectedSessionForAuthenticatedRequest(
            ownedBy: transition
        )
    }

    /// Clears a broken anonymous session and creates a fresh ghost identity.
    @discardableResult
    func resetGhostSessionForRetry() async -> Bool {
        await AuthSessionRecoveryCoordinator(
            dependencies: authSessionRecoveryDependencies()
        ).resetGhostSessionForRetry()
    }

    @discardableResult
    func clearLocalSessionAfterAuthFailure() async
        -> AuthSessionLocalClearOutcome {
        await AuthSessionRecoveryCoordinator(
            dependencies: authSessionRecoveryDependencies()
        ).clearLocalSessionAfterAuthFailure()
    }

    @discardableResult
    private func clearLocalSessionAfterAuthFailure(
        ownedBy transition: AuthTransitionToken,
        entryPolicy: AuthSessionRecoveryEntryPolicy = .requireActiveCaller
    ) async -> AuthSessionLocalClearOutcome {
        await AuthSessionRecoveryCoordinator(
            dependencies: authSessionRecoveryDependencies()
        ).clearLocalSessionAfterAuthFailure(
            ownedBy: transition,
            entryPolicy: entryPolicy
        )
    }

    private func authSessionRecoveryDependencies()
        -> AuthSessionRecoveryDependencies {
        let state = AuthSessionRecoveryStateBoundary(
            isSigningOut: { [self] in
                isSigningOut
            },
            hasPendingPurchaseIdentityHandoff: { [self] in
                hasPendingPurchaseIdentityHandoffFailClosed()
            },
            clearLocalRecoveryState: { [self] in
                currentUser = nil
                isAuthenticated = false
                appleCredentialRevocationCoordinator.cancel()
                purchaseIdentitySessionCoordinator.clearLinkedUser()
                publicAuthorIdentityRefreshCoordinator.clearCompletedUser()
                publicAuthorIdentityRefreshCoordinator.cancel()
                ghostProfileMergeCoordinator.cancel()
                KeychainManager.shared.removeObject(
                    forKey: KeychainKeys.hasAuthenticatedOAuth
                )
                KeychainManager.shared.removeObject(
                    forKey: KeychainKeys.legacyGhostModeUserID
                )
                PostHogManager.shared.reset()
            }
        )
        let authTransition = AuthSessionRecoveryTransitionBoundary(
            beginRecovery: { [self] in
                beginAuthTransition(.recovery)
            },
            finish: { [self] transition in
                finishAuthTransition(transition)
            },
            owns: { [self] transition in
                ownsAuthTransition(transition)
            },
            expectedSession: { [self] transition in
                guard ownsAuthTransition(transition) else { return nil }
                return activeAuthTransition?.expectedSession
            },
            awaitAccountWorkQuiescence: { [self] in
                await awaitAccountBoundWorkQuiescenceForAuthTransition()
            },
            currentSessionMatches: { [self] transition in
                currentSessionMatchesAuthTransition(transition)
            },
            updatePhase: { [self] transition, phase in
                _ = updateAuthTransition(transition, phase: phase)
            },
            adoptSignedOutSession: { [self] transition in
                _ = adoptAuthTransitionSession(nil, for: transition)
            }
        )
        let operations = AuthSessionRecoveryOperationBoundary(
            refreshSDKSession: { [self] in
                authSessionRecoverySession(
                    from: try await supabaseAuthSessionService
                        .refreshRecoverySession()
                )
            },
            loadSDKSession: { [self] in
                authSessionRecoverySession(
                    from: try await supabaseAuthSessionService
                        .loadRecoverySession()
                )
            },
            resetAnonymousSession: { [self] transition in
                await PurchaseIdentitySignOutCoordinator(
                    dependencies: purchaseIdentitySignOutDependencies()
                ).resetGhostSessionForRetry(ownedBy: transition)
            },
            performLocalSDKSignOut: { [self] in
                try await supabaseAuthSessionService.signOutLocal()
            },
            finishPurchaseIdentitySignOut: {
                await RevenueCatManager.shared.handleSupabaseSignOut()
            }
        )
        return AuthSessionRecoveryDependencies(
            state: state,
            transition: authTransition,
            operations: operations,
            diagnose: { diagnostic, error in
                AuthSessionRecoveryLiveDiagnostics.report(
                    diagnostic,
                    error: error
                )
            }
        )
    }

    private func authSessionRecoverySession(
        from session: AuthSessionRecoveryLiveSession
    ) -> AuthSessionRecoverySession {
        let user = session.user
        let generation = authSessionGeneration
        return AuthSessionRecoverySession(
            identity: session.identity,
            adopt: { [self] transition in
                adoptAuthTransitionSession(user, for: transition)
            },
            publish: { [self] in
                currentUser = user
                isAuthenticated = true
            },
            schedulePublicAuthorIdentityRefresh: { [self] in
                schedulePublicAuthorIdentityRefreshIfNeeded(for: user)
            },
            ensurePurchaseIdentityReady: { [self] transition in
                _ = await ensurePurchaseIdentityReady(
                    for: user,
                    ownedBy: transition
                )
            },
            purchaseIdentityIsReady: { [self] in
                currentUser?.id == user.id
                    && currentUser?.isAnonymous == user.isAnonymous
                    && authSessionGeneration == generation
                    && purchaseIdentitySessionCoordinator.activeBinding != nil
                    && RevenueCatManager.shared.isIdentityReady
                    && RevenueCatManager.shared.linkedAuthUserID == user.id
            },
            beginEntitlementSession: { [self] transition in
                await EntitlementManager.shared.beginSession(
                    userID: user.id,
                    client: client,
                    authTransitionOwner: transition
                )
            },
            isPublishedAtCapturedGeneration: { [self] in
                currentUser?.id == user.id
                    && currentUser?.isAnonymous == user.isAnonymous
                    && authSessionGeneration == generation
            }
        )
    }

    /// Builds authenticated REST headers, initializing a ghost session if no token exists.
    func getValidAuthHeaders(
        ownedBy transition: AuthTransitionToken? = nil,
        expectedUserID: UUID? = nil
    ) async throws -> [String: String] {
        guard !isSigningOut,
              AuthTransitionPolicy.allowsAuthenticatedRequest(
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
              AuthTransitionPolicy.allowsAuthenticatedRequest(
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
        await AuthenticationCallbackCoordinator(
            dependencies: authenticationCallbackDependencies(url: url)
        ).handle()
    }

    private func authenticationCallbackDependencies(
        url: URL
    ) -> AuthenticationCallbackDependencies {
        AuthenticationCallbackDependencies(
            transition: AuthenticationCallbackTransitionBoundary(
                hasPendingPurchaseIdentityHandoff: { [self] in
                    hasPendingPurchaseIdentityHandoffFailClosed()
                },
                isSignOutInProgress: { [self] in
                    isSigningOut
                },
                begin: { [self] in
                    beginAuthTransition(.authenticationCallback)
                },
                finish: { [self] transition in
                    finishAuthTransition(transition)
                },
                owns: { [self] transition in
                    ownsAuthTransition(transition)
                },
                sourceSession: { [self] transition in
                    guard activeAuthTransition?.token == transition else {
                        return nil
                    }
                    return activeAuthTransition?.sourceSession
                },
                currentSessionMatches: { [self] transition in
                    currentSessionMatchesAuthTransition(transition)
                },
                verifyExpectedSessionIfPresent: { [self] transition in
                    _ = try await verifiedExpectedSessionIfPresent(
                        for: transition
                    )
                },
                verifyExpectedSession: { [self] transition in
                    _ = try await verifiedExpectedSession(for: transition)
                },
                updatePhase: { [self] transition, phase in
                    _ = updateAuthTransition(transition, phase: phase)
                }
            ),
            session: AuthenticationCallbackSessionBoundary(
                analyticsGeneration: { [self] transition in
                    analyticsGeneration(for: transition)
                },
                installAndAdopt: { [self] transition, didMutateSession in
                    let session = try await supabaseAuthSessionService
                        .installCallbackSession(from: url)
                    didMutateSession()
                    let installed = authenticationCallbackSession(session)
                    guard adoptAuthTransitionSession(
                        session.user,
                        for: transition
                    ) else {
                        throw SupabaseAuthTransitionError
                            .signOutSessionChanged
                    }
                    return installed
                },
                current: { [self] in
                    supabaseAuthSessionService.currentSession().map(
                        authenticationCallbackSession
                    )
                },
                clearPublishedSession: { [self] in
                    currentUser = nil
                    isAuthenticated = false
                }
            ),
            completion: AuthenticationCallbackCompletionBoundary(
                clearMutatedSession: { [self] transition in
                    await clearLocalSessionAfterAuthFailure(
                        ownedBy: transition,
                        entryPolicy: .completeMutatedOAuthSession
                    )
                },
                markAuthenticatedOAuth: { isAuthenticated in
                    KeychainManager.shared.set(
                        isAuthenticated,
                        forKey: KeychainKeys.hasAuthenticatedOAuth
                    )
                }
            ),
            diagnostics: .live
        )
    }

    private func authenticationCallbackSession(
        _ session: Session
    ) -> AuthenticationCallbackSession {
        AuthenticationCallbackSession(
            identity: transitionSession(from: session.user)!,
            isExpired: session.isExpired,
            publish: { [self] in
                currentUser = session.user
                isAuthenticated = true
            },
            ensurePurchaseIdentityReady: { [self] transition in
                _ = await ensurePurchaseIdentityReady(
                    for: session.user,
                    ownedBy: transition
                )
            },
            purchaseIdentityIsReady: {
                RevenueCatManager.shared.linkedAuthUserID == session.user.id
                    && RevenueCatManager.shared.isIdentityReady
            },
            beginEntitlementSession: { [self] transition in
                await EntitlementManager.shared.beginSession(
                    userID: session.user.id,
                    client: client,
                    authTransitionOwner: transition
                )
            }
        )
    }

    // MARK: - Google Sign-In

    func signInWithGoogle() async {
        await oauthProviderSignInCoordinator.signInWithGoogle(
            dependencies: oauthProviderSignInDependencies()
        )
    }

    // MARK: - Apple Sign-In

    func startAppleSignIn() {
        oauthProviderSignInCoordinator.startAppleSignIn(
            dependencies: oauthProviderSignInDependencies()
        )
    }

    // MARK: - Private OAuth Helpers

    private func oauthProviderSignInDependencies()
        -> OAuthProviderSignInDependencies {
        let googleProvider = googleOAuthAuthorizationLiveProvider
        let appleProvider = appleOAuthAuthorizationLiveProvider
        return OAuthProviderSignInDependencies(
            transition: OAuthProviderSignInTransitionBoundary(
                begin: { [weak self] provider in
                    self?.beginAuthTransition(.oauth(provider))
                },
                updateAwaitingProvider: { [weak self] transition in
                    _ = self?.updateAuthTransition(
                        transition,
                        phase: .awaitingProvider
                    )
                },
                activeTransitionID: { [weak self] in
                    self?.activeAuthTransition?.token.id
                },
                sourceSession: { [weak self] transition in
                    guard self?.activeAuthTransition?.token == transition
                    else {
                        return nil
                    }
                    return self?.activeAuthTransition?.sourceSession
                },
                verifyExpectedSessionIfPresent: { [weak self] transition in
                    guard let self else { throw CancellationError() }
                    _ = try await self
                        .verifiedExpectedSessionIfPresent(for: transition)
                },
                finish: { [weak self] transition in
                    self?.finishAuthTransition(transition)
                }
            ),
            authorization: OAuthProviderAuthorizationBoundary(
                authorizeWithGoogle: {
                    try await googleProvider.authorize()
                },
                startAppleAuthorization: { completion in
                    try appleProvider.start(completion: completion)
                },
                cancelAppleAuthorization: {
                    appleProvider.cancel()
                }
            ),
            completion: OAuthProviderSignInCompletionBoundary(
                complete: { [weak self] authorization, transition, didMutateSession in
                    guard let self else { throw CancellationError() }
                    let registration: OAuthProviderCredentialRegistration?
                    if let credential = authorization.appleCredentialRegistration {
                        let identityToken = authorization.credentials.idToken
                        registration = { [weak self] userID, token in
                            guard let self else {
                                throw CancellationError()
                            }
                            _ = try await self.verifiedExpectedSession(
                                for: token
                            )
                            try await self.registerAppleRevocationCredential(
                                registrationId: credential.registrationID,
                                authorizationCode: credential.authorizationCode,
                                identityToken: identityToken,
                                expectedUserID: userID,
                                ownedBy: token
                            )
                        }
                    } else {
                        registration = nil
                    }
                    _ = try await OAuthSignInCoordinator(
                        dependencies: self.oauthSignInDependencies()
                    ).complete(
                        credentials: authorization.credentials,
                        profileMetadata: authorization.profileMetadata,
                        registerProviderCredential: registration,
                        ownedBy: transition,
                        didMutateSession: didMutateSession
                    )
                },
                recoverAfterFailure: { [weak self] didMutateSession, sourceSession, transition in
                    await self?.recoverOAuthSignInFailureIfNeeded(
                        observedSessionMutation: didMutateSession,
                        sourceSession: sourceSession,
                        ownedBy: transition
                    )
                }
            ),
            diagnostics: .live
        )
    }

    private func oauthSignInDependencies()
        -> OAuthSignInCoordinationDependencies {
        OAuthSignInCoordinationDependencies(
            session: OAuthSignInSessionBoundary(
                ownsTransition: { token in
                    self.ownsAuthTransition(token)
                },
                isSignOutInProgress: {
                    self.isSigningOut
                },
                expectedSession: { token in
                    guard self.activeAuthTransition?.token == token else {
                        return nil
                    }
                    return self.activeAuthTransition?.expectedSession
                },
                verifyExpectedSessionIfPresent: { token in
                    guard let session = try await self
                        .verifiedExpectedSessionIfPresent(for: token) else {
                        return nil
                    }
                    return self.supabaseAuthSessionService.signInSession(
                        from: session
                    )
                },
                verifyExpectedSession: { token in
                    let session = try await self.verifiedExpectedSession(
                        for: token
                    )
                    return self.supabaseAuthSessionService.signInSession(
                        from: session
                    )
                },
                readSDKSession: {
                    self.supabaseAuthSessionService.signInSession(
                        from: try await self.supabaseAuthSessionService.readSession()
                    )
                },
                linkIdentity: { credentials in
                    try await self.supabaseAuthSessionService.linkIdentity(
                        using: credentials
                    )
                },
                replaceAndAdoptSession: { credentials, token, didMutateSession in
                    self.supabaseAuthSessionService.signInSession(
                        from: try await self
                            .installOAuthSessionReplacingCurrentAccount(
                                credentials: credentials,
                                transition: token,
                                didMutateSession: didMutateSession
                            )
                    )
                },
                adoptSession: { session, token in
                    self.adoptOAuthSignInSession(session, for: token)
                },
                currentSessionMatchesTransition: { token in
                    self.currentSessionMatchesAuthTransition(token)
                },
                updateTransition: { token, phase in
                    _ = self.updateAuthTransition(token, phase: phase)
                },
                publishAuthenticatedSession: { token in
                    let session = try await self.verifiedExpectedSession(
                        for: token
                    )
                    self.currentUser = session.user
                    self.isAuthenticated = true
                    return self.supabaseAuthSessionService.signInSession(
                        from: session
                    )
                }
            ),
            merge: OAuthSignInMergeBoundary(
                completePendingPurchaseHandoff: { userID, token in
                    await self
                        .completePendingSignOutPurchaseHandoffIfNeeded(
                            expectedDestinationUserId: userID,
                            ownedBy: token
                        )
                },
                requiresProviderBoundGhostMerge: { error in
                    self.ghostProfileMergeRemoteService
                        .requiresProviderBoundMerge(after: error)
                },
                prepareGhostMerge: { ghostID, provider, providerSubject, token in
                    guard let sourceUserID = UUID(uuidString: ghostID) else {
                        throw SupabaseAuthTransitionError
                            .guestMergeSessionChanged
                    }
                    _ = try await self.ghostProfileMergeCoordinator.prepare(
                        sourceUserID: sourceUserID,
                        provider: provider,
                        providerSubject: providerSubject,
                        ownedBy: token,
                        dependencies: self.ghostProfileMergeDependencies()
                    )
                },
                clearGhostMerges: { ghostID in
                    guard let sourceUserID = UUID(uuidString: ghostID) else {
                        throw SupabaseAuthTransitionError
                            .guestMergeSessionChanged
                    }
                    try self.ghostProfileMergeCoordinator.clearHandoffs(
                        for: sourceUserID,
                        dependencies: self.ghostProfileMergeDependencies()
                    )
                },
                completePendingGhostMerge: { userID, token in
                    guard let targetUserID = UUID(uuidString: userID) else {
                        return false
                    }
                    return await self.ghostProfileMergeCoordinator
                        .completePendingHandoffs(
                            expectedTargetUserID: targetUserID,
                            ownedBy: token,
                            dependencies:
                                self.ghostProfileMergeDependencies()
                        )
                }
            ),
            completion: OAuthSignInCompletionBoundary(
                persistProfileMetadata: { metadata, provider, userID, token in
                    await self.persistOAuthProfileMetadata(
                        metadata,
                        provider: provider,
                        expectedUserID: userID,
                        transition: token
                    )
                },
                ensureTelemetryLinked: { userID, token in
                    guard let user = self.supabaseAuthSessionService
                        .currentSession()?.user,
                          user.id == userID else {
                        return
                    }
                    _ = await self.ensurePurchaseIdentityReady(
                        for: user,
                        ownedBy: token
                    )
                },
                providerIdentityIsReady: { userID in
                    RevenueCatManager.shared.linkedAuthUserID == userID
                        && RevenueCatManager.shared.isIdentityReady
                },
                beginEntitlementSession: { userID, token in
                    await EntitlementManager.shared.beginSession(
                        userID: userID,
                        client: self.client,
                        authTransitionOwner: token
                    )
                },
                refreshPublicAuthorIdentity: { userID, token in
                    await self.publicAuthorIdentityRefreshCoordinator.refresh(
                        expectedUserID: userID,
                        ownedBy: token,
                        dependencies:
                            self.publicAuthorIdentityRefreshDependencies()
                    )
                },
                publishPublicAuthorIdentityChange: { previousUserID, currentUserID in
                    SupabasePublicAuthorRefreshLiveEffects
                        .publishIdentityChanged(
                            previousUserID: previousUserID,
                            currentUserID: currentUserID
                        )
                },
                markAuthenticatedOAuth: {
                    KeychainManager.shared.set(
                        true,
                        forKey: KeychainKeys.hasAuthenticatedOAuth
                    )
                }
            )
        )
    }

    private func adoptOAuthSignInSession(
        _ session: OAuthSignInSession,
        for transition: AuthTransitionToken
    ) -> Bool {
        guard let user = supabaseAuthSessionService.currentSession()?.user,
              transitionSession(from: user) == session.identity else {
            return false
        }
        return adoptAuthTransitionSession(user, for: transition)
    }

    private func registerAppleRevocationCredential(
        registrationId: UUID,
        authorizationCode: String,
        identityToken: String,
        expectedUserID: UUID,
        ownedBy transition: AuthTransitionToken
    ) async throws {
        try await OAuthSignInWorkflow.registerAppleCredential {
            guard self.currentSessionMatchesAuthTransition(transition),
                  self.supabaseAuthSessionService.currentSession()?.user.id
                    == expectedUserID else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }
            try await self.appleOAuthCredentialRegistrationService.register(
                registrationID: registrationId,
                authorizationCode: authorizationCode,
                identityToken: identityToken
            )
            guard self.currentSessionMatchesAuthTransition(transition),
                  self.supabaseAuthSessionService.currentSession()?.user.id
                    == expectedUserID else {
                throw SupabaseAuthTransitionError.signOutSessionChanged
            }
        }
    }

    private func installOAuthSessionReplacingCurrentAccount(
        credentials: OAuthSignInCredentials,
        transition: AuthTransitionToken,
        didMutateSession: OAuthSessionMutationObserver
    ) async throws -> Session {
        try await OAuthSignInWorkflow.replacingSession(
            suspendAnalytics: {
                self.analyticsGeneration(for: transition)
            },
            installSession: {
                let session = try await self.supabaseAuthSessionService.installSession(
                    using: credentials
                )
                didMutateSession()
                let installed = self.supabaseAuthSessionService.signInSession(
                    from: session
                )
                guard self.adoptOAuthSignInSession(
                    installed,
                    for: transition
                ) else {
                    throw SupabaseAuthTransitionError
                        .signOutSessionChanged
                }
                return session
            },
            currentSession: {
                self.supabaseAuthSessionService.currentSession()
            },
            reconcileSession: { _, session, disposition in
                self.reconcileOAuthSessionReplacement(
                    session: session,
                    disposition: disposition,
                    transition: transition
                )
            }
        )
    }

    private func reconcileOAuthSessionReplacement(
        session: Session?,
        disposition: OAuthSessionReplacementDisposition,
        transition: AuthTransitionToken
    ) {
        guard ownsAuthTransition(transition) else { return }
        let resolvedSession = supabaseAuthSessionService.currentSession() ?? session
        let activeSession: Session?
        switch disposition {
        case .installed, .failed:
            activeSession =
                !isSigningOut && resolvedSession?.isExpired == false
                ? resolvedSession
                : nil
        case .cancelled:
            let sourceSession = activeAuthTransition?.sourceSession
            activeSession =
                !isSigningOut
                && resolvedSession?.isExpired == false
                && transitionSession(from: resolvedSession?.user)
                    == sourceSession
                ? resolvedSession
                : nil
        }
        currentUser = activeSession?.user
        isAuthenticated = activeSession != nil
    }

    private func ghostProfileMergeDependencies()
        -> GhostProfileMergeDependencies {
        GhostProfileMergeDependencies(
            session: GhostProfileMergeSessionBoundary(
                isSigningOut: { [self] in isSigningOut },
                currentPublishedSession: { [self] in
                    transitionSession(from: currentUser)
                },
                currentSDKSession: { [self] in
                    transitionSession(
                        from: client.auth.currentSession?.user
                    )
                },
                currentSessionMatchesTransition: { [self] transition in
                    currentSessionMatchesAuthTransition(transition)
                },
                beginUnownedAccountWork: { [self] userID in
                    try? beginUnownedAccountBoundWork(
                        expectedUserID: userID
                    )
                },
                finishAccountWork: { [self] lease in
                    finishAccountBoundWork(lease)
                },
                loadSDKSession: { [self] in
                    let user = try await client.auth.session.user
                    return AuthTransitionSession(
                        userID: user.id,
                        isAnonymous: user.isAnonymous
                    )
                }
            ),
            queue: GhostProfileMergeQueueBoundary(
                load: { [self] in
                    let result = try ghostProfileMergeStore
                        .loadPendingHandoffs()
                    return GhostProfileMergeQueueSnapshot(
                        handoffs: result.handoffs,
                        legacyMigrationWasDeferred:
                            result.legacyMigrationWasDeferred
                    )
                },
                persist: { [self] handoffs in
                    try ghostProfileMergeStore
                        .persistPendingHandoffs(handoffs)
                },
                clear: { [self] handoffID in
                    try ghostProfileMergeStore.clearPendingHandoff(
                        handoffId: handoffID
                    )
                },
                clearSource: { [self] sourceUserID in
                    try ghostProfileMergeStore.clearPendingHandoffs(
                        ghostUserId: sourceUserID
                    )
                }
            ),
            operations: GhostProfileMergeOperationBoundary(
                prepare: { [self] provider, providerSubject in
                    try await ghostProfileMergeRemoteService.prepare(
                        provider: provider,
                        providerSubject: providerSubject
                    )
                },
                complete: { [self] handoff in
                    try await ghostProfileMergeRemoteService.complete(handoff)
                },
                synchronizeProviderPurchases: {
                    try await RevenueCatManager.shared
                        .synchronizePurchasesAfterAccountMerge()
                },
                rebindAndSynchronizeLocalEvidence: { source, target in
                    try await ConsentManager.shared
                        .rebindAndSynchronizeGhostEvidence(
                            from: source,
                            to: target
                        )
                },
                synchronizeTargetEvidence: { transition in
                    if let transition {
                        try await ConsentManager.shared
                            .synchronizeWithCurrentSession(
                                ownedBy: transition
                            )
                    } else {
                        try await ConsentManager.shared
                            .synchronizeWithCurrentSession()
                    }
                },
                targetEvidenceMatches: { target in
                    ConsentManager.shared.currentSessionUserId == target
                },
                isTerminalHandoffError: { [self] error in
                    ghostProfileMergeRemoteService
                        .isTerminalHandoffError(error)
                }
            ),
            setAnalyticsSuppressed: { isSuppressed in
                ConsentManager.shared.setAnalyticsSuppressedForGhostHandoff(
                    isSuppressed
                )
            },
            diagnose: { diagnostic, error in
                let errorKind = error.map(MerianLog.errorKind)
                    ?? "unavailable"
                switch diagnostic {
                case .secured:
                    MerianLog.auth.debug(
                        "Secured provider-bound guest profile handoff."
                    )
                case .legacyMigrationDeferred:
                    MerianLog.auth.error(
                        "Could not migrate the signed-out profile handoff queue; the original proof remains available."
                    )
                case .queueUnreadable:
                    MerianLog.auth.error(
                        "Signed-out profile upgrade remains pending because its durable queue is unreadable; kind=\(errorKind, privacy: .public)"
                    )
                case .unexpectedTarget:
                    MerianLog.auth.error(
                        "Refused guest merge retry for an unexpected active account."
                    )
                case .invalidSource:
                    MerianLog.auth.error(
                        "Refused guest merge for an invalid source account UUID."
                    )
                case .completed:
                    MerianLog.auth.debug(
                        "Signed-out profile upgrade finalized."
                    )
                case .terminalDiscarded:
                    MerianLog.auth.error(
                        "Discarded a terminal signed-out profile handoff; kind=\(errorKind, privacy: .public)"
                    )
                case .terminalCleanupPending:
                    MerianLog.auth.error(
                        "Terminal signed-out handoff cleanup remains pending; kind=\(errorKind, privacy: .public)"
                    )
                case .retryPending:
                    MerianLog.auth.error(
                        "Signed-out profile upgrade remains pending and will retry; kind=\(errorKind, privacy: .public)"
                    )
                case .sessionUnavailable:
                    MerianLog.auth.error(
                        "Signed-out profile upgrade retry could not read the active session; kind=\(errorKind, privacy: .public)"
                    )
                }
            }
        )
    }

    @discardableResult
    private func completePendingSignOutPurchaseHandoffIfNeeded(
        expectedDestinationUserId: String? = nil,
        expectedAuthGeneration: UInt64? = nil,
        ownedBy transition: AuthTransitionToken? = nil
    ) async -> Bool {
        await purchaseIdentityHandoffCoordinator.completePendingHandoff(
            expectedDestinationUserID: expectedDestinationUserId,
            expectedAuthGeneration: expectedAuthGeneration,
            ownedBy: transition,
            dependencies: purchaseIdentityHandoffDependencies()
        )
    }

    private func purchaseIdentityHandoffDependencies()
        -> PurchaseIdentityHandoffDependencies {
        let client = client
        let resolver = purchasePrincipalResolver
        let remoteService = legacyPurchaseHandoffRemoteService

        return PurchaseIdentityHandoffDependencies(
            session: .init(
                currentPublishedAnonymousUserID: { [weak self] in
                    guard self?.currentUser?.isAnonymous == true else {
                        return nil
                    }
                    return self?.currentUser?.id.uuidString.lowercased()
                },
                currentAuthGeneration: { [weak self] in
                    self?.authSessionGeneration ?? 0
                },
                isLocalSignOutInProgress: { [weak self] in
                    self?.isSigningOut ?? true
                },
                currentSessionMatchesTransition: { [weak self] transition in
                    self?.currentSessionMatchesAuthTransition(transition)
                        ?? false
                },
                beginUnownedAccountWork: { [weak self] expectedUserID in
                    guard let self else { return nil }
                    return try? self.beginUnownedAccountBoundWork(
                        expectedUserID: expectedUserID
                    )
                },
                finishAccountWork: { [weak self] lease in
                    self?.finishAccountBoundWork(lease)
                },
                loadSDKSession: { [weak self] in
                    guard let self else {
                        throw SupabaseAuthTransitionError
                            .signOutSessionChanged
                    }
                    let user = try await client.auth.session.user
                    let identity = AuthTransitionSession(
                        userID: user.id,
                        isAnonymous: user.isAnonymous
                    )
                    return PurchaseIdentityHandoffSessionSnapshot(
                        identity: identity,
                        linkLegacyProviderIdentity: { [weak self] in
                            guard let self else {
                                throw SupabaseAuthTransitionError
                                    .signOutSessionChanged
                            }
                            try await self
                                .linkLegacyPurchaseIdentityForSignOutHandoff(
                                    user: user
                                )
                        },
                        ensureTelemetryLinked: { [weak self] transition in
                            guard let self else { return }
                            _ = await self.ensurePurchaseIdentityReady(
                                for: user,
                                ownedBy: transition
                            )
                        }
                    )
                },
                activeAnonymousSessionMatches: { [weak self] userID, generation, transition in
                    self?.activeAnonymousSessionMatches(
                        userId: userID,
                        expectedAuthGeneration: generation,
                        ownedBy: transition
                    ) ?? false
                }
            ),
            journal: .init(
                loadLegacyHandoff: { [weak self] in
                    guard let self else {
                        throw SupabaseAuthTransitionError
                            .signOutSessionChanged
                    }
                    return try self.purchaseIdentityHandoffJournal
                        .loadLegacyHandoff()
                },
                loadStableRotation: { [weak self] in
                    guard let self else {
                        throw SupabaseAuthTransitionError
                            .signOutSessionChanged
                    }
                    return try self.purchaseIdentityHandoffJournal
                        .loadStableRotation()
                },
                clearLegacyHandoff: { [weak self] in
                    guard let self else {
                        throw SupabaseAuthTransitionError
                            .signOutSessionChanged
                    }
                    try self.purchaseIdentityHandoffJournal
                        .clearLegacyHandoff()
                },
                clearStableRotation: { [weak self] in
                    guard let self else {
                        throw SupabaseAuthTransitionError
                            .signOutSessionChanged
                    }
                    try self.purchaseIdentityHandoffJournal
                        .clearStableRotation()
                },
                setHandoffPending: { [weak self] pending in
                    self?.publishPurchaseIdentityHandoffPending(pending)
                }
            ),
            operations: .init(
                claimStableRotation: { rotationID, rotationSecret, capabilityFingerprint in
                    try await resolver.claimSignoutRotation(
                        rotationId: rotationID,
                        rotationSecret: rotationSecret,
                        expectedCapabilityFingerprint: capabilityFingerprint
                    )
                },
                applyStableBinding: { [weak self] binding, userID in
                    guard let self else { return }
                    self.purchaseIdentitySessionCoordinator.recordBinding(
                        binding
                    )
                    RevenueCatManager.shared.beginPurchaseIdentityResolution()
                    await RevenueCatManager.shared
                        .linkResolvedPurchasePrincipal(
                            binding,
                            authUserID: userID,
                            accountKind: RevenueCatAccountMutationPolicy
                                .accountKind(isAnonymous: true)
                        )
                },
                stableProviderIdentityMatches: { userID in
                    RevenueCatManager.shared.isIdentityReady
                        && RevenueCatManager.shared.linkedAuthUserID == userID
                        && RevenueCatManager.shared.linkedAccountKind ==
                        RevenueCatAccountMutationPolicy.ghostAccountKind
                },
                bindLegacyHandoff: { handoff, destinationUserID in
                    do {
                        try await remoteService.bind(
                            handoff,
                            to: destinationUserID
                        )
                    } catch LegacyPurchaseHandoffRemoteError.invalidResponse {
                        throw SupabaseAuthTransitionError
                            .signOutSessionChanged
                    }
                },
                synchronizeLegacyPurchases: { userID in
                    try await RevenueCatManager.shared
                        .synchronizePurchasesAfterIdentityHandoff(
                            expectedUserId: userID
                        )
                },
                completeLegacyHandoff: { handoff in
                    do {
                        try await remoteService.complete(handoff)
                    } catch LegacyPurchaseHandoffRemoteError.invalidResponse {
                        throw SupabaseAuthTransitionError
                            .signOutSessionChanged
                    }
                },
                refreshEntitlement: { userID, transition in
                    await EntitlementManager.shared.beginSession(
                        userID: userID,
                        client: client,
                        authTransitionOwner: transition
                    )
                },
                refreshCustomerInfo: {
                    await RevenueCatManager.shared.refreshCustomerInfo()
                },
                recordLinkedUser: { [weak self] userID in
                    self?.purchaseIdentitySessionCoordinator.recordLinkedUser(
                        userID
                    )
                },
                abandonLegacyHandoffIfSourceRestored: { [weak self] sourceUserID, transition in
                    guard let self else { return }
                    await self.purchaseIdentitySourceHandoffCoordinator()
                        .abandonLegacyHandoffIfSourceRestored(
                            sourceUserID: sourceUserID,
                            ownedBy: transition
                        )
                },
                shouldDiscardLegacyHandoff: { error in
                    remoteService.isTerminalProofError(error)
                }
            ),
            diagnostics: .init(
                reportJournalSelectionFailure: { _ in },
                reportStableCompletionFailure: { error in
                    MerianLog.auth.debug(
                        "Stable purchase identity rotation remains pending; kind=\(MerianLog.errorKind(error), privacy: .public)"
                    )
                },
                reportLegacyJournalFailure: { error in
                    MerianLog.auth.error(
                        "Purchase continuity remains pending because its device proof is unreadable; kind=\(MerianLog.errorKind(error), privacy: .public)"
                    )
                },
                reportLegacyCompletionFailure: { error in
                    MerianLog.auth.debug(
                        "Purchase continuity retry remains pending; kind=\(MerianLog.errorKind(error), privacy: .public)"
                    )
                },
                reportStableCompletion: {
                    MerianLog.auth.debug(
                        "Claimed the server-authorized stable purchase identity after sign-out."
                    )
                },
                reportLegacyCompletion: {
                    MerianLog.auth.debug(
                        "Verified purchase continuity for the signed-out session."
                    )
                }
            )
        )
    }

    private func purchaseIdentitySourceHandoffCoordinator()
        -> PurchaseIdentitySourceHandoffCoordinator {
        PurchaseIdentitySourceHandoffCoordinator(
            dependencies: purchaseIdentitySourceHandoffDependencies()
        )
    }

    private func purchaseIdentitySourceHandoffDependencies()
        -> SourceHandoffDependencies {
        let client = client
        let journal = purchaseIdentityHandoffJournal
        let resolver = purchasePrincipalResolver
        let remoteService = legacyPurchaseHandoffRemoteService
        let preparation = PurchaseHandoffPreparationCoordinator(
            dependencies: .init(
                journal: .init(
                    persistLegacyHandoff: { pending in
                        try journal.persistLegacyHandoff(pending)
                    },
                    persistStableRotation: { pending in
                        try journal.persistStableRotation(pending)
                    }
                ),
                operations: .init(
                    currentCapabilityFingerprint: {
                        try resolver
                            .currentInstallationCapabilityFingerprint()
                    },
                    makeRotationID: { UUID() },
                    makeRotationSecret: {
                        try PurchasePrincipalResolver
                            .generateSignoutRotationSecret()
                    },
                    currentTimestamp: {
                        DateUtilities.iso8601Formatter.string(from: Date())
                    },
                    prepareStableRotation: { rotationID, secret, binding, fingerprint in
                        try await resolver.prepareSignoutRotation(
                            rotationId: rotationID,
                            rotationSecret: secret,
                            expectedBinding: binding,
                            expectedCapabilityFingerprint: fingerprint
                        )
                    },
                    prepareLegacyHandoff: {
                        try await remoteService.prepare()
                    }
                )
            )
        )

        return SourceHandoffDependencies(
            session: .init(
                currentAuthGeneration: { [weak self] in
                    self?.authSessionGeneration ?? 0
                },
                currentPublishedUserID: { [weak self] in
                    self?.currentUser?.id
                },
                currentSDKUserID: {
                    client.auth.currentSession?.user.id
                },
                ownsTransition: { [weak self] transition in
                    self?.ownsAuthTransition(transition) ?? false
                },
                currentSessionMatchesTransition: { [weak self] transition in
                    self?.currentSessionMatchesAuthTransition(transition)
                        ?? false
                },
                beginUnownedAccountWork: { [weak self] sourceUserID in
                    guard let self else { return nil }
                    return try? self.beginUnownedAccountBoundWork(
                        expectedUserID: sourceUserID
                    )
                },
                isAccountWorkCurrent: { [weak self] lease in
                    self?.isAccountBoundWorkLeaseCurrent(lease) ?? false
                },
                finishAccountWork: { [weak self] lease in
                    self?.finishAccountBoundWork(lease)
                },
                loadSDKSession: {
                    let user = try await client.auth.session.user
                    return AuthTransitionSession(
                        userID: user.id,
                        isAnonymous: user.isAnonymous
                    )
                },
                adoptSourceSession: { [weak self] sourceUserID, transition in
                    guard let self,
                          let user = client.auth.currentSession?.user,
                          user.id == sourceUserID,
                          !user.isAnonymous else {
                        return false
                    }
                    return self.adoptAuthTransitionSession(
                        user,
                        for: transition
                    )
                },
                publishRestoredSource: { [weak self] sourceUserID in
                    guard let self,
                          let user = client.auth.currentSession?.user,
                          user.id == sourceUserID,
                          !user.isAnonymous else {
                        return false
                    }
                    self.currentUser = user
                    self.isAuthenticated = true
                    KeychainManager.shared.set(
                        true,
                        forKey: KeychainKeys.hasAuthenticatedOAuth
                    )
                    ConsentManager.shared.observeSession(userId: sourceUserID)
                    self.schedulePublicAuthorIdentityRefreshIfNeeded(for: user)
                    return true
                },
                restoredSourceIsCurrent: { [weak self] sourceUserID, transition in
                    guard let self else { return false }
                    return self.currentUser?.id == sourceUserID
                        && self.currentSessionMatchesAuthTransition(transition)
                }
            ),
            journal: .init(
                loadLegacyHandoff: {
                    try journal.loadLegacyHandoff()
                },
                loadStableRotation: {
                    try journal.loadStableRotation()
                },
                clearLegacyHandoff: {
                    try journal.clearLegacyHandoff()
                },
                clearStableRotation: {
                    try journal.clearStableRotation()
                },
                setHandoffPending: { [weak self] pending in
                    self?.publishPurchaseIdentityHandoffPending(pending)
                }
            ),
            operations: .init(
                prepareStableRotation: { sourceUserID, binding in
                    try await preparation.prepareStableRotation(
                        sourceUserID: sourceUserID,
                        binding: binding
                    )
                },
                prepareLegacyHandoff: { sourceUserID in
                    try await preparation.prepareLegacyHandoff(
                        sourceUserID: sourceUserID
                    )
                },
                cancelStableRotation: { rotation in
                    guard let rotationID = UUID(
                        uuidString: rotation.rotationId
                    ) else {
                        throw SupabaseAuthTransitionError
                            .purchasePrincipalRotationPersistenceFailed
                    }
                    _ = try await resolver.cancelSignoutRotation(
                        rotationId: rotationID,
                        rotationSecret: rotation.rotationSecret,
                        expectedCapabilityFingerprint:
                            rotation.installationCapabilityFingerprint
                    )
                },
                cancelLegacyHandoff: { pending in
                    do {
                        try await remoteService.cancel(pending)
                    } catch LegacyPurchaseHandoffRemoteError.invalidResponse {
                        throw SupabaseAuthTransitionError
                            .signOutSessionChanged
                    }
                },
                ensurePurchaseIdentityReady: { [weak self] sourceUserID, transition in
                    guard let self,
                          let user = client.auth.currentSession?.user,
                          user.id == sourceUserID,
                          !user.isAnonymous else {
                        return
                    }
                    _ = await self.ensurePurchaseIdentityReady(
                        for: user,
                        ownedBy: transition
                    )
                },
                beginEntitlementSession: { sourceUserID, transition in
                    await EntitlementManager.shared.beginSession(
                        userID: sourceUserID,
                        client: client,
                        authTransitionOwner: transition
                    )
                }
            ),
            diagnostics: .init(
                reportPendingStateFailure: { _ in
                    MerianLog.auth.error(
                        "Could not verify the purchase handoff proof; preserving the active identity."
                    )
                },
                reportLegacyPreparation: {
                    MerianLog.auth.debug(
                        "Secured purchase continuity before sign-out."
                    )
                },
                reportLegacyAbandonment: {
                    MerianLog.auth.debug(
                        "Abandoned an unused sign-out purchase proof after the source account was restored."
                    )
                },
                reportLegacyAbandonmentFailure: { error in
                    MerianLog.auth.error(
                        "Could not clear an unused sign-out purchase proof; kind=\(MerianLog.errorKind(error), privacy: .public)"
                    )
                },
                reportSourceRestoration: {
                    MerianLog.auth.debug(
                        "Restored the linked purchase identity after local sign-out failed."
                    )
                }
            )
        )
    }

    /// Publishes the aggregate durable handoff fence and wakes a retained Apple
    /// revocation only after every purchase-continuity proof is resolved.
    private func publishPurchaseIdentityHandoffPending(_ isPending: Bool) {
        RevenueCatManager.shared.setPurchaseIdentityHandoffPending(isPending)
        guard !isPending else { return }
        appleCredentialRevocationCoordinator.resumeDeferredIfNeeded(
            dependencies: appleCredentialRevocationDependencies()
        )
    }

    /// Re-reads the device proof before any operation that could replace the
    /// active Auth identity. An unreadable Keychain value is treated as an
    /// unresolved handoff so a transient device-access failure cannot strand
    /// the one destination already bound on the server.
    func hasPendingPurchaseIdentityHandoffFailClosed() -> Bool {
        purchaseIdentitySourceHandoffCoordinator()
            .hasPendingHandoffFailClosed()
    }

    private func activeAnonymousSessionMatches(
        userId: String,
        expectedAuthGeneration: UInt64,
        ownedBy transition: AuthTransitionToken?
    ) -> Bool {
        guard !Task.isCancelled,
              isAuthenticated,
              authSessionGeneration == expectedAuthGeneration,
              currentUser?.isAnonymous == true,
              currentUser?.id.uuidString.caseInsensitiveCompare(userId)
                == .orderedSame,
              let sdkSession = client.auth.currentSession,
              !sdkSession.isExpired,
              sdkSession.user.isAnonymous,
              sdkSession.user.id.uuidString.caseInsensitiveCompare(userId)
                == .orderedSame else {
            return false
        }
        if let transition {
            return currentSessionMatchesAuthTransition(transition)
        }
        return activeAuthTransition == nil
    }

    private func persistOAuthProfileMetadata(
        _ profileMetadata: OAuthProfileMetadata,
        provider: AuthTransitionProvider,
        expectedUserID: UUID,
        transition: AuthTransitionToken
    ) async -> Bool {
        guard !Task.isCancelled,
              AuthTransitionPolicy.allowsOAuthMetadataMutation(
            transitionIsCurrent:
                currentSessionMatchesAuthTransition(transition),
            transitionExpectedUserID:
                authRuntimeState.activeExpectedSession?.userID,
            currentSessionUserID:
                supabaseAuthSessionService.currentSession()?.user.id,
            expectedUserID: expectedUserID
        ) else {
            return false
        }

        do {
            guard let updatedUser = try await supabaseAuthSessionService
                .updateProfileMetadata(profileMetadata) else {
                return false
            }
            guard !Task.isCancelled,
                  AuthTransitionPolicy.allowsOAuthMetadataMutation(
                transitionIsCurrent:
                    currentSessionMatchesAuthTransition(transition),
                transitionExpectedUserID:
                    authRuntimeState.activeExpectedSession?.userID,
                currentSessionUserID:
                    supabaseAuthSessionService.currentSession()?.user.id,
                expectedUserID: expectedUserID,
                updatedUserID: updatedUser.id
            ) else {
                return false
            }
            currentUser = updatedUser
            switch provider {
            case .apple:
                MerianLog.auth.debug(
                    "Apple profile metadata persisted for public author identity."
                )
            case .google:
                MerianLog.auth.debug(
                    "Google profile metadata persisted for public author identity."
                )
            }
            return true
        } catch {
            guard !Task.isCancelled,
                  !(error is CancellationError) else {
                return false
            }
            switch provider {
            case .apple:
                MerianLog.auth.debug(
                    "Apple profile metadata update failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
                )
            case .google:
                MerianLog.auth.debug(
                    "Google profile metadata update failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
                )
            }
            return false
        }
    }

    private func recoverOAuthSignInFailureIfNeeded(
        observedSessionMutation: Bool,
        sourceSession: AuthTransitionSession?,
        ownedBy transition: AuthTransitionToken
    ) async {
        guard AuthTransitionPolicy.shouldClearOAuthSessionAfterFailure(
            observedSessionMutation: observedSessionMutation,
            sourceSession: sourceSession,
            currentSession: transitionSession(
                from: supabaseAuthSessionService.currentSession()?.user
            )
        ) else {
            return
        }
        await clearLocalSessionAfterAuthFailure(
            ownedBy: transition,
            entryPolicy: .completeMutatedOAuthSession
        )
    }

    private func schedulePublicAuthorIdentityRefreshIfNeeded(for user: User) {
        publicAuthorIdentityRefreshCoordinator.scheduleIfNeeded(
            for: AuthTransitionSession(
                userID: user.id,
                isAnonymous: user.isAnonymous
            ),
            dependencies: publicAuthorIdentityRefreshDependencies()
        )
    }

    private func publicAuthorIdentityRefreshDependencies()
        -> PublicAuthorIdentityRefreshDependencies {
        let remoteService = ghostProfileMergeRemoteService
        return PublicAuthorIdentityRefreshDependencies(
            session: PublicAuthorRefreshSessionBoundary(
                isTestExecution: {
                    TestExecutionCoordinator.isRunningTests
                },
                hasActiveTransition: { [weak self] in
                    self?.isAuthTransitionInProgress ?? true
                },
                currentPublishedUserID: { [weak self] in
                    self?.currentUser?.id
                },
                transitionOwnsExpectedUser: { [weak self] transition, userID in
                    guard let self else { return false }
                    return self.ownsAuthTransition(transition)
                        && self.currentSessionMatchesAuthTransition(transition)
                        && self.client.auth.currentSession?.user.id == userID
                },
                beginUnownedAccountWork: { [weak self] userID in
                    guard let self else { return nil }
                    return try? self.beginUnownedAccountBoundWork(
                        expectedUserID: userID
                    )
                },
                finishAccountWork: { [weak self] lease in
                    self?.finishAccountBoundWork(lease)
                },
                accountWorkIsCurrent: { [weak self] lease in
                    self?.isAccountBoundWorkLeaseCurrent(lease) ?? false
                }
            ),
            operations: PublicAuthorRefreshOperationBoundary(
                completePendingGhostMerges: { [weak self] userID in
                    guard let self else { return }
                    _ = await self.ghostProfileMergeCoordinator.completePendingHandoffs(
                        expectedTargetUserID: userID,
                        dependencies: self.ghostProfileMergeDependencies()
                    )
                },
                refreshRemoteIdentity: {
                    try await remoteService.refreshIdentity()
                }
            ),
            events: PublicAuthorRefreshEventBoundary(
                publishIdentityChanged: { previousUserID, currentUserID in
                    SupabasePublicAuthorRefreshLiveEffects
                        .publishIdentityChanged(
                            previousUserID: previousUserID,
                            currentUserID: currentUserID
                        )
                }
            ),
            diagnostics: PublicAuthorRefreshDiagnostics(
                reportRefreshFailure: { error in
                    SupabasePublicAuthorRefreshLiveEffects
                        .reportRefreshFailure(error)
                }
            )
        )
    }

}

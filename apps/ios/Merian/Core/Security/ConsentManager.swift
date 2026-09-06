import Foundation
import Observation

@MainActor
@Observable
final class ConsentManager {
    private struct CancelledConsentWork {
        let synchronization: ConsentSynchronizationCoordinator.CancelledWork
        let restoration: RequiredConsentRestorationCoordinator.CancelledWork

        func wait() async {
            await synchronization.wait()
            await restoration.wait()
        }
    }

    static let shared = ConsentManager()

    private(set) var currentSessionUserId: UUID?
    private(set) var hasConfirmedCurrentAdultEligibility = false
    private(set) var hasAcceptedCurrentTerms = false
    private(set) var hasGrantedCurrentGeminiProcessing = false
    private(set) var hasGrantedCurrentPostHogAnalytics = false
    private(set) var requiredConsentRestorationState:
        RequiredConsentRestorationState = .awaitingInitialSession

    var hasCurrentRequiredConsent: Bool {
        let accountMatches = currentSessionUserId == nil
            || ledger.activeUserId == nil
            || currentSessionUserId == ledger.activeUserId
        return accountMatches
            && hasConfirmedCurrentAdultEligibility
            && hasAcceptedCurrentTerms
            && hasGrantedCurrentGeminiProcessing
    }

    var isRestoringRequiredConsent: Bool {
        guard !hasCurrentRequiredConsent else { return false }
        if case .resolved = requiredConsentRestorationState {
            return false
        }
        return true
    }

    var canRetryRequiredConsentRestoration: Bool {
        restorationCoordinator.canRetry
    }

    var pendingCloudRecordCount: Int {
        let activeUserId = ledger.activeUserId
        let pendingAdultReceipts = ledger.adultEligibilityReceipts.filter {
            guard $0.ownerUserId == activeUserId else { return false }
            if let activeUserId {
                return $0.syncedUserId != activeUserId
            }
            return true
        }.count
        let pendingTerms = ledger.termsReceipts.filter {
            guard $0.ownerUserId == activeUserId else { return false }
            if let activeUserId {
                return $0.syncedUserId != activeUserId
            }
            return true
        }.count
        let pendingEvents = ledger.aiConsentEvents.filter {
            guard $0.ownerUserId == activeUserId else { return false }
            guard $0.supersededByEventId == nil,
                  $0.supersededByRevision == nil else { return false }
            if let activeUserId {
                return $0.syncedUserId != activeUserId
            }
            return true
        }.count
        let pendingAnalyticsEvents = ledger.analyticsConsentEvents.filter {
            guard $0.ownerUserId == activeUserId else { return false }
            guard $0.supersededByEventId == nil,
                  $0.supersededByRevision == nil else { return false }
            if let activeUserId {
                return $0.syncedUserId != activeUserId
            }
            return true
        }.count
        return pendingAdultReceipts
            + pendingTerms
            + pendingEvents
            + pendingAnalyticsEvents
    }

    @ObservationIgnored private let ledgerRepository: ConsentLedgerRepository
    @ObservationIgnored private let synchronizationCoordinator:
        ConsentSynchronizationCoordinator
    @ObservationIgnored private let restorationCoordinator:
        RequiredConsentRestorationCoordinator
    @ObservationIgnored private let realtimeCoordinator: ConsentRealtimeCoordinator
    @ObservationIgnored private let currentSDKUserIdProvider: @MainActor () -> UUID?
    @ObservationIgnored private let analyticsPermissionApplier: @MainActor (
        Bool,
        String?
    ) -> Void
    @ObservationIgnored private var hasObservedSession = false
    @ObservationIgnored private var cloudReadyRequiredConsentUserId: UUID?
    @ObservationIgnored private var requiredConsentReapprovalBasisUserId: UUID?
    @ObservationIgnored private var requiredConsentReapprovalAIStreamHeadId: UUID?
    @ObservationIgnored private var inMemoryRequiredConsentReapprovalUserIds:
        Set<UUID> = []
    @ObservationIgnored private(set) var isAnalyticsSuppressedForGhostHandoff = false
    @ObservationIgnored private(set) var isAnalyticsSuppressedForAccountTransition = false
    @ObservationIgnored private var analyticsAccountTransitionGeneration: UInt = 0
    @ObservationIgnored private(set) var analyticsCloudAuthorityState:
        AnalyticsCloudAuthorityState = .localOnly

    private var ledger: LocalLedger {
        ledgerRepository.ledger
    }

    private var isLedgerStorageUncertain: Bool {
        ledgerRepository.isLedgerStorageUncertain
    }

    private var isRevocationIntentStorageUncertain: Bool {
        ledgerRepository.isRevocationIntentStorageUncertain
    }

    private var isAnalyticsWithdrawalInProgress: Bool {
        ledgerRepository.isAnalyticsWithdrawalInProgress
    }

    convenience init() {
        self.init(ledgerStore: DurableConsentLedgerStore())
    }

    convenience init(userDefaults: UserDefaults) {
        self.init(
            ledgerStore: UserDefaultsConsentLedgerStore(
                userDefaults: userDefaults
            )
        )
    }

    init(
        ledgerStore: ConsentLedgerStoring,
        remoteService: ConsentRemoteService? = nil,
        currentSDKUserIdProvider: @escaping @MainActor () -> UUID? = {
            SupabaseManager.shared.client.auth.currentSession?.user.id
        },
        analyticsPermissionApplier: @escaping @MainActor (
            Bool,
            String?
        ) -> Void = { enabled, userId in
            guard !TestExecutionCoordinator.isRunningTests else { return }
            PostHogManager.shared.setConsentGranted(enabled, userId: userId)
            AppTelemetry.setAnalyticsConsentEnabled(
                PostHogManager.shared.isCaptureEnabled
            )
        },
        synchronizationOperation: (
            @MainActor (UUID, UInt) async throws -> Void
        )? = nil,
        realtimeCoordinator: ConsentRealtimeCoordinator? = nil
    ) {
        let ledgerRepository = ConsentLedgerRepository(store: ledgerStore)
        let synchronizationCoordinator = ConsentSynchronizationCoordinator(
            ledgerRepository: ledgerRepository,
            remoteService: remoteService ?? .live,
            customSynchronizationOperation: synchronizationOperation
        )
        let restorationCoordinator = RequiredConsentRestorationCoordinator(
            dependencies: .init(
                shouldScheduleAutomaticRetry: {
                    !TestExecutionCoordinator.isRunningTests
                },
                sleep: { delay in
                    try await Task.sleep(for: .seconds(delay))
                }
            )
        )
        let realtimeCoordinator = realtimeCoordinator
            ?? ConsentRealtimeCoordinator(dependencies: .live)
        self.ledgerRepository = ledgerRepository
        self.synchronizationCoordinator = synchronizationCoordinator
        self.restorationCoordinator = restorationCoordinator
        self.realtimeCoordinator = realtimeCoordinator
        self.currentSDKUserIdProvider = currentSDKUserIdProvider
        self.analyticsPermissionApplier = analyticsPermissionApplier
        ledgerRepository.setStateChangeHandler { [weak self] in
            self?.refreshDerivedState()
        }
        restorationCoordinator.setHandlers(
            contextProvider: { [weak self] in
                guard let self else { return nil }
                return RequiredConsentRestorationCoordinator.Context(
                    synchronizationGeneration:
                        self.synchronizationCoordinator.generation,
                    observedUserId: self.currentSessionUserId,
                    sdkUserId: self.currentSDKUserIdProvider(),
                    hasCurrentRequiredConsent: self.hasCurrentRequiredConsent
                )
            },
            stateChangeHandler: { [weak self] state in
                self?.requiredConsentRestorationState = state
            },
            synchronizationHandler: { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.synchronizeWithCurrentSession()
            },
            failureReporter: { error in
                MerianLog.auth.error(
                    "Required consent restoration failed and remains unresolved; kind=\(MerianLog.errorKind(error), privacy: .public)."
                )
            }
        )
        synchronizationCoordinator.setHandlers(
            observedUserIdProvider: { [weak self] in
                self?.currentSessionUserId
            },
            sdkUserIdProvider: { [weak self] in
                self?.currentSDKUserIdProvider()
            },
            didBindUnownedRecords: { [weak self] in
                self?.applyAnalyticsPermissionToSDK()
            },
            willMergeRemoteState: { [weak self] in
                self?.cloudReadyRequiredConsentUserId = nil
            },
            didMergeRemoteState: { [weak self] result, userId in
                self?.applySynchronizationMerge(result, for: userId)
            },
            failureHandler: { [weak self] error, userId, generation in
                self?.restorationCoordinator.handleSynchronizationFailure(
                    error,
                    for: userId,
                    generation: generation
                )
            }
        )
        realtimeCoordinator.setHandlers(
            currentUserIdProvider: { [weak self] in
                self?.currentSessionUserId
            },
            synchronizationHandler: { [weak self] userId in
                guard let self else { return }
                try? await self.synchronize(for: userId)
            }
        )
        refreshDerivedState()
    }

    func confirmAdultAndAcceptCurrentTermsAndGrantGemini(
        analyticsEnabled: Bool
    ) throws {
        try ledgerRepository.ensureLedgerStorageAvailable()
        if analyticsEnabled {
            try ledgerRepository.ensureRevocationIntentStorageAvailable()
        }

        let now = Date()
        let ownerUserId = currentSessionUserId
        var candidate = ledgerRepository
            .ledgerByApplyingPendingAnalyticsRevocation(to: ledger)
        if candidate.activeUserId != ownerUserId {
            candidate.activeUserId = ownerUserId
        }

        let requiresReapproval = requiresRequiredConsentReapproval(
            for: ownerUserId
        )
        let reapprovalAIStreamHeadId: UUID?
        if requiresReapproval {
            // A fresh approval must be based on the provider head fetched
            // after the server rejection. Replaying a cached grant could
            // repair a missing row but could never supersede a legitimate
            // newer revocation from another device.
            guard let ownerUserId,
                  requiredConsentReapprovalBasisUserId == ownerUserId else {
                throw MerianError.aiConsentRequired
            }
            reapprovalAIStreamHeadId =
                requiredConsentReapprovalAIStreamHeadId
            candidate.requiredConsentReapprovalUserIds.remove(ownerUserId)
        } else {
            reapprovalAIStreamHeadId = nil
        }

        if requiresReapproval
            || currentAdultEligibilityReceipt(ownerUserId: ownerUserId) == nil {
            candidate.adultEligibilityReceipts.append(AdultEligibilityReceipt(
                id: UUID(),
                ownerUserId: ownerUserId,
                syncedUserId: nil,
                policyVersion: ConsentPolicy.adultEligibilityVersion,
                confirmedAt: now,
                confirmationMethod: .selfAttestation,
                confirmationText: ConsentPolicy.adultConfirmationText,
                platform: "ios",
                appVersion: Self.appVersion,
                appBuild: Self.appBuild,
                recordedAt: nil
            ))
        }

        if requiresReapproval
            || currentTermsReceipt(ownerUserId: ownerUserId) == nil {
            candidate.termsReceipts.append(TermsAcceptanceReceipt(
                id: UUID(),
                ownerUserId: ownerUserId,
                syncedUserId: nil,
                termsVersion: ConsentPolicy.termsVersion,
                acceptedAt: now,
                acceptanceText: ConsentPolicy.combinedAcceptanceText,
                platform: "ios",
                appVersion: Self.appVersion,
                appBuild: Self.appBuild,
                recordedAt: nil
            ))
        }

        if requiresReapproval
            || currentAIConsentEvent(ownerUserId: ownerUserId)?.eventKind
                != .granted {
            candidate.aiConsentEvents.append(AIConsentEvent(
                id: UUID(),
                ownerUserId: ownerUserId,
                syncedUserId: nil,
                provider: ConsentPolicy.geminiProvider,
                disclosureVersion: ConsentPolicy.geminiDisclosureVersion,
                eventKind: .granted,
                occurredAt: now,
                disclosureText: ConsentPolicy.geminiDisclosureText,
                actionText: ConsentPolicy.combinedAcceptanceText,
                platform: "ios",
                appVersion: Self.appVersion,
                appBuild: Self.appBuild,
                recordedAt: nil,
                causalParentId: requiresReapproval
                    ? reapprovalAIStreamHeadId
                    : ConsentAuthorityPolicy.currentAIConsentStreamHead(
                        ownerUserId: ownerUserId,
                        in: candidate
                    )?.id
            ))
        }

        let analyticsEvent = appendAnalyticsConsentEventIfNeeded(
            to: &candidate,
            enabled: analyticsEnabled,
            ownerUserId: ownerUserId,
            occurredAt: now
        )

        let persistenceEvent: AnalyticsConsentEvent?
        if let analyticsEvent {
            persistenceEvent = analyticsEvent
        } else if analyticsEnabled,
                  ledgerRepository.hasPendingAnalyticsRevocationJournal {
            persistenceEvent = ConsentAuthorityPolicy.currentAnalyticsConsentEvent(
                ownerUserId: ownerUserId,
                in: candidate
            )
        } else if !analyticsEnabled {
            persistenceEvent = ledgerRepository.pendingAnalyticsRevocationEvent(
                for: ownerUserId
            )
        } else {
            persistenceEvent = nil
        }
        if persistenceEvent?.eventKind == .revoked {
            ledgerRepository.setAnalyticsWithdrawalInProgress(true)
            applyAnalyticsPermissionToSDK()
        }
        try ledgerRepository.persistConsentChange(
            candidate,
            analyticsEvent: persistenceEvent
        )
        if requiresReapproval, let ownerUserId {
            inMemoryRequiredConsentReapprovalUserIds.remove(ownerUserId)
            cloudReadyRequiredConsentUserId = nil
            requiredConsentReapprovalBasisUserId = nil
            requiredConsentReapprovalAIStreamHeadId = nil
            refreshDerivedState()
        }
        applyAnalyticsPermissionToSDK()
        scheduleSynchronization(createAnonymousSessionIfNeeded: true)
    }

    /// Fences a server-rejected account out of AI inference and returns a
    /// completed user to the required disclosure step. The marker is durable
    /// so relaunching cannot reopen the same futile retry loop.
    @discardableResult
    func requireCurrentConsentReapprovalAfterServerRejection() throws -> Bool {
        guard let userId = currentSessionUserId,
              currentSDKUserIdProvider() == userId else {
            return false
        }

        if requiresRequiredConsentReapproval(for: userId) {
            if requiredConsentReapprovalBasisUserId != userId,
               !restorationCoordinator.belongs(to: userId) {
                restorationCoordinator.beginReconciliation(for: userId)
                refreshDerivedState()
                scheduleSynchronization(createAnonymousSessionIfNeeded: false)
            }
            return true
        }

        inMemoryRequiredConsentReapprovalUserIds.insert(userId)
        cloudReadyRequiredConsentUserId = nil
        invalidateSynchronizationWork()
        restorationCoordinator.beginReconciliation(for: userId)
        refreshDerivedState()

        var candidate = ledger
        candidate.requiredConsentReapprovalUserIds.insert(userId)
        do {
            try ledgerRepository.persistLedger(candidate)
        } catch {
            // Keep the process-local gate closed even when durable storage is
            // temporarily unavailable.
            refreshDerivedState()
            scheduleSynchronization(createAnonymousSessionIfNeeded: false)
            throw error
        }
        scheduleSynchronization(createAnonymousSessionIfNeeded: false)
        return true
    }

    func setPostHogAnalyticsEnabled(_ enabled: Bool) throws {
        try ledgerRepository.ensureLedgerStorageAvailable()
        if enabled {
            try ledgerRepository.ensureRevocationIntentStorageAvailable()
        } else {
            // Privacy withdrawal is effective in-process before either durable
            // boundary is touched.
            ledgerRepository.setAnalyticsWithdrawalInProgress(true)
            applyAnalyticsPermissionToSDK()
        }

        let ownerUserId = currentSessionUserId ?? ledger.activeUserId
        var candidate = ledgerRepository
            .ledgerByApplyingPendingAnalyticsRevocation(to: ledger)
        if candidate.activeUserId != ownerUserId {
            candidate.activeUserId = ownerUserId
        }

        let analyticsEvent = appendAnalyticsConsentEventIfNeeded(
            to: &candidate,
            enabled: enabled,
            ownerUserId: ownerUserId,
            occurredAt: Date()
        )

        let recoveryEvent: AnalyticsConsentEvent?
        if enabled,
           analyticsEvent == nil,
           ledgerRepository.hasPendingAnalyticsRevocationJournal {
            recoveryEvent = ConsentAuthorityPolicy.currentAnalyticsConsentEvent(
                ownerUserId: ownerUserId,
                in: candidate
            )
        } else if !enabled,
           analyticsEvent == nil,
           let pendingEvent = ledgerRepository.pendingAnalyticsRevocationEvent(
               for: ownerUserId
           ) {
            recoveryEvent = pendingEvent
        } else {
            recoveryEvent = analyticsEvent
        }

        guard candidate != ledger || recoveryEvent != nil else {
            ledgerRepository.setAnalyticsWithdrawalInProgress(false)
            applyAnalyticsPermissionToSDK()
            return
        }

        try ledgerRepository.persistConsentChange(
            candidate,
            analyticsEvent: recoveryEvent
        )
        applyAnalyticsPermissionToSDK()
        scheduleSynchronization(createAnonymousSessionIfNeeded: enabled)
    }

    func withdrawGeminiPermission() throws {
        guard hasGrantedCurrentGeminiProcessing else { return }
        try ledgerRepository.ensureLedgerStorageAvailable()

        let ownerUserId = currentSessionUserId ?? ledger.activeUserId
        var candidate = ledger
        candidate.activeUserId = ownerUserId
        candidate.aiConsentEvents.append(AIConsentEvent(
            id: UUID(),
            ownerUserId: ownerUserId,
            syncedUserId: nil,
            provider: ConsentPolicy.geminiProvider,
            disclosureVersion: ConsentPolicy.geminiDisclosureVersion,
            eventKind: .revoked,
            occurredAt: Date(),
            disclosureText: ConsentPolicy.geminiDisclosureText,
            actionText: ConsentPolicy.geminiWithdrawalText,
            platform: "ios",
            appVersion: Self.appVersion,
            appBuild: Self.appBuild,
            recordedAt: nil,
            causalParentId: ConsentAuthorityPolicy.currentAIConsentStreamHead(
                ownerUserId: ownerUserId,
                in: candidate
            )?.id
        ))

        try ledgerRepository.persistLedger(candidate)
        scheduleSynchronization(createAnonymousSessionIfNeeded: false)
    }

    func observeSession(userId: UUID?) {
        let previousUserId = currentSessionUserId
        if previousUserId != userId {
            invalidateSynchronizationWork()
        }
        if let userId {
            requireAuthoritativeAnalyticsRefresh(for: userId)
        } else {
            analyticsCloudAuthorityState = .localOnly
        }
        hasObservedSession = true
        currentSessionUserId = userId
        refreshDerivedState()
        let preservesPendingRestorationRetry = restorationCoordinator
            .observeSession(
                previousUserId: previousUserId,
                userId: userId,
                hasCurrentRequiredConsent: hasCurrentRequiredConsent
            )
        applyAnalyticsPermissionToSDK()
        realtimeCoordinator.ensureUpdates(for: userId)

        guard userId != nil,
              !preservesPendingRestorationRetry else {
            return
        }
        scheduleSynchronization(createAnonymousSessionIfNeeded: false)
    }

    func retryRequiredConsentRestoration() {
        guard restorationCoordinator.requestManualRetry() else { return }
        scheduleSynchronization(createAnonymousSessionIfNeeded: false)
    }

    /// Closes analytics before an OAuth operation can replace the active
    /// account. The returned generation prevents an older overlapping login
    /// from reopening capture after a newer transition has started.
    @discardableResult
    func beginAnalyticsAccountTransition() -> UInt {
        analyticsAccountTransitionGeneration &+= 1
        isAnalyticsSuppressedForAccountTransition = true
        invalidateSynchronizationWork()
        realtimeCoordinator.stopUpdates()
        applyAnalyticsPermissionToSDK()
        return analyticsAccountTransitionGeneration
    }

    /// Reconciles the actual SDK session after either OAuth success or failure,
    /// then reopens analytics only if that account has a current grant.
    @discardableResult
    func resolveAnalyticsAccountTransition(
        generation: UInt,
        userId: UUID?
    ) -> Bool {
        guard generation == analyticsAccountTransitionGeneration else {
            return false
        }
        observeSession(userId: userId)
        isAnalyticsSuppressedForAccountTransition = false
        applyAnalyticsPermissionToSDK()
        return true
    }

    /// Keeps analytics closed while a provider-bound ghost handoff is pending.
    /// SupabaseManager reconstructs this state from its durable Keychain queue
    /// before exposing a restored account's analytics permission.
    func setAnalyticsSuppressedForGhostHandoff(_ suppressed: Bool) {
        guard isAnalyticsSuppressedForGhostHandoff != suppressed else { return }
        isAnalyticsSuppressedForGhostHandoff = suppressed
        applyAnalyticsPermissionToSDK()
    }

    /// Rebinds immutable local evidence after the server has transactionally
    /// moved synchronized ghost rows to the permanent account. The transformed
    /// ledger is persisted before pending permanent-account actions are pushed
    /// and authoritative account state is fetched again.
    func rebindAndSynchronizeGhostEvidence(
        from ghostUserId: UUID,
        to permanentUserId: UUID
    ) async throws {
        setAnalyticsSuppressedForGhostHandoff(true)
        try Task.checkCancellation()

        let session = try await SupabaseManager.shared.client.auth.session
        try Task.checkCancellation()
        guard !session.user.isAnonymous,
              session.user.id == permanentUserId,
              currentSessionUserId == permanentUserId,
              SupabaseManager.shared.currentUser?.id == permanentUserId else {
            throw ConsentHandoffError.activeAccountChanged
        }
        invalidateSynchronizationWork()

        try ledgerRepository.rebindPendingAnalyticsRevocationJournal(
            from: ghostUserId,
            to: permanentUserId
        )
        do {
            try ledgerRepository.rebindLedger(
                from: ghostUserId,
                to: permanentUserId
            )
        } catch {
            throw ConsentHandoffError.ledgerPersistenceFailed
        }
        if ledgerRepository.hasPendingAnalyticsRevocationJournal {
            try ledgerRepository.recoverPendingAnalyticsRevocation()
        }
        applyAnalyticsPermissionToSDK()

        try await synchronize(for: permanentUserId)
        let finalSession = try await SupabaseManager.shared.client.auth.session
        try Task.checkCancellation()
        guard !finalSession.user.isAnonymous,
              finalSession.user.id == permanentUserId,
              currentSessionUserId == permanentUserId,
              SupabaseManager.shared.currentUser?.id == permanentUserId else {
            throw ConsentHandoffError.activeAccountChanged
        }
    }

    func ensureCloudConsentForInference() async throws {
        guard hasCurrentRequiredConsent else {
            throw MerianError.aiConsentRequired
        }

        if !SupabaseManager.shared.isAuthenticated {
            guard await SupabaseManager.shared.initializeGhostSession() != nil
            else {
                throw SupabaseAuthTransitionError.signOutInProgress
            }
        }
        let accountWorkLease = try SupabaseManager.shared
            .beginUnownedAccountBoundWork()
        defer {
            SupabaseManager.shared.finishAccountBoundWork(accountWorkLease)
        }
        let adoptionGeneration = synchronizationCoordinator.generation
        let userId = accountWorkLease.session.userID
        try Task.checkCancellation()
        guard synchronizationCoordinator.generation == adoptionGeneration,
              SupabaseManager.shared
                .isAccountBoundWorkLeaseCurrent(accountWorkLease) else {
            throw ConsentHandoffError.activeAccountChanged
        }
        if hasObservedSession,
           let currentSessionUserId,
           currentSessionUserId != userId {
            throw ConsentHandoffError.activeAccountChanged
        }
        currentSessionUserId = userId
        requireAuthoritativeAnalyticsRefresh(for: userId)
        refreshDerivedState()
        applyAnalyticsPermissionToSDK()
        realtimeCoordinator.ensureUpdates(for: userId)

        guard hasCurrentRequiredConsent else {
            throw MerianError.aiConsentRequired
        }

        try await synchronize(for: userId)
        guard SupabaseManager.shared
                .isAccountBoundWorkLeaseCurrent(accountWorkLease),
              hasCloudReadyCurrentConsent(for: userId) else {
            do {
                try requireCurrentConsentReapprovalAfterServerRejection()
            } catch {
                MerianLog.auth.error(
                    "Required consent reapproval could not be persisted; the in-memory gate remains closed; kind=\(MerianLog.errorKind(error), privacy: .public)."
                )
            }
            throw MerianError.aiConsentRequired
        }
    }

    func synchronizeWithCurrentSession() async throws {
        let supabaseManager = SupabaseManager.shared
        let accountWorkLease = try supabaseManager
            .beginUnownedAccountBoundWork()
        defer {
            supabaseManager.finishAccountBoundWork(accountWorkLease)
        }
        try await synchronizeWithCurrentSession(
            authorizationIsCurrent: {
                supabaseManager
                    .isAccountBoundWorkLeaseCurrent(accountWorkLease)
            }
        )
    }

    /// Auth-transition owners use the same consent adoption path without
    /// attempting to enter the deliberately closed ordinary-work gate. The
    /// exact transition token and expected SDK session are revalidated across
    /// every suspension; callers cannot manufacture this authority.
    func synchronizeWithCurrentSession(
        ownedBy transition: AuthTransitionToken
    ) async throws {
        let supabaseManager = SupabaseManager.shared
        try await synchronizeWithCurrentSession(
            authorizationIsCurrent: {
                supabaseManager.currentSessionMatchesAuthTransition(transition)
            }
        )
    }

    private func synchronizeWithCurrentSession(
        authorizationIsCurrent: @MainActor () -> Bool
    ) async throws {
        guard !TestExecutionCoordinator.isRunningTests else { return }
        try Task.checkCancellation()
        guard authorizationIsCurrent() else {
            throw ConsentHandoffError.activeAccountChanged
        }
        let adoptionGeneration = synchronizationCoordinator.generation
        do {
            let userId = try await SupabaseManager.shared.client.auth.session.user.id
            try Task.checkCancellation()
            guard authorizationIsCurrent(),
                  synchronizationCoordinator.generation == adoptionGeneration else {
                throw ConsentHandoffError.activeAccountChanged
            }
            guard SupabaseManager.shared.client.auth.currentSession?.user.id
                    == userId else {
                throw ConsentHandoffError.activeAccountChanged
            }
            if hasObservedSession,
               let currentSessionUserId,
               currentSessionUserId != userId {
                throw ConsentHandoffError.activeAccountChanged
            }
            currentSessionUserId = userId
            requireAuthoritativeAnalyticsRefresh(for: userId)
            refreshDerivedState()
            applyAnalyticsPermissionToSDK()
            realtimeCoordinator.ensureUpdates(for: userId)
            try await synchronize(for: userId)
            guard authorizationIsCurrent() else {
                throw ConsentHandoffError.activeAccountChanged
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let userId = currentSessionUserId {
                restorationCoordinator.handleSynchronizationFailure(
                    error,
                    for: userId,
                    generation: adoptionGeneration
                )
            }
            throw error
        }
    }

    private func scheduleSynchronization(createAnonymousSessionIfNeeded: Bool) {
        guard !TestExecutionCoordinator.isRunningTests else { return }
        guard !SupabaseManager.shared.isAuthTransitionInProgress,
              !AccountDeletionLocalCleanupStore.isPending() else {
            return
        }
        synchronizationCoordinator.schedule { @MainActor [weak self] in
            guard let self else { return }
            guard !Task.isCancelled else { return }
            if createAnonymousSessionIfNeeded {
                await SupabaseManager.shared.initializeGhostSession()
            }
            guard !Task.isCancelled else { return }
            do {
                try await self.synchronizeWithCurrentSession()
            } catch is CancellationError {
                return
            } catch {
                // synchronizeWithCurrentSession records a retryable restoration
                // failure while the identity and generation still match.
            }
        }
    }

    func synchronize(for userId: UUID) async throws {
        requireAuthoritativeAnalyticsRefresh(for: userId)
        applyAnalyticsPermissionToSDK()
        try await synchronizationCoordinator.synchronize(for: userId)
    }

    func merge(
        _ remoteState: RemoteState,
        for userId: UUID,
        generation: UInt
    ) throws {
        try synchronizationCoordinator.merge(
            remoteState,
            for: userId,
            generation: generation
        )
    }

    private func applySynchronizationMerge(
        _ result: ConsentSynchronizationMergePolicy.Result,
        for userId: UUID
    ) {
        requiredConsentReapprovalBasisUserId = userId
        requiredConsentReapprovalAIStreamHeadId =
            result.requiredConsentReapprovalAIStreamHeadId
        if result.hasAuthoritativeRequiredConsent {
            cloudReadyRequiredConsentUserId = userId
        }
        analyticsCloudAuthorityState = result.analyticsCloudAuthorityState
        applyAnalyticsPermissionToSDK()
        restorationCoordinator.resolveIfNeeded(for: userId)
    }

    static let maximumAutomaticRestorationRetries =
        RequiredConsentRestorationCoordinator.maximumAutomaticRetries

    @discardableResult
    func beginRequiredConsentRestorationRetry(
        for userId: UUID,
        generation: UInt,
        attempt: Int
    ) -> Bool {
        restorationCoordinator.beginRetry(
            for: userId,
            generation: generation,
            attempt: attempt
        )
    }

    private func requireAuthoritativeAnalyticsRefresh(for userId: UUID) {
        if case let .resolvedRemote(resolvedUserId, _) =
            analyticsCloudAuthorityState,
           resolvedUserId == userId {
            return
        }
        analyticsCloudAuthorityState = .awaitingRemote(userId: userId)
    }

    private func hasCloudReadyCurrentConsent(for userId: UUID) -> Bool {
        guard cloudReadyRequiredConsentUserId == userId,
              ledger.activeUserId == userId,
              currentAdultEligibilityReceipt(ownerUserId: userId)?.syncedUserId == userId,
              currentTermsReceipt(ownerUserId: userId)?.syncedUserId == userId,
              let event = currentAIConsentEvent(ownerUserId: userId) else {
            return false
        }
        return event.eventKind == .granted && event.syncedUserId == userId
    }

    private func currentTermsReceipt(ownerUserId: UUID?) -> TermsAcceptanceReceipt? {
        ledger.termsReceipts
            .filter {
                $0.ownerUserId == ownerUserId
                    && $0.termsVersion == ConsentPolicy.termsVersion
            }
            .max { lhs, rhs in
                (lhs.recordedAt ?? lhs.acceptedAt) < (rhs.recordedAt ?? rhs.acceptedAt)
            }
    }

    private func currentAdultEligibilityReceipt(
        ownerUserId: UUID?
    ) -> AdultEligibilityReceipt? {
        ledger.adultEligibilityReceipts
            .filter {
                $0.ownerUserId == ownerUserId
                    && $0.policyVersion == ConsentPolicy.adultEligibilityVersion
            }
            .max { lhs, rhs in
                (lhs.recordedAt ?? lhs.confirmedAt) < (rhs.recordedAt ?? rhs.confirmedAt)
            }
    }

    private func currentAIConsentEvent(ownerUserId: UUID?) -> AIConsentEvent? {
        ConsentAuthorityPolicy.currentAIConsentEvent(
            ownerUserId: ownerUserId,
            in: ledger
        )
    }

    private func currentAnalyticsConsentEvent(
        ownerUserId: UUID?
    ) -> AnalyticsConsentEvent? {
        ConsentAuthorityPolicy.currentAnalyticsConsentEvent(
            ownerUserId: ownerUserId,
            in: ledger
        )
    }

    @discardableResult
    private func appendAnalyticsConsentEventIfNeeded(
        to candidate: inout LocalLedger,
        enabled: Bool,
        ownerUserId: UUID?,
        occurredAt: Date
    ) -> AnalyticsConsentEvent? {
        let currentEvent = ConsentAuthorityPolicy.currentAnalyticsConsentEvent(
            ownerUserId: ownerUserId,
            in: candidate
        )
        let currentlyEnabled = currentEvent?.eventKind == .granted
        guard currentlyEnabled != enabled else { return nil }

        // No event is needed for the privacy-safe default state.
        guard enabled || currentEvent != nil else { return nil }

        let event = AnalyticsConsentEvent(
            id: UUID(),
            ownerUserId: ownerUserId,
            syncedUserId: nil,
            provider: ConsentPolicy.analyticsProvider,
            disclosureVersion: ConsentPolicy.analyticsDisclosureVersion,
            eventKind: enabled ? .granted : .revoked,
            occurredAt: occurredAt,
            disclosureText: ConsentPolicy.analyticsDisclosureText,
            actionText: enabled
                ? ConsentPolicy.analyticsDisclosureText
                : ConsentPolicy.analyticsWithdrawalText,
            platform: "ios",
            appVersion: Self.appVersion,
            appBuild: Self.appBuild,
            recordedAt: nil,
            causalParentId: ConsentAuthorityPolicy.currentAnalyticsConsentStreamHead(
                ownerUserId: ownerUserId,
                in: candidate
            )?.id
        )
        candidate.analyticsConsentEvents.append(event)
        return event
    }

    @discardableResult
    private func invalidateSynchronizationWork()
        -> CancelledConsentWork {
        let currentUserId = currentSessionUserId
        let hadCurrentRequiredConsent = hasCurrentRequiredConsent
        let synchronizationWork = synchronizationCoordinator.invalidate()
        cloudReadyRequiredConsentUserId = nil
        requiredConsentReapprovalBasisUserId = nil
        requiredConsentReapprovalAIStreamHeadId = nil
        let restorationWork = restorationCoordinator.invalidate(
            currentUserId: currentUserId,
            hasCurrentRequiredConsent: hadCurrentRequiredConsent
        )
        return CancelledConsentWork(
            synchronization: synchronizationWork,
            restoration: restorationWork
        )
    }

    /// Stops ordinary consent I/O and waits for synchronization, restoration,
    /// and Realtime channel teardown before an Auth-transition owner may change
    /// the SDK session. The transition gate prevents replacement scheduled work
    /// from entering during this drain.
    func cancelAndAwaitAccountBoundWorkForAuthTransition() async {
        let cancelledWork = invalidateSynchronizationWork()
        realtimeCoordinator.stopUpdates()
        await cancelledWork.wait()
        await realtimeCoordinator.awaitTeardown()
    }

    private func requiresRequiredConsentReapproval(
        for ownerUserId: UUID?
    ) -> Bool {
        guard let ownerUserId else { return false }
        return ledger.requiredConsentReapprovalUserIds.contains(ownerUserId)
            || inMemoryRequiredConsentReapprovalUserIds.contains(ownerUserId)
    }

    private func refreshDerivedState() {
        let ownerUserId: UUID?
        if let currentSessionUserId {
            ownerUserId = currentSessionUserId
        } else if hasObservedSession {
            // Once auth has explicitly resolved to no session, never expose a
            // prior account's choices. Nil still permits a newly completed,
            // not-yet-bound local action to remain effective until ghost auth
            // assigns it an account UUID.
            ownerUserId = nil
        } else {
            // During cold-start auth restoration, use the persisted account
            // evidence provisionally. The first auth event either confirms it
            // or immediately closes every gate for a different account.
            ownerUserId = ledger.activeUserId
        }
        let requiresReapproval = requiresRequiredConsentReapproval(
            for: ownerUserId
        )
        hasConfirmedCurrentAdultEligibility = !requiresReapproval
            && currentAdultEligibilityReceipt(ownerUserId: ownerUserId) != nil
        hasAcceptedCurrentTerms = !requiresReapproval
            && currentTermsReceipt(ownerUserId: ownerUserId) != nil
        hasGrantedCurrentGeminiProcessing = !requiresReapproval
            && currentAIConsentEvent(ownerUserId: ownerUserId)?.eventKind == .granted
        let hasStoredAnalyticsGrant =
            currentAnalyticsConsentEvent(ownerUserId: ownerUserId)?.eventKind == .granted
        hasGrantedCurrentPostHogAnalytics = !isLedgerStorageUncertain
            && !isRevocationIntentStorageUncertain
            && !isAnalyticsWithdrawalInProgress
            && !ledgerRepository.pendingAnalyticsRevocationApplies(
                to: ownerUserId
            )
            && hasStoredAnalyticsGrant
    }

    private func applyAnalyticsPermissionToSDK() {
        let ownerUserId = ledger.activeUserId
        let accountMatches: Bool
        if let ownerUserId {
            accountMatches = currentSessionUserId == ownerUserId
        } else {
            accountMatches = currentSessionUserId == nil
        }

        let shouldEnable = !isAnalyticsSuppressedForGhostHandoff
            && !isAnalyticsSuppressedForAccountTransition
            && analyticsCloudAuthorityState.allowsCapture(
                for: currentSessionUserId
            )
            && !isLedgerStorageUncertain
            && !isRevocationIntentStorageUncertain
            && !isAnalyticsWithdrawalInProgress
            && !ledgerRepository.pendingAnalyticsRevocationApplies(
                to: currentSessionUserId ?? ownerUserId
            )
            && accountMatches
            && hasGrantedCurrentPostHogAnalytics
        analyticsPermissionApplier(
            shouldEnable,
            shouldEnable
                ? (currentSessionUserId ?? ownerUserId)?.uuidString
                : nil
        )
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}

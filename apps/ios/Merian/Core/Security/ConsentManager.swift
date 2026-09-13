import Foundation
import Observation

@MainActor
@Observable
final class ConsentManager {
    static let shared = ConsentManager()

    private(set) var currentSessionUserId: UUID?
    private(set) var hasConfirmedCurrentAdultEligibility = false
    private(set) var hasAcceptedCurrentTerms = false
    private(set) var hasGrantedCurrentGeminiProcessing = false
    private(set) var hasGrantedCurrentPostHogAnalytics = false
    private(set) var requiredConsentRestorationState:
        RequiredConsentRestorationState = .awaitingInitialSession

    var hasCurrentRequiredConsent: Bool {
        ConsentStateProjectionPolicy.hasCurrentRequiredConsent(
            currentSessionUserId: currentSessionUserId,
            ledgerActiveUserId: ledger.activeUserId,
            hasConfirmedAdultEligibility:
                hasConfirmedCurrentAdultEligibility,
            hasAcceptedTerms: hasAcceptedCurrentTerms,
            hasGrantedGeminiProcessing:
                hasGrantedCurrentGeminiProcessing
        )
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
        ConsentStateProjectionPolicy.pendingCloudRecordCount(in: ledger)
    }

    @ObservationIgnored private let runtime: ConsentManagerRuntime
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

    private var ledgerRepository: ConsentLedgerRepository {
        runtime.ledgerRepository
    }

    private var synchronizationCoordinator: ConsentSynchronizationCoordinator {
        runtime.synchronizationCoordinator
    }

    private var restorationCoordinator: RequiredConsentRestorationCoordinator {
        runtime.restorationCoordinator
    }

    private var realtimeCoordinator: ConsentRealtimeCoordinator {
        runtime.realtimeCoordinator
    }

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
        realtimeCoordinator: ConsentRealtimeCoordinator? = nil,
        cloudSessionDependencies:
            ConsentCloudSessionCoordinator.Dependencies? = nil
    ) {
        let runtime = ConsentManagerRuntime(
            ledgerStore: ledgerStore,
            remoteService: remoteService ?? .live,
            currentSDKUserIdProvider: currentSDKUserIdProvider,
            analyticsPermissionApplier: analyticsPermissionApplier,
            synchronizationOperation: synchronizationOperation,
            realtimeCoordinator: realtimeCoordinator
                ?? ConsentRealtimeCoordinator(dependencies: .live),
            cloudSessionDependencies: cloudSessionDependencies ?? .live,
            shouldScheduleAutomaticRetry: {
                !TestExecutionCoordinator.isRunningTests
            },
            sleep: { delay in
                try await Task.sleep(for: .seconds(delay))
            },
            restorationFailureReporter: { error in
                MerianLog.auth.error(
                    "Required consent restoration failed and remains unresolved; kind=\(MerianLog.errorKind(error), privacy: .public)."
                )
            }
        )
        self.runtime = runtime
        runtime.connect(to: self)
        refreshDerivedState()
    }

    func confirmAdultAndAcceptCurrentTermsAndGrantGemini(
        analyticsEnabled: Bool
    ) throws {
        let ownerUserId = currentSessionUserId
        let requiresReapproval = requiresRequiredConsentReapproval(
            for: ownerUserId
        )
        let result = try runtime.mutationService.confirmRequiredConsent(
            analyticsEnabled: analyticsEnabled,
            context: .init(
                ownerUserId: ownerUserId,
                requiresReapproval: requiresReapproval,
                reapprovalBasisUserId:
                    requiredConsentReapprovalBasisUserId,
                reapprovalAIStreamHeadId:
                    requiredConsentReapprovalAIStreamHeadId
            ),
            refreshAnalyticsPermission: { [unowned self] in
                applyAnalyticsPermissionToSDK()
            }
        )
        if let resolvedUserId = result.resolvedReapprovalUserId {
            inMemoryRequiredConsentReapprovalUserIds.remove(resolvedUserId)
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
              runtime.currentSDKUserIdProvider() == userId else {
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
        let ownerUserId = currentSessionUserId ?? ledger.activeUserId
        let result = try runtime.mutationService.setAnalyticsEnabled(
            enabled,
            ownerUserId: ownerUserId,
            refreshAnalyticsPermission: { [unowned self] in
                applyAnalyticsPermissionToSDK()
            }
        )
        guard result == .persisted else { return }
        applyAnalyticsPermissionToSDK()
        scheduleSynchronization(createAnonymousSessionIfNeeded: enabled)
    }

    func withdrawGeminiPermission() throws {
        let ownerUserId = currentSessionUserId ?? ledger.activeUserId
        guard try runtime.mutationService.withdrawGeminiPermission(
            hasGrantedGeminiProcessing:
                hasGrantedCurrentGeminiProcessing,
            ownerUserId: ownerUserId,
        ) else { return }
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
        try await runtime.cloudSessionCoordinator
            .rebindAndSynchronizeGhostEvidence(
                from: ghostUserId,
                to: permanentUserId,
                manager: self
            )
    }

    func ensureCloudConsentForInference() async throws {
        try await runtime.cloudSessionCoordinator
            .ensureCloudConsentForInference(manager: self)
    }

    func synchronizeWithCurrentSession() async throws {
        try await runtime.cloudSessionCoordinator
            .synchronizeWithCurrentSession(manager: self)
    }

    /// Auth-transition owners use the same consent adoption path without
    /// attempting to enter the deliberately closed ordinary-work gate. The
    /// exact transition token and expected SDK session are revalidated across
    /// every suspension; callers cannot manufacture this authority.
    func synchronizeWithCurrentSession(
        ownedBy transition: AuthTransitionToken
    ) async throws {
        try await runtime.cloudSessionCoordinator
            .synchronizeWithCurrentSession(
                manager: self,
                ownedBy: transition
            )
    }

    private func scheduleSynchronization(createAnonymousSessionIfNeeded: Bool) {
        runtime.cloudSessionCoordinator.scheduleSynchronization(
            manager: self,
            createAnonymousSessionIfNeeded: createAnonymousSessionIfNeeded
        )
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

    func applySynchronizationMerge(
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

    func handleConsentLedgerStateChange() {
        refreshDerivedState()
    }

    func requiredConsentRestorationContext(
        synchronizationGeneration: UInt,
        sdkUserId: UUID?
    ) -> RequiredConsentRestorationCoordinator.Context {
        RequiredConsentRestorationCoordinator.Context(
            synchronizationGeneration: synchronizationGeneration,
            observedUserId: currentSessionUserId,
            sdkUserId: sdkUserId,
            hasCurrentRequiredConsent: hasCurrentRequiredConsent
        )
    }

    func publishRequiredConsentRestorationState(
        _ state: RequiredConsentRestorationState
    ) {
        requiredConsentRestorationState = state
    }

    func prepareForConsentSynchronizationMerge() {
        cloudReadyRequiredConsentUserId = nil
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

    func canAdoptCloudSession(_ userId: UUID) -> Bool {
        guard hasObservedSession,
              let currentSessionUserId else {
            return true
        }
        return currentSessionUserId == userId
    }

    func hasBindableUnownedRequiredConsent() -> Bool {
        guard !isLedgerStorageUncertain,
              ledger.activeUserId == nil else {
            return false
        }
        return ConsentStateProjectionPolicy.requiredConsentEvidence(
            for: nil,
            ledger: ledger,
            inMemoryUserIds: inMemoryRequiredConsentReapprovalUserIds
        ).isComplete
    }

    func adoptCloudSession(_ userId: UUID) {
        currentSessionUserId = userId
        requireAuthoritativeAnalyticsRefresh(for: userId)
        refreshDerivedState()
        applyAnalyticsPermissionToSDK()
        realtimeCoordinator.ensureUpdates(for: userId)
    }

    func prepareForGhostEvidenceRebind() {
        invalidateSynchronizationWork()
    }

    func handleConsentSynchronizationFailure(
        _ error: Error,
        for userId: UUID,
        generation: UInt
    ) {
        restorationCoordinator.handleSynchronizationFailure(
            error,
            for: userId,
            generation: generation
        )
    }

    func hasCloudReadyCurrentConsent(for userId: UUID) -> Bool {
        ConsentStateProjectionPolicy.hasCloudReadyCurrentConsent(
            for: userId,
            cloudReadyUserId: cloudReadyRequiredConsentUserId,
            ledger: ledger
        )
    }

    @discardableResult
    private func invalidateSynchronizationWork()
        -> ConsentManagerRuntime.CancelledWork {
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
        return ConsentManagerRuntime.CancelledWork(
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
        ConsentStateProjectionPolicy.requiresRequiredConsentReapproval(
            for: ownerUserId,
            ledger: ledger,
            inMemoryUserIds: inMemoryRequiredConsentReapprovalUserIds
        )
    }

    private func refreshDerivedState() {
        let ownerUserId = ConsentStateProjectionPolicy.currentOwnerUserId(
            currentSessionUserId: currentSessionUserId,
            hasObservedSession: hasObservedSession,
            ledgerActiveUserId: ledger.activeUserId
        )
        let state = ConsentStateProjectionPolicy.currentState(
            ledger: ledger,
            ownerUserId: ownerUserId,
            inMemoryReapprovalUserIds:
                inMemoryRequiredConsentReapprovalUserIds,
            isLedgerStorageUncertain: isLedgerStorageUncertain,
            isRevocationIntentStorageUncertain:
                isRevocationIntentStorageUncertain,
            isAnalyticsWithdrawalInProgress:
                isAnalyticsWithdrawalInProgress,
            pendingAnalyticsRevocationApplies: ledgerRepository
                .pendingAnalyticsRevocationApplies(to: ownerUserId)
        )
        hasConfirmedCurrentAdultEligibility =
            state.hasConfirmedAdultEligibility
        hasAcceptedCurrentTerms = state.hasAcceptedTerms
        hasGrantedCurrentGeminiProcessing =
            state.hasGrantedGeminiProcessing
        hasGrantedCurrentPostHogAnalytics =
            state.hasGrantedPostHogAnalytics
    }

    func applyAnalyticsPermissionToSDK() {
        let permission = ConsentStateProjectionPolicy.analyticsPermission(
            ledgerActiveUserId: ledger.activeUserId,
            currentSessionUserId: currentSessionUserId,
            isSuppressedForGhostHandoff:
                isAnalyticsSuppressedForGhostHandoff,
            isSuppressedForAccountTransition:
                isAnalyticsSuppressedForAccountTransition,
            cloudAuthorityState: analyticsCloudAuthorityState,
            isLedgerStorageUncertain: isLedgerStorageUncertain,
            isRevocationIntentStorageUncertain:
                isRevocationIntentStorageUncertain,
            isAnalyticsWithdrawalInProgress:
                isAnalyticsWithdrawalInProgress,
            pendingAnalyticsRevocationApplies: ledgerRepository
                .pendingAnalyticsRevocationApplies(
                    to: currentSessionUserId ?? ledger.activeUserId
                ),
            hasGrantedPostHogAnalytics:
                hasGrantedCurrentPostHogAnalytics
        )
        runtime.analyticsPermissionApplier(
            permission.isEnabled,
            permission.ownerUserId?.uuidString
        )
    }
}

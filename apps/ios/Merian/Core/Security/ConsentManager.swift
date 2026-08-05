import Foundation
import Observation
import Supabase

enum ConsentPolicy {
    static let termsVersion = "2026-08-03"
    static let adultEligibilityVersion = "2026-08-03"
    static let geminiDisclosureVersion = "2026-08-04.1"
    static let analyticsDisclosureVersion = "2026-08-04"
    static let geminiProvider = "google_gemini"
    static let analyticsProvider = "posthog"

    static let adultConfirmationText = """
    I confirm I am 18 or older.
    """

    static let geminiDisclosureText = """
    Naturebook sends observation data to Google Gemini for AI-powered identification.
    """

    static let combinedAcceptanceText = """
    I accept the terms and allow this data sharing.
    """

    static let geminiWithdrawalText = """
    I withdraw permission for Google Gemini to process future observations.
    """

    static let analyticsDisclosureText = """
    Share usage and diagnostics to help improve Naturebook.
    """

    static let analyticsWithdrawalText = """
    I withdraw permission to process future usage and diagnostics.
    """
}

enum ConsentHandoffError: LocalizedError {
    case activeAccountChanged
    case ledgerPersistenceFailed

    var errorDescription: String? {
        switch self {
        case .activeAccountChanged:
            return "The active account changed during consent migration."
        case .ledgerPersistenceFailed:
            return "The migrated consent ledger could not be persisted."
        }
    }
}

enum ConsentPersistenceError: LocalizedError {
    case storedLedgerUnavailable
    case revocationIntentInvalid
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .storedLedgerUnavailable:
            return "Naturebook could not safely access your saved consent record. Please try again."
        case .revocationIntentInvalid:
            return "Naturebook could not verify the saved analytics withdrawal. Analytics will remain off."
        case .encodingFailed:
            return "Naturebook could not prepare your consent record for secure storage."
        }
    }
}

@MainActor
@Observable
final class ConsentManager {
    enum AdultConfirmationMethod: String, Codable {
        case selfAttestation = "self_attestation"
    }

    enum AIConsentEventKind: String, Codable {
        case granted
        case revoked
    }

    enum AnalyticsConsentEventKind: String, Codable {
        case granted
        case revoked
    }

    /// Separates a cached analytics choice from permission to operate the SDK.
    /// Authenticated capture is allowed only after the active account's latest
    /// server state survives the synchronization identity and storage fences.
    enum AnalyticsCloudAuthorityState: Equatable {
        case localOnly
        case awaitingRemote(userId: UUID)
        case resolvedRemote(userId: UUID, granted: Bool)

        func allowsCapture(for sessionUserId: UUID?) -> Bool {
            switch (self, sessionUserId) {
            case (.localOnly, nil):
                return true
            case let (.resolvedRemote(resolvedUserId, true), sessionUserId?):
                return resolvedUserId == sessionUserId
            default:
                return false
            }
        }
    }

    private enum LocalLedgerCodingKeys: String, CodingKey {
        case activeUserId
        case termsReceipts
        case aiConsentEvents
        case adultEligibilityReceipts
        case analyticsConsentEvents
    }

    struct AdultEligibilityReceipt: Codable, Equatable {
        let id: UUID
        var ownerUserId: UUID?
        var syncedUserId: UUID?
        let policyVersion: String
        let confirmedAt: Date
        let confirmationMethod: AdultConfirmationMethod
        let confirmationText: String
        let platform: String
        let appVersion: String
        let appBuild: String
        var recordedAt: Date?
    }

    struct TermsAcceptanceReceipt: Codable, Equatable {
        let id: UUID
        var ownerUserId: UUID?
        var syncedUserId: UUID?
        let termsVersion: String
        let acceptedAt: Date
        let acceptanceText: String
        let platform: String
        let appVersion: String
        let appBuild: String
        var recordedAt: Date?
    }

    struct AIConsentEvent: Codable, Equatable {
        let id: UUID
        var ownerUserId: UUID?
        var syncedUserId: UUID?
        let provider: String
        let disclosureVersion: String
        let eventKind: AIConsentEventKind
        let occurredAt: Date
        let disclosureText: String
        let actionText: String
        let platform: String
        let appVersion: String
        let appBuild: String
        var recordedAt: Date?
    }

    struct AnalyticsConsentEvent: Codable, Equatable {
        let id: UUID
        var ownerUserId: UUID?
        var syncedUserId: UUID?
        let provider: String
        let disclosureVersion: String
        let eventKind: AnalyticsConsentEventKind
        let occurredAt: Date
        let disclosureText: String
        let actionText: String
        let platform: String
        let appVersion: String
        let appBuild: String
        var recordedAt: Date?
    }

    struct AnalyticsRevocationIntent: Codable, Equatable {
        var event: AnalyticsConsentEvent
    }

    struct AnalyticsRevocationJournal: Codable, Equatable {
        static let currentFormatVersion = 1

        let formatVersion: Int
        var intents: [AnalyticsRevocationIntent]

        init(intents: [AnalyticsRevocationIntent]) {
            formatVersion = Self.currentFormatVersion
            self.intents = intents
        }
    }

    struct LocalLedger: Codable, Equatable {
        var activeUserId: UUID?
        var termsReceipts: [TermsAcceptanceReceipt]
        var aiConsentEvents: [AIConsentEvent]
        var adultEligibilityReceipts: [AdultEligibilityReceipt]
        var analyticsConsentEvents: [AnalyticsConsentEvent]

        static let empty = LocalLedger(
            activeUserId: nil,
            termsReceipts: [],
            aiConsentEvents: [],
            adultEligibilityReceipts: [],
            analyticsConsentEvents: []
        )

        init(
            activeUserId: UUID?,
            termsReceipts: [TermsAcceptanceReceipt],
            aiConsentEvents: [AIConsentEvent],
            adultEligibilityReceipts: [AdultEligibilityReceipt],
            analyticsConsentEvents: [AnalyticsConsentEvent]
        ) {
            self.activeUserId = activeUserId
            self.termsReceipts = termsReceipts
            self.aiConsentEvents = aiConsentEvents
            self.adultEligibilityReceipts = adultEligibilityReceipts
            self.analyticsConsentEvents = analyticsConsentEvents
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: LocalLedgerCodingKeys.self)
            activeUserId = try container.decodeIfPresent(UUID.self, forKey: .activeUserId)
            termsReceipts = try container.decodeIfPresent(
                [TermsAcceptanceReceipt].self,
                forKey: .termsReceipts
            ) ?? []
            aiConsentEvents = try container.decodeIfPresent(
                [AIConsentEvent].self,
                forKey: .aiConsentEvents
            ) ?? []
            adultEligibilityReceipts = try container.decodeIfPresent(
                [AdultEligibilityReceipt].self,
                forKey: .adultEligibilityReceipts
            ) ?? []
            analyticsConsentEvents = try container.decodeIfPresent(
                [AnalyticsConsentEvent].self,
                forKey: .analyticsConsentEvents
            ) ?? []
        }
    }

    private struct AdultEligibilityReceiptInsert: Encodable {
        let id: UUID
        let user_id: UUID
        let policy_version: String
        let confirmed_at: String
        let confirmation_method: String
        let confirmation_text: String
        let platform: String
        let app_version: String
        let app_build: String
    }

    private struct TermsReceiptInsert: Encodable {
        let id: UUID
        let user_id: UUID
        let terms_version: String
        let accepted_at: String
        let acceptance_text: String
        let platform: String
        let app_version: String
        let app_build: String
    }

    private struct AIConsentEventInsert: Encodable {
        let id: UUID
        let user_id: UUID
        let provider: String
        let disclosure_version: String
        let event_kind: String
        let occurred_at: String
        let disclosure_text: String
        let action_text: String
        let platform: String
        let app_version: String
        let app_build: String
    }

    private struct AnalyticsConsentEventInsert: Encodable {
        let id: UUID
        let user_id: UUID
        let provider: String
        let disclosure_version: String
        let event_kind: String
        let occurred_at: String
        let disclosure_text: String
        let action_text: String
        let platform: String
        let app_version: String
        let app_build: String
    }

    private struct CloudAdultEligibilityReceipt: Decodable {
        let id: UUID
        let user_id: UUID
        let policy_version: String
        let confirmed_at: String
        let confirmation_method: String
        let confirmation_text: String
        let platform: String
        let app_version: String
        let app_build: String
        let recorded_at: String
    }

    private struct CloudTermsReceipt: Decodable {
        let id: UUID
        let user_id: UUID
        let terms_version: String
        let accepted_at: String
        let acceptance_text: String
        let platform: String
        let app_version: String
        let app_build: String
        let recorded_at: String
    }

    private struct CloudAIConsentEvent: Decodable {
        let id: UUID
        let user_id: UUID
        let provider: String
        let disclosure_version: String
        let event_kind: String
        let occurred_at: String
        let disclosure_text: String
        let action_text: String
        let platform: String
        let app_version: String
        let app_build: String
        let recorded_at: String
    }

    private struct CloudAnalyticsConsentEvent: Decodable {
        let id: UUID
        let user_id: UUID
        let provider: String
        let disclosure_version: String
        let event_kind: String
        let occurred_at: String
        let disclosure_text: String
        let action_text: String
        let platform: String
        let app_version: String
        let app_build: String
        let recorded_at: String
    }

    struct RemoteState {
        let adultEligibilityReceipt: AdultEligibilityReceipt?
        let termsReceipt: TermsAcceptanceReceipt?
        let aiConsentEvent: AIConsentEvent?
        let analyticsConsentEvent: AnalyticsConsentEvent?
    }

    static let shared = ConsentManager()

    private(set) var currentSessionUserId: UUID?
    private(set) var hasConfirmedCurrentAdultEligibility = false
    private(set) var hasAcceptedCurrentTerms = false
    private(set) var hasGrantedCurrentGeminiProcessing = false
    private(set) var hasGrantedCurrentPostHogAnalytics = false

    var hasCurrentRequiredConsent: Bool {
        let accountMatches = currentSessionUserId == nil
            || ledger.activeUserId == nil
            || currentSessionUserId == ledger.activeUserId
        return accountMatches
            && hasConfirmedCurrentAdultEligibility
            && hasAcceptedCurrentTerms
            && hasGrantedCurrentGeminiProcessing
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
            if let activeUserId {
                return $0.syncedUserId != activeUserId
            }
            return true
        }.count
        let pendingAnalyticsEvents = ledger.analyticsConsentEvents.filter {
            guard $0.ownerUserId == activeUserId else { return false }
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

    @ObservationIgnored private let ledgerStore: ConsentLedgerStoring
    @ObservationIgnored private let currentSDKUserIdProvider: @MainActor () -> UUID?
    @ObservationIgnored private let analyticsPermissionApplier: @MainActor (
        Bool,
        String?
    ) -> Void
    @ObservationIgnored private var ledger: LocalLedger
    @ObservationIgnored private var pendingAnalyticsRevocationJournal: AnalyticsRevocationJournal?
    @ObservationIgnored private var isLedgerStorageUncertain: Bool
    @ObservationIgnored private var isRevocationIntentStorageUncertain: Bool
    @ObservationIgnored private var isAnalyticsWithdrawalInProgress = false
    @ObservationIgnored private var hasObservedSession = false
    @ObservationIgnored private var scheduledSyncTask: Task<Void, Never>?
    @ObservationIgnored private var activeSyncTask: Task<Void, Error>?
    @ObservationIgnored private var activeSyncUserId: UUID?
    @ObservationIgnored private var activeSyncGeneration: UInt?
    @ObservationIgnored private var synchronizationGeneration: UInt = 0
    @ObservationIgnored private var analyticsConsentChannel: RealtimeChannelV2?
    @ObservationIgnored private var analyticsConsentChannelUserId: UUID?
    @ObservationIgnored private var analyticsConsentSubscribedUserId: UUID?
    @ObservationIgnored private var analyticsConsentListenerTask: Task<Void, Never>?
    @ObservationIgnored private var analyticsConsentRetryTask: Task<Void, Never>?
    @ObservationIgnored private var analyticsConsentRetryUserId: UUID?
    @ObservationIgnored private var analyticsConsentRetryAttempt = 0
    @ObservationIgnored private var analyticsConsentSubscriptionGeneration: UInt = 0
    @ObservationIgnored private(set) var isAnalyticsSuppressedForGhostHandoff = false
    @ObservationIgnored private(set) var isAnalyticsSuppressedForAccountTransition = false
    @ObservationIgnored private var analyticsAccountTransitionGeneration: UInt = 0
    @ObservationIgnored private(set) var analyticsCloudAuthorityState:
        AnalyticsCloudAuthorityState = .localOnly

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
        }
    ) {
        self.ledgerStore = ledgerStore
        self.currentSDKUserIdProvider = currentSDKUserIdProvider
        self.analyticsPermissionApplier = analyticsPermissionApplier

        do {
            if let data = try ledgerStore.loadLedgerData() {
                do {
                    ledger = try JSONDecoder().decode(LocalLedger.self, from: data)
                    isLedgerStorageUncertain = false
                } catch {
                    ledger = .empty
                    isLedgerStorageUncertain = true
                    MerianLog.auth.error("Consent ledger decoding failed; all consent gates remain closed.")
                }
            } else {
                ledger = .empty
                isLedgerStorageUncertain = false
            }
        } catch {
            ledger = .empty
            isLedgerStorageUncertain = true
            MerianLog.auth.error(
                "Consent ledger loading failed; all consent gates remain closed: \(error.localizedDescription, privacy: .private)"
            )
        }

        do {
            if let data = try ledgerStore.loadAnalyticsRevocationIntentData() {
                do {
                    let journal = try JSONDecoder().decode(
                        AnalyticsRevocationJournal.self,
                        from: data
                    )
                    if journal.formatVersion
                        == AnalyticsRevocationJournal.currentFormatVersion,
                       !journal.intents.isEmpty,
                       journal.intents.allSatisfy({ intent in
                           intent.event.eventKind == .revoked
                               && intent.event.provider
                                   == ConsentPolicy.analyticsProvider
                       }) {
                        pendingAnalyticsRevocationJournal = journal
                        isRevocationIntentStorageUncertain = false
                    } else {
                        pendingAnalyticsRevocationJournal = nil
                        isRevocationIntentStorageUncertain = true
                    }
                } catch {
                    pendingAnalyticsRevocationJournal = nil
                    isRevocationIntentStorageUncertain = true
                    MerianLog.auth.error("Analytics withdrawal journal decoding failed; analytics remains disabled.")
                }
            } else {
                pendingAnalyticsRevocationJournal = nil
                isRevocationIntentStorageUncertain = false
            }
        } catch {
            pendingAnalyticsRevocationJournal = nil
            isRevocationIntentStorageUncertain = true
            MerianLog.auth.error(
                "Analytics withdrawal journal loading failed; analytics remains disabled: \(error.localizedDescription, privacy: .private)"
            )
        }

        if !isLedgerStorageUncertain,
           !isRevocationIntentStorageUncertain,
           pendingAnalyticsRevocationJournal != nil {
            do {
                try recoverPendingAnalyticsRevocation()
            } catch {
                MerianLog.auth.error(
                    "Analytics withdrawal recovery remains pending: \(error.localizedDescription, privacy: .private)"
                )
            }
        }
        refreshDerivedState()
    }

    deinit {
        scheduledSyncTask?.cancel()
        activeSyncTask?.cancel()
        analyticsConsentListenerTask?.cancel()
        analyticsConsentRetryTask?.cancel()
    }

    func confirmAdultAndAcceptCurrentTermsAndGrantGemini(
        analyticsEnabled: Bool
    ) throws {
        try ensureLedgerStorageAvailable()
        if analyticsEnabled {
            try ensureRevocationIntentStorageAvailable()
        }

        let now = Date()
        let ownerUserId = currentSessionUserId
        var candidate = ledgerByApplyingPendingAnalyticsRevocation(to: ledger)
        if candidate.activeUserId != ownerUserId {
            candidate.activeUserId = ownerUserId
        }

        if currentAdultEligibilityReceipt(ownerUserId: ownerUserId) == nil {
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

        if currentTermsReceipt(ownerUserId: ownerUserId) == nil {
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

        if currentAIConsentEvent(ownerUserId: ownerUserId)?.eventKind != .granted {
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
                recordedAt: nil
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
                  pendingAnalyticsRevocationJournal != nil {
            persistenceEvent = Self.currentAnalyticsConsentEvent(
                ownerUserId: ownerUserId,
                in: candidate
            )
        } else if !analyticsEnabled {
            persistenceEvent = pendingAnalyticsRevocationEvent(
                for: ownerUserId
            )
        } else {
            persistenceEvent = nil
        }
        if persistenceEvent?.eventKind == .revoked {
            isAnalyticsWithdrawalInProgress = true
            refreshDerivedState()
            applyAnalyticsPermissionToSDK()
        }
        try persistConsentChange(
            candidate,
            analyticsEvent: persistenceEvent
        )
        applyAnalyticsPermissionToSDK()
        scheduleSynchronization(createAnonymousSessionIfNeeded: true)
    }

    func setPostHogAnalyticsEnabled(_ enabled: Bool) throws {
        try ensureLedgerStorageAvailable()
        if enabled {
            try ensureRevocationIntentStorageAvailable()
        } else {
            // Privacy withdrawal is effective in-process before either durable
            // boundary is touched.
            isAnalyticsWithdrawalInProgress = true
            refreshDerivedState()
            applyAnalyticsPermissionToSDK()
        }

        let ownerUserId = currentSessionUserId ?? ledger.activeUserId
        var candidate = ledgerByApplyingPendingAnalyticsRevocation(to: ledger)
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
           pendingAnalyticsRevocationJournal != nil {
            recoveryEvent = Self.currentAnalyticsConsentEvent(
                ownerUserId: ownerUserId,
                in: candidate
            )
        } else if !enabled,
           analyticsEvent == nil,
           let pendingEvent = pendingAnalyticsRevocationEvent(
               for: ownerUserId
           ) {
            recoveryEvent = pendingEvent
        } else {
            recoveryEvent = analyticsEvent
        }

        guard candidate != ledger || recoveryEvent != nil else {
            isAnalyticsWithdrawalInProgress = false
            refreshDerivedState()
            applyAnalyticsPermissionToSDK()
            return
        }

        try persistConsentChange(
            candidate,
            analyticsEvent: recoveryEvent
        )
        applyAnalyticsPermissionToSDK()
        scheduleSynchronization(createAnonymousSessionIfNeeded: enabled)
    }

    func withdrawGeminiPermission() throws {
        guard hasGrantedCurrentGeminiProcessing else { return }
        try ensureLedgerStorageAvailable()

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
            recordedAt: nil
        ))

        try persistLedger(candidate)
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
        applyAnalyticsPermissionToSDK()
        ensureAnalyticsConsentUpdates(for: userId)

        guard userId != nil else { return }
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
        stopAnalyticsConsentUpdates()
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

        try rebindPendingAnalyticsRevocationJournal(
            from: ghostUserId,
            to: permanentUserId
        )
        let reboundLedger = Self.rebinding(
            ledgerByApplyingPendingAnalyticsRevocation(to: ledger),
            from: ghostUserId,
            to: permanentUserId
        )
        try replaceLedgerWithVerifiedPersistence(reboundLedger)
        if pendingAnalyticsRevocationJournal != nil {
            try recoverPendingAnalyticsRevocation()
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

        await SupabaseManager.shared.initializeGhostSession()
        let adoptionGeneration = synchronizationGeneration
        let userId = try await SupabaseManager.shared.client.auth.session.user.id
        try Task.checkCancellation()
        guard synchronizationGeneration == adoptionGeneration else {
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
        ensureAnalyticsConsentUpdates(for: userId)

        guard hasCurrentRequiredConsent else {
            throw MerianError.aiConsentRequired
        }

        try await synchronize(for: userId)
        guard hasCloudReadyCurrentConsent(for: userId) else {
            throw MerianError.aiConsentRequired
        }
    }

    func synchronizeWithCurrentSession() async throws {
        guard !TestExecutionCoordinator.isRunningTests else { return }
        try Task.checkCancellation()
        let adoptionGeneration = synchronizationGeneration
        let userId = try await SupabaseManager.shared.client.auth.session.user.id
        try Task.checkCancellation()
        guard synchronizationGeneration == adoptionGeneration else {
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
        ensureAnalyticsConsentUpdates(for: userId)
        try await synchronize(for: userId)
    }

    private func scheduleSynchronization(createAnonymousSessionIfNeeded: Bool) {
        guard !TestExecutionCoordinator.isRunningTests else { return }
        scheduledSyncTask?.cancel()
        scheduledSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard !Task.isCancelled else { return }
            if createAnonymousSessionIfNeeded {
                await SupabaseManager.shared.initializeGhostSession()
            }
            guard !Task.isCancelled else { return }
            try? await self.synchronizeWithCurrentSession()
        }
    }

    private func synchronize(for userId: UUID) async throws {
        requireAuthoritativeAnalyticsRefresh(for: userId)
        applyAnalyticsPermissionToSDK()
        let generation = synchronizationGeneration
        if let activeSyncTask,
           activeSyncUserId == userId,
           activeSyncGeneration == generation {
            try await activeSyncTask.value
            return
        }

        if activeSyncUserId != userId || activeSyncGeneration != generation {
            activeSyncTask?.cancel()
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            try await self.performSynchronization(
                for: userId,
                generation: generation
            )
        }
        activeSyncTask = task
        activeSyncUserId = userId
        activeSyncGeneration = generation

        do {
            try await task.value
            if activeSyncUserId == userId,
               activeSyncGeneration == generation {
                activeSyncTask = nil
                activeSyncUserId = nil
                activeSyncGeneration = nil
            }
        } catch {
            if activeSyncUserId == userId,
               activeSyncGeneration == generation {
                activeSyncTask = nil
                activeSyncUserId = nil
                activeSyncGeneration = nil
            }
            throw error
        }
    }

    private func performSynchronization(
        for userId: UUID,
        generation: UInt
    ) async throws {
        try validateSynchronization(for: userId, generation: generation)
        if pendingAnalyticsRevocationJournal != nil {
            try recoverPendingAnalyticsRevocation()
        }

        if ledger.activeUserId == nil,
           ledger.adultEligibilityReceipts.contains(where: { $0.ownerUserId == nil })
                || ledger.termsReceipts.contains(where: { $0.ownerUserId == nil })
                || ledger.aiConsentEvents.contains(where: { $0.ownerUserId == nil })
                || ledger.analyticsConsentEvents.contains(where: { $0.ownerUserId == nil }) {
            try bindUnownedRecords(to: userId)
        }

        try activateLedger(for: userId)
        try await pushPendingRecords(for: userId, generation: generation)
        let remoteState = try await fetchRemoteState(
            for: userId,
            generation: generation
        )
        try merge(
            remoteState,
            for: userId,
            generation: generation
        )
    }

    private func activateLedger(for userId: UUID) throws {
        guard ledger.activeUserId != userId else { return }
        let candidate = Self.activating(ledger, for: userId)
        try persistLedger(candidate)
        // Account restoration remains fail-closed while local actions are
        // pushed and authoritative cloud state is refetched. `merge` applies
        // the resolved permission only after both operations succeed.
    }

    private func bindUnownedRecords(to userId: UUID) throws {
        var candidate = ledgerByApplyingPendingAnalyticsRevocation(to: ledger)
        candidate.activeUserId = userId
        for index in candidate.adultEligibilityReceipts.indices
        where candidate.adultEligibilityReceipts[index].ownerUserId == nil {
            candidate.adultEligibilityReceipts[index].ownerUserId = userId
        }
        for index in candidate.termsReceipts.indices
        where candidate.termsReceipts[index].ownerUserId == nil {
            candidate.termsReceipts[index].ownerUserId = userId
        }
        for index in candidate.aiConsentEvents.indices
        where candidate.aiConsentEvents[index].ownerUserId == nil {
            candidate.aiConsentEvents[index].ownerUserId = userId
        }
        for index in candidate.analyticsConsentEvents.indices
        where candidate.analyticsConsentEvents[index].ownerUserId == nil {
            candidate.analyticsConsentEvents[index].ownerUserId = userId
        }
        try persistLedger(candidate)
        applyAnalyticsPermissionToSDK()
    }

    private func pushPendingRecords(
        for userId: UUID,
        generation: UInt
    ) async throws {
        let adultReceipts = ledger.adultEligibilityReceipts.filter {
            $0.ownerUserId == userId && $0.syncedUserId != userId
        }
        for receipt in adultReceipts {
            try validateSynchronization(for: userId, generation: generation)
            let synchronizedReceipt = try await insertAdultEligibilityReceipt(
                receipt,
                for: userId,
                generation: generation
            )
            try validateSynchronization(for: userId, generation: generation)
            var candidate = ledger
            if let index = candidate.adultEligibilityReceipts.firstIndex(where: {
                $0.id == receipt.id
            }) {
                candidate.adultEligibilityReceipts[index] = synchronizedReceipt
            }
            try persistLedger(candidate)
        }

        let termsReceipts = ledger.termsReceipts.filter {
            $0.ownerUserId == userId && $0.syncedUserId != userId
        }
        for receipt in termsReceipts {
            try validateSynchronization(for: userId, generation: generation)
            let synchronizedReceipt = try await insertTermsReceipt(
                receipt,
                for: userId,
                generation: generation
            )
            try validateSynchronization(for: userId, generation: generation)
            var candidate = ledger
            if let index = candidate.termsReceipts.firstIndex(where: {
                $0.id == receipt.id
            }) {
                candidate.termsReceipts[index] = synchronizedReceipt
            }
            try persistLedger(candidate)
        }

        let events = ledger.aiConsentEvents.filter {
            $0.ownerUserId == userId && $0.syncedUserId != userId
        }
        for event in events {
            try validateSynchronization(for: userId, generation: generation)
            let synchronizedEvent = try await insertAIConsentEvent(
                event,
                for: userId,
                generation: generation
            )
            try validateSynchronization(for: userId, generation: generation)
            var candidate = ledger
            if let index = candidate.aiConsentEvents.firstIndex(where: {
                $0.id == event.id
            }) {
                candidate.aiConsentEvents[index] = synchronizedEvent
            }
            try persistLedger(candidate)
        }

        let analyticsEvents = ledger.analyticsConsentEvents.filter {
            $0.ownerUserId == userId && $0.syncedUserId != userId
        }
        for event in analyticsEvents {
            try validateSynchronization(for: userId, generation: generation)
            let synchronizedEvent = try await insertAnalyticsConsentEvent(
                event,
                for: userId,
                generation: generation
            )
            try validateSynchronization(for: userId, generation: generation)
            var candidate = ledger
            if let index = candidate.analyticsConsentEvents.firstIndex(where: {
                $0.id == event.id
            }) {
                candidate.analyticsConsentEvents[index] = synchronizedEvent
            }
            try persistLedger(candidate)
        }
    }

    private func insertAdultEligibilityReceipt(
        _ receipt: AdultEligibilityReceipt,
        for userId: UUID,
        generation: UInt
    ) async throws -> AdultEligibilityReceipt {
        let row = AdultEligibilityReceiptInsert(
            id: receipt.id,
            user_id: userId,
            policy_version: receipt.policyVersion,
            confirmed_at: Self.timestamp(receipt.confirmedAt),
            confirmation_method: receipt.confirmationMethod.rawValue,
            confirmation_text: receipt.confirmationText,
            platform: receipt.platform,
            app_version: receipt.appVersion,
            app_build: receipt.appBuild
        )

        do {
            try await SupabaseManager.shared.client
                .from("user_adult_eligibility_receipts")
                .insert(row)
                .execute()
            try validateSynchronization(for: userId, generation: generation)
        } catch {
            try validateSynchronization(for: userId, generation: generation)
            let existingReceipt = try await fetchAdultEligibilityReceipt(
                id: receipt.id,
                userId: userId
            )
            try validateSynchronization(for: userId, generation: generation)
            guard let existingReceipt else {
                throw error
            }
            return existingReceipt
        }

        let insertedReceipt = try await fetchAdultEligibilityReceipt(
            id: receipt.id,
            userId: userId
        )
        try validateSynchronization(for: userId, generation: generation)
        guard let insertedReceipt else {
            throw MerianError.aiConsentRequired
        }
        return insertedReceipt
    }

    private func insertTermsReceipt(
        _ receipt: TermsAcceptanceReceipt,
        for userId: UUID,
        generation: UInt
    ) async throws -> TermsAcceptanceReceipt {
        let row = TermsReceiptInsert(
            id: receipt.id,
            user_id: userId,
            terms_version: receipt.termsVersion,
            accepted_at: Self.timestamp(receipt.acceptedAt),
            acceptance_text: receipt.acceptanceText,
            platform: receipt.platform,
            app_version: receipt.appVersion,
            app_build: receipt.appBuild
        )

        do {
            try await SupabaseManager.shared.client
                .from("user_terms_acceptance_receipts")
                .insert(row)
                .execute()
            try validateSynchronization(for: userId, generation: generation)
        } catch {
            try validateSynchronization(for: userId, generation: generation)
            let existingReceipt = try await fetchTermsReceipt(
                id: receipt.id,
                userId: userId
            )
            try validateSynchronization(for: userId, generation: generation)
            guard let existingReceipt else {
                throw error
            }
            return existingReceipt
        }

        let insertedReceipt = try await fetchTermsReceipt(
            id: receipt.id,
            userId: userId
        )
        try validateSynchronization(for: userId, generation: generation)
        guard let insertedReceipt else {
            throw MerianError.aiConsentRequired
        }
        return insertedReceipt
    }

    private func insertAIConsentEvent(
        _ event: AIConsentEvent,
        for userId: UUID,
        generation: UInt
    ) async throws -> AIConsentEvent {
        let row = AIConsentEventInsert(
            id: event.id,
            user_id: userId,
            provider: event.provider,
            disclosure_version: event.disclosureVersion,
            event_kind: event.eventKind.rawValue,
            occurred_at: Self.timestamp(event.occurredAt),
            disclosure_text: event.disclosureText,
            action_text: event.actionText,
            platform: event.platform,
            app_version: event.appVersion,
            app_build: event.appBuild
        )

        do {
            try await SupabaseManager.shared.client
                .from("user_ai_consent_events")
                .insert(row)
                .execute()
            try validateSynchronization(for: userId, generation: generation)
        } catch {
            try validateSynchronization(for: userId, generation: generation)
            let existingEvent = try await fetchAIConsentEvent(
                id: event.id,
                userId: userId
            )
            try validateSynchronization(for: userId, generation: generation)
            guard let existingEvent else {
                throw error
            }
            return existingEvent
        }

        let insertedEvent = try await fetchAIConsentEvent(
            id: event.id,
            userId: userId
        )
        try validateSynchronization(for: userId, generation: generation)
        guard let insertedEvent else {
            throw MerianError.aiConsentRequired
        }
        return insertedEvent
    }

    private func insertAnalyticsConsentEvent(
        _ event: AnalyticsConsentEvent,
        for userId: UUID,
        generation: UInt
    ) async throws -> AnalyticsConsentEvent {
        let row = AnalyticsConsentEventInsert(
            id: event.id,
            user_id: userId,
            provider: event.provider,
            disclosure_version: event.disclosureVersion,
            event_kind: event.eventKind.rawValue,
            occurred_at: Self.timestamp(event.occurredAt),
            disclosure_text: event.disclosureText,
            action_text: event.actionText,
            platform: event.platform,
            app_version: event.appVersion,
            app_build: event.appBuild
        )

        do {
            try await SupabaseManager.shared.client
                .from("user_analytics_consent_events")
                .insert(row)
                .execute()
            try validateSynchronization(for: userId, generation: generation)
        } catch {
            try validateSynchronization(for: userId, generation: generation)
            let existingEvent = try await fetchAnalyticsConsentEvent(
                id: event.id,
                userId: userId
            )
            try validateSynchronization(for: userId, generation: generation)
            guard let existingEvent else {
                throw error
            }
            return existingEvent
        }

        let insertedEvent = try await fetchAnalyticsConsentEvent(
            id: event.id,
            userId: userId
        )
        try validateSynchronization(for: userId, generation: generation)
        guard let insertedEvent else {
            throw MerianError.aiConsentRequired
        }
        return insertedEvent
    }

    private func fetchAdultEligibilityReceipt(
        id: UUID,
        userId: UUID
    ) async throws -> AdultEligibilityReceipt? {
        let rows: [CloudAdultEligibilityReceipt] = try await SupabaseManager.shared.client
            .from("user_adult_eligibility_receipts")
            .select("id,user_id,policy_version,confirmed_at,confirmation_method,confirmation_text,platform,app_version,app_build,recorded_at")
            .eq("id", value: id)
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value
        return rows.first.flatMap(Self.localAdultEligibilityReceipt)
    }

    private func fetchTermsReceipt(
        id: UUID,
        userId: UUID
    ) async throws -> TermsAcceptanceReceipt? {
        let rows: [CloudTermsReceipt] = try await SupabaseManager.shared.client
            .from("user_terms_acceptance_receipts")
            .select("id,user_id,terms_version,accepted_at,acceptance_text,platform,app_version,app_build,recorded_at")
            .eq("id", value: id)
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value
        return rows.first.flatMap(Self.localTermsReceipt)
    }

    private func fetchAIConsentEvent(
        id: UUID,
        userId: UUID
    ) async throws -> AIConsentEvent? {
        let rows: [CloudAIConsentEvent] = try await SupabaseManager.shared.client
            .from("user_ai_consent_events")
            .select("id,user_id,provider,disclosure_version,event_kind,occurred_at,disclosure_text,action_text,platform,app_version,app_build,recorded_at")
            .eq("id", value: id)
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value
        return rows.first.flatMap(Self.localAIConsentEvent)
    }

    private func fetchAnalyticsConsentEvent(
        id: UUID,
        userId: UUID
    ) async throws -> AnalyticsConsentEvent? {
        let rows: [CloudAnalyticsConsentEvent] = try await SupabaseManager.shared.client
            .from("user_analytics_consent_events")
            .select("id,user_id,provider,disclosure_version,event_kind,occurred_at,disclosure_text,action_text,platform,app_version,app_build,recorded_at")
            .eq("id", value: id)
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value
        return rows.first.flatMap(Self.localAnalyticsConsentEvent)
    }

    private func fetchRemoteState(
        for userId: UUID,
        generation: UInt
    ) async throws -> RemoteState {
        async let adultRows: [CloudAdultEligibilityReceipt] = SupabaseManager.shared.client
            .from("user_adult_eligibility_receipts")
            .select("id,user_id,policy_version,confirmed_at,confirmation_method,confirmation_text,platform,app_version,app_build,recorded_at")
            .eq("user_id", value: userId)
            .eq("policy_version", value: ConsentPolicy.adultEligibilityVersion)
            .order("recorded_at", ascending: false)
            .order("id", ascending: false)
            .limit(1)
            .execute()
            .value

        async let termsRows: [CloudTermsReceipt] = SupabaseManager.shared.client
            .from("user_terms_acceptance_receipts")
            .select("id,user_id,terms_version,accepted_at,acceptance_text,platform,app_version,app_build,recorded_at")
            .eq("user_id", value: userId)
            .eq("terms_version", value: ConsentPolicy.termsVersion)
            .order("recorded_at", ascending: false)
            .order("id", ascending: false)
            .limit(1)
            .execute()
            .value

        async let eventRows: [CloudAIConsentEvent] = SupabaseManager.shared.client
            .from("user_ai_consent_events")
            .select("id,user_id,provider,disclosure_version,event_kind,occurred_at,disclosure_text,action_text,platform,app_version,app_build,recorded_at")
            .eq("user_id", value: userId)
            .eq("provider", value: ConsentPolicy.geminiProvider)
            .eq("disclosure_version", value: ConsentPolicy.geminiDisclosureVersion)
            .order("recorded_at", ascending: false)
            .order("id", ascending: false)
            .limit(1)
            .execute()
            .value

        async let analyticsRows: [CloudAnalyticsConsentEvent] = SupabaseManager.shared.client
            .from("user_analytics_consent_events")
            .select("id,user_id,provider,disclosure_version,event_kind,occurred_at,disclosure_text,action_text,platform,app_version,app_build,recorded_at")
            .eq("user_id", value: userId)
            .eq("provider", value: ConsentPolicy.analyticsProvider)
            .eq("disclosure_version", value: ConsentPolicy.analyticsDisclosureVersion)
            .order("recorded_at", ascending: false)
            .order("id", ascending: false)
            .limit(1)
            .execute()
            .value

        let resolvedRows = try await (
            adultRows,
            termsRows,
            eventRows,
            analyticsRows
        )
        try validateSynchronization(for: userId, generation: generation)

        let adultEligibilityReceipt = resolvedRows.0.first.flatMap(
            Self.localAdultEligibilityReceipt
        )
        let termsReceipt = resolvedRows.1.first.flatMap(Self.localTermsReceipt)
        let aiConsentEvent = resolvedRows.2.first.flatMap(Self.localAIConsentEvent)
        let analyticsConsentEvent = resolvedRows.3.first.flatMap(
            Self.localAnalyticsConsentEvent
        )
        return RemoteState(
            adultEligibilityReceipt: adultEligibilityReceipt,
            termsReceipt: termsReceipt,
            aiConsentEvent: aiConsentEvent,
            analyticsConsentEvent: analyticsConsentEvent
        )
    }

    func merge(
        _ remoteState: RemoteState,
        for userId: UUID,
        generation: UInt
    ) throws {
        try validateSynchronization(for: userId, generation: generation)
        var candidate = ledger

        if let receipt = remoteState.adultEligibilityReceipt {
            if let index = candidate.adultEligibilityReceipts.firstIndex(where: {
                $0.id == receipt.id
            }) {
                candidate.adultEligibilityReceipts[index] = receipt
            } else {
                candidate.adultEligibilityReceipts.append(receipt)
            }
        }

        if let receipt = remoteState.termsReceipt {
            if let index = candidate.termsReceipts.firstIndex(where: {
                $0.id == receipt.id
            }) {
                candidate.termsReceipts[index] = receipt
            } else {
                candidate.termsReceipts.append(receipt)
            }
        }

        if let event = remoteState.aiConsentEvent {
            if let index = candidate.aiConsentEvents.firstIndex(where: {
                $0.id == event.id
            }) {
                candidate.aiConsentEvents[index] = event
            } else {
                candidate.aiConsentEvents.append(event)
            }
        }

        if let event = remoteState.analyticsConsentEvent {
            if let index = candidate.analyticsConsentEvents.firstIndex(where: {
                $0.id == event.id
            }) {
                candidate.analyticsConsentEvents[index] = event
            } else {
                candidate.analyticsConsentEvents.append(event)
            }
        }

        candidate.activeUserId = userId
        try persistLedger(candidate)
        analyticsCloudAuthorityState = .resolvedRemote(
            userId: userId,
            granted: Self.isAuthoritativeAnalyticsGrant(
                remoteState.analyticsConsentEvent,
                for: userId
            )
        )
        applyAnalyticsPermissionToSDK()
    }

    private func requireAuthoritativeAnalyticsRefresh(for userId: UUID) {
        if case let .resolvedRemote(resolvedUserId, _) =
            analyticsCloudAuthorityState,
           resolvedUserId == userId {
            return
        }
        analyticsCloudAuthorityState = .awaitingRemote(userId: userId)
    }

    static func isAuthoritativeAnalyticsGrant(
        _ event: AnalyticsConsentEvent?,
        for userId: UUID
    ) -> Bool {
        guard let event else { return false }
        return event.ownerUserId == userId
            && event.syncedUserId == userId
            && event.provider == ConsentPolicy.analyticsProvider
            && event.disclosureVersion == ConsentPolicy.analyticsDisclosureVersion
            && event.eventKind == .granted
    }

    private func hasCloudReadyCurrentConsent(for userId: UUID) -> Bool {
        guard ledger.activeUserId == userId,
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
        let matchingEvents = ledger.aiConsentEvents.filter {
            $0.ownerUserId == ownerUserId
                && $0.provider == ConsentPolicy.geminiProvider
                && $0.disclosureVersion == ConsentPolicy.geminiDisclosureVersion
        }

        // A newly appended device action is authoritative for the local gate
        // until the server assigns its ordering timestamp. This keeps an
        // offline withdrawal immediate even if the device clock moves back.
        if let pendingEvent = matchingEvents.last(where: {
            $0.syncedUserId == nil || $0.syncedUserId != $0.ownerUserId
        }) {
            return pendingEvent
        }

        return matchingEvents.max { lhs, rhs in
            let lhsDate = lhs.recordedAt ?? lhs.occurredAt
            let rhsDate = rhs.recordedAt ?? rhs.occurredAt
            if lhsDate == rhsDate {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhsDate < rhsDate
        }
    }

    private func currentAnalyticsConsentEvent(
        ownerUserId: UUID?
    ) -> AnalyticsConsentEvent? {
        Self.currentAnalyticsConsentEvent(
            ownerUserId: ownerUserId,
            in: ledger
        )
    }

    private static func currentAnalyticsConsentEvent(
        ownerUserId: UUID?,
        in source: LocalLedger
    ) -> AnalyticsConsentEvent? {
        let matchingEvents = source.analyticsConsentEvents.filter {
            $0.ownerUserId == ownerUserId
                && $0.provider == ConsentPolicy.analyticsProvider
                && $0.disclosureVersion == ConsentPolicy.analyticsDisclosureVersion
        }

        // A local withdrawal must win immediately while it is waiting for the
        // account-wide event stream to assign its server ordering timestamp.
        if let pendingEvent = matchingEvents.last(where: {
            $0.syncedUserId == nil || $0.syncedUserId != $0.ownerUserId
        }) {
            return pendingEvent
        }

        return matchingEvents.max { lhs, rhs in
            let lhsDate = lhs.recordedAt ?? lhs.occurredAt
            let rhsDate = rhs.recordedAt ?? rhs.occurredAt
            if lhsDate == rhsDate {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhsDate < rhsDate
        }
    }

    @discardableResult
    private func appendAnalyticsConsentEventIfNeeded(
        to candidate: inout LocalLedger,
        enabled: Bool,
        ownerUserId: UUID?,
        occurredAt: Date
    ) -> AnalyticsConsentEvent? {
        let currentEvent = Self.currentAnalyticsConsentEvent(
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
            recordedAt: nil
        )
        candidate.analyticsConsentEvents.append(event)
        return event
    }

    static func rebinding(
        _ source: LocalLedger,
        from ghostUserId: UUID,
        to permanentUserId: UUID
    ) -> LocalLedger {
        var rebound = source
        rebound.activeUserId = permanentUserId

        for index in rebound.adultEligibilityReceipts.indices
        where rebound.adultEligibilityReceipts[index].ownerUserId == ghostUserId {
            let synchronizedUserId = rebound
                .adultEligibilityReceipts[index].syncedUserId
            rebound.adultEligibilityReceipts[index].ownerUserId = permanentUserId
            rebound.adultEligibilityReceipts[index].syncedUserId =
                reboundSynchronizationOwner(
                    synchronizedUserId,
                    from: ghostUserId,
                    to: permanentUserId
                )
        }

        for index in rebound.termsReceipts.indices
        where rebound.termsReceipts[index].ownerUserId == ghostUserId {
            let synchronizedUserId = rebound.termsReceipts[index].syncedUserId
            rebound.termsReceipts[index].ownerUserId = permanentUserId
            rebound.termsReceipts[index].syncedUserId =
                reboundSynchronizationOwner(
                    synchronizedUserId,
                    from: ghostUserId,
                    to: permanentUserId
                )
        }

        for index in rebound.aiConsentEvents.indices
        where rebound.aiConsentEvents[index].ownerUserId == ghostUserId {
            let synchronizedUserId = rebound.aiConsentEvents[index].syncedUserId
            rebound.aiConsentEvents[index].ownerUserId = permanentUserId
            rebound.aiConsentEvents[index].syncedUserId =
                reboundSynchronizationOwner(
                    synchronizedUserId,
                    from: ghostUserId,
                    to: permanentUserId
                )
        }

        for index in rebound.analyticsConsentEvents.indices
        where rebound.analyticsConsentEvents[index].ownerUserId == ghostUserId {
            let synchronizedUserId = rebound
                .analyticsConsentEvents[index].syncedUserId
            rebound.analyticsConsentEvents[index].ownerUserId = permanentUserId
            rebound.analyticsConsentEvents[index].syncedUserId =
                reboundSynchronizationOwner(
                    synchronizedUserId,
                    from: ghostUserId,
                    to: permanentUserId
                )
        }

        return rebound
    }

    static func activating(
        _ source: LocalLedger,
        for userId: UUID
    ) -> LocalLedger {
        var activated = source
        activated.activeUserId = userId
        return activated
    }

    private static func reboundSynchronizationOwner(
        _ synchronizedUserId: UUID?,
        from ghostUserId: UUID,
        to permanentUserId: UUID
    ) -> UUID? {
        guard synchronizedUserId == ghostUserId else {
            return nil
        }
        return permanentUserId
    }

    private func replaceLedgerWithVerifiedPersistence(
        _ candidate: LocalLedger
    ) throws {
        do {
            try persistLedger(candidate)
        } catch {
            throw ConsentHandoffError.ledgerPersistenceFailed
        }
    }

    private func invalidateSynchronizationWork() {
        synchronizationGeneration &+= 1
        scheduledSyncTask?.cancel()
        scheduledSyncTask = nil
        activeSyncTask?.cancel()
        activeSyncTask = nil
        activeSyncUserId = nil
        activeSyncGeneration = nil
    }

    private func validateSynchronization(
        for userId: UUID,
        generation: UInt
    ) throws {
        guard Self.isSynchronizationContextCurrent(
            expectedUserId: userId,
            expectedGeneration: generation,
            observedUserId: currentSessionUserId,
            sdkUserId: currentSDKUserIdProvider(),
            currentGeneration: synchronizationGeneration,
            isCancelled: Task.isCancelled
        ) else {
            throw CancellationError()
        }
    }

    nonisolated static func isSynchronizationContextCurrent(
        expectedUserId: UUID,
        expectedGeneration: UInt,
        observedUserId: UUID?,
        sdkUserId: UUID?,
        currentGeneration: UInt,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled
            && observedUserId == expectedUserId
            && sdkUserId == expectedUserId
            && currentGeneration == expectedGeneration
    }

    private func ensureLedgerStorageAvailable() throws {
        guard !isLedgerStorageUncertain else {
            throw ConsentPersistenceError.storedLedgerUnavailable
        }
    }

    private func ensureRevocationIntentStorageAvailable() throws {
        guard !isRevocationIntentStorageUncertain else {
            throw ConsentPersistenceError.revocationIntentInvalid
        }
    }

    private func persistLedger(_ candidate: LocalLedger) throws {
        try ensureLedgerStorageAvailable()
        let data: Data
        do {
            data = try JSONEncoder().encode(candidate)
        } catch {
            throw ConsentPersistenceError.encodingFailed
        }
        try ledgerStore.saveLedgerData(data)
        ledger = candidate
        refreshDerivedState()
    }

    private func persistConsentChange(
        _ candidate: LocalLedger,
        analyticsEvent: AnalyticsConsentEvent?
    ) throws {
        switch analyticsEvent?.eventKind {
        case .revoked:
            guard let analyticsEvent else { return }
            try persistAnalyticsRevocation(
                candidate,
                event: analyticsEvent
            )
        case .granted:
            try ensureRevocationIntentStorageAvailable()
            try persistLedger(candidate)
            if pendingAnalyticsRevocationJournal != nil {
                do {
                    try clearAnalyticsRevocationJournal()
                } catch {
                    isAnalyticsWithdrawalInProgress = true
                    refreshDerivedState()
                    throw error
                }
            }
            isAnalyticsWithdrawalInProgress = false
            refreshDerivedState()
        case nil:
            try persistLedger(candidate)
        }
    }

    private func persistAnalyticsRevocation(
        _ candidate: LocalLedger,
        event: AnalyticsConsentEvent
    ) throws {
        if pendingAnalyticsRevocationIntents.contains(where: {
            $0.event.id == event.id
        }) {
            // The write-ahead record was already verified by an earlier
            // attempt, so retry only the primary ledger boundary.
        } else {
            let intent = AnalyticsRevocationIntent(event: event)
            var journal = pendingAnalyticsRevocationJournal
                ?? AnalyticsRevocationJournal(intents: [])
            journal.intents.append(intent)
            do {
                try saveAnalyticsRevocationJournal(journal)
            } catch {
                // The atomic ledger remains a second independent way to make
                // the withdrawal durable. Only fail if both boundaries fail.
                do {
                    try persistLedger(candidate)
                    isAnalyticsWithdrawalInProgress = false
                    refreshDerivedState()
                    return
                } catch {
                    refreshDerivedState()
                    throw error
                }
            }
        }

        do {
            try persistLedger(candidate)
        } catch {
            // The intent is already durable and is deliberately retained.
            // It will be replayed on restart or the next retry.
            refreshDerivedState()
            throw error
        }

        do {
            try clearAnalyticsRevocationJournal()
        } catch {
            // Cleanup failure is privacy-safe: the durable ledger contains the
            // revocation and the retained intent continues to force analytics
            // off. Recovery will retry deletion on the next launch.
            MerianLog.auth.error(
                "Analytics withdrawal journal cleanup remains pending: \(error.localizedDescription, privacy: .private)"
            )
        }
        isAnalyticsWithdrawalInProgress = false
        refreshDerivedState()
    }

    private var pendingAnalyticsRevocationIntents: [AnalyticsRevocationIntent] {
        pendingAnalyticsRevocationJournal?.intents ?? []
    }

    private func saveAnalyticsRevocationJournal(
        _ journal: AnalyticsRevocationJournal
    ) throws {
        try ensureRevocationIntentStorageAvailable()
        let data: Data
        do {
            data = try JSONEncoder().encode(journal)
        } catch {
            throw ConsentPersistenceError.encodingFailed
        }
        try ledgerStore.saveAnalyticsRevocationIntentData(data)
        pendingAnalyticsRevocationJournal = journal
        isRevocationIntentStorageUncertain = false
        refreshDerivedState()
    }

    private func clearAnalyticsRevocationJournal() throws {
        try ledgerStore.clearAnalyticsRevocationIntentData()
        pendingAnalyticsRevocationJournal = nil
        isRevocationIntentStorageUncertain = false
        refreshDerivedState()
    }

    private func recoverPendingAnalyticsRevocation() throws {
        guard pendingAnalyticsRevocationJournal != nil else { return }
        let candidate = ledgerByApplyingPendingAnalyticsRevocation(to: ledger)
        try persistLedger(candidate)
        try clearAnalyticsRevocationJournal()
        isAnalyticsWithdrawalInProgress = false
        refreshDerivedState()
    }

    private func rebindPendingAnalyticsRevocationJournal(
        from ghostUserId: UUID,
        to permanentUserId: UUID
    ) throws {
        guard var journal = pendingAnalyticsRevocationJournal else { return }
        var didChange = false
        for index in journal.intents.indices
        where journal.intents[index].event.ownerUserId == ghostUserId {
            journal.intents[index].event.ownerUserId = permanentUserId
            journal.intents[index].event.syncedUserId =
                Self.reboundSynchronizationOwner(
                    journal.intents[index].event.syncedUserId,
                    from: ghostUserId,
                    to: permanentUserId
                )
            didChange = true
        }
        guard didChange else { return }
        try saveAnalyticsRevocationJournal(journal)
    }

    private func ledgerByApplyingPendingAnalyticsRevocation(
        to source: LocalLedger
    ) -> LocalLedger {
        guard !pendingAnalyticsRevocationIntents.isEmpty else { return source }
        var candidate = source
        for intent in pendingAnalyticsRevocationIntents
        where !candidate.analyticsConsentEvents.contains(where: {
            $0.id == intent.event.id
        }) {
            candidate.analyticsConsentEvents.append(intent.event)
        }
        return candidate
    }

    private func pendingAnalyticsRevocationEvent(
        for ownerUserId: UUID?
    ) -> AnalyticsConsentEvent? {
        for intent in pendingAnalyticsRevocationIntents.reversed() {
            let effectiveEvent = ledger.analyticsConsentEvents.first(where: {
                $0.id == intent.event.id
            }) ?? intent.event
            if effectiveEvent.ownerUserId == nil
                || effectiveEvent.ownerUserId == ownerUserId {
                return effectiveEvent
            }
        }
        return nil
    }

    private func pendingAnalyticsRevocationApplies(
        to ownerUserId: UUID?
    ) -> Bool {
        pendingAnalyticsRevocationEvent(for: ownerUserId) != nil
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
        hasConfirmedCurrentAdultEligibility =
            currentAdultEligibilityReceipt(ownerUserId: ownerUserId) != nil
        hasAcceptedCurrentTerms = currentTermsReceipt(ownerUserId: ownerUserId) != nil
        hasGrantedCurrentGeminiProcessing =
            currentAIConsentEvent(ownerUserId: ownerUserId)?.eventKind == .granted
        let hasStoredAnalyticsGrant =
            currentAnalyticsConsentEvent(ownerUserId: ownerUserId)?.eventKind == .granted
        hasGrantedCurrentPostHogAnalytics = !isLedgerStorageUncertain
            && !isRevocationIntentStorageUncertain
            && !isAnalyticsWithdrawalInProgress
            && !pendingAnalyticsRevocationApplies(to: ownerUserId)
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
            && !pendingAnalyticsRevocationApplies(
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

    private func ensureAnalyticsConsentUpdates(for userId: UUID?) {
        guard let userId else {
            stopAnalyticsConsentUpdates()
            return
        }
        guard !TestExecutionCoordinator.isRunningTests else { return }

        if analyticsConsentChannelUserId == userId,
           let channel = analyticsConsentChannel,
           analyticsConsentListenerTask != nil {
            if analyticsConsentSubscribedUserId == nil {
                // Initial subscription is still in flight.
                return
            }
            switch channel.status {
            case .subscribed, .subscribing:
                return
            case .unsubscribed, .unsubscribing:
                break
            }
        }

        let isRetryingSameUser = analyticsConsentRetryUserId == userId
        let isReplacingSameUser = analyticsConsentChannelUserId == userId
        startAnalyticsConsentUpdates(
            for: userId,
            resetRetryAttempt: !isRetryingSameUser && !isReplacingSameUser
        )
    }

    private func startAnalyticsConsentUpdates(
        for userId: UUID,
        resetRetryAttempt: Bool
    ) {
        stopAnalyticsConsentUpdates(resetRetryAttempt: resetRetryAttempt)
        let generation = analyticsConsentSubscriptionGeneration

        let channel = SupabaseManager.shared.client.channel(
            "legal-analytics-consent-\(userId.uuidString)-\(UUID().uuidString)"
        )
        let changes = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "user_analytics_consent_events",
            filter: .eq("user_id", value: userId.uuidString)
        )
        analyticsConsentChannel = channel
        analyticsConsentChannelUserId = userId
        analyticsConsentSubscribedUserId = nil

        analyticsConsentListenerTask = Task { @MainActor [weak self] in
            var shouldRetry = false
            do {
                try await channel.subscribeWithError()
                guard let self,
                      self.isCurrentAnalyticsConsentSubscription(
                          channel: channel,
                          userId: userId,
                          generation: generation
                      ) else {
                    await SupabaseManager.shared.client.removeChannel(channel)
                    return
                }
                self.analyticsConsentSubscribedUserId = userId
                self.analyticsConsentRetryAttempt = 0

                for await _ in changes {
                    guard self.isCurrentAnalyticsConsentSubscription(
                        channel: channel,
                        userId: userId,
                        generation: generation
                    ) else {
                        break
                    }
                    try? await self.synchronize(for: userId)
                }
                shouldRetry = !Task.isCancelled
            } catch is CancellationError {
                shouldRetry = false
            } catch {
                shouldRetry = !Task.isCancelled
                MerianLog.general.debug(
                    "Analytics consent Realtime subscription failed: \(error.localizedDescription, privacy: .private)"
                )
            }

            await self?.finishAnalyticsConsentSubscription(
                channel: channel,
                userId: userId,
                generation: generation,
                shouldRetry: shouldRetry
            )
        }
    }

    private func stopAnalyticsConsentUpdates(
        resetRetryAttempt: Bool = true
    ) {
        analyticsConsentSubscriptionGeneration &+= 1
        analyticsConsentRetryTask?.cancel()
        analyticsConsentRetryTask = nil
        analyticsConsentRetryUserId = nil
        analyticsConsentListenerTask?.cancel()
        analyticsConsentListenerTask = nil
        analyticsConsentSubscribedUserId = nil
        analyticsConsentChannelUserId = nil
        if resetRetryAttempt {
            analyticsConsentRetryAttempt = 0
        }

        if let channel = analyticsConsentChannel {
            analyticsConsentChannel = nil
            Task {
                await SupabaseManager.shared.client.removeChannel(channel)
            }
        }
    }

    private func isCurrentAnalyticsConsentSubscription(
        channel: RealtimeChannelV2,
        userId: UUID,
        generation: UInt
    ) -> Bool {
        !Task.isCancelled
            && analyticsConsentSubscriptionGeneration == generation
            && analyticsConsentChannel === channel
            && analyticsConsentChannelUserId == userId
            && currentSessionUserId == userId
    }

    private func finishAnalyticsConsentSubscription(
        channel: RealtimeChannelV2,
        userId: UUID,
        generation: UInt,
        shouldRetry: Bool
    ) async {
        await SupabaseManager.shared.client.removeChannel(channel)
        guard analyticsConsentSubscriptionGeneration == generation,
              analyticsConsentChannel === channel,
              analyticsConsentChannelUserId == userId else {
            return
        }

        analyticsConsentChannel = nil
        analyticsConsentChannelUserId = nil
        analyticsConsentSubscribedUserId = nil
        analyticsConsentListenerTask = nil
        guard shouldRetry,
              currentSessionUserId == userId else {
            return
        }
        scheduleAnalyticsConsentRetry(for: userId)
    }

    private func scheduleAnalyticsConsentRetry(for userId: UUID) {
        analyticsConsentRetryAttempt += 1
        let delay = Self.analyticsConsentRetryDelay(
            attempt: analyticsConsentRetryAttempt
        )
        let generation = analyticsConsentSubscriptionGeneration
        analyticsConsentRetryUserId = userId
        analyticsConsentRetryTask?.cancel()
        analyticsConsentRetryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  self.analyticsConsentSubscriptionGeneration == generation,
                  self.analyticsConsentRetryUserId == userId,
                  self.currentSessionUserId == userId else {
                return
            }
            self.analyticsConsentRetryTask = nil
            self.analyticsConsentRetryUserId = nil
            self.startAnalyticsConsentUpdates(
                for: userId,
                resetRetryAttempt: false
            )
        }
    }

    static func analyticsConsentRetryDelay(attempt: Int) -> Double {
        let boundedExponent = min(max(attempt - 1, 0), 5)
        return min(pow(2, Double(boundedExponent)), 30)
    }

    private static func localAdultEligibilityReceipt(
        _ row: CloudAdultEligibilityReceipt
    ) -> AdultEligibilityReceipt? {
        guard let method = AdultConfirmationMethod(rawValue: row.confirmation_method),
              let confirmedAt = date(row.confirmed_at),
              let recordedAt = date(row.recorded_at) else {
            return nil
        }
        return AdultEligibilityReceipt(
            id: row.id,
            ownerUserId: row.user_id,
            syncedUserId: row.user_id,
            policyVersion: row.policy_version,
            confirmedAt: confirmedAt,
            confirmationMethod: method,
            confirmationText: row.confirmation_text,
            platform: row.platform,
            appVersion: row.app_version,
            appBuild: row.app_build,
            recordedAt: recordedAt
        )
    }

    private static func localTermsReceipt(
        _ row: CloudTermsReceipt
    ) -> TermsAcceptanceReceipt? {
        guard let acceptedAt = date(row.accepted_at),
              let recordedAt = date(row.recorded_at) else {
            return nil
        }
        return TermsAcceptanceReceipt(
            id: row.id,
            ownerUserId: row.user_id,
            syncedUserId: row.user_id,
            termsVersion: row.terms_version,
            acceptedAt: acceptedAt,
            acceptanceText: row.acceptance_text,
            platform: row.platform,
            appVersion: row.app_version,
            appBuild: row.app_build,
            recordedAt: recordedAt
        )
    }

    private static func localAIConsentEvent(
        _ row: CloudAIConsentEvent
    ) -> AIConsentEvent? {
        guard let eventKind = AIConsentEventKind(rawValue: row.event_kind),
              let occurredAt = date(row.occurred_at),
              let recordedAt = date(row.recorded_at) else {
            return nil
        }
        return AIConsentEvent(
            id: row.id,
            ownerUserId: row.user_id,
            syncedUserId: row.user_id,
            provider: row.provider,
            disclosureVersion: row.disclosure_version,
            eventKind: eventKind,
            occurredAt: occurredAt,
            disclosureText: row.disclosure_text,
            actionText: row.action_text,
            platform: row.platform,
            appVersion: row.app_version,
            appBuild: row.app_build,
            recordedAt: recordedAt
        )
    }

    private static func localAnalyticsConsentEvent(
        _ row: CloudAnalyticsConsentEvent
    ) -> AnalyticsConsentEvent? {
        guard let eventKind = AnalyticsConsentEventKind(rawValue: row.event_kind),
              let occurredAt = date(row.occurred_at),
              let recordedAt = date(row.recorded_at) else {
            return nil
        }
        return AnalyticsConsentEvent(
            id: row.id,
            ownerUserId: row.user_id,
            syncedUserId: row.user_id,
            provider: row.provider,
            disclosureVersion: row.disclosure_version,
            eventKind: eventKind,
            occurredAt: occurredAt,
            disclosureText: row.disclosure_text,
            actionText: row.action_text,
            platform: row.platform,
            appVersion: row.app_version,
            appBuild: row.app_build,
            recordedAt: recordedAt
        )
    }

    private static func timestamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    private static func date(_ timestamp: String) -> Date? {
        if let date = try? Date(
            timestamp,
            strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        ) {
            return date
        }
        return try? Date(
            timestamp,
            strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: false)
        )
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}

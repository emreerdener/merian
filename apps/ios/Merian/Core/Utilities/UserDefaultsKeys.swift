import Combine
import Foundation
import Observation
import Supabase
import SwiftData
import UIKit

// MARK: - UserDefaults Key Constants
/// Single source of truth for all UserDefaults / AppStorage key strings.
/// Using these constants prevents silent key mismatches across sites that
/// read and write the same preference value.
enum UserDefaultsKeys {
    /// Versioned prefix for account-isolated, source-agnostic capture goal caches.
    static let captureGoalContextPrefix = "captureGoalContext.v1."
    /// Versioned prefix for account-isolated first Field trip achievement progress.
    static let firstFieldTripAchievementProgressPrefix = "firstFieldTripAchievementProgress.v1."
    /// Whether onboarding has completed and the full app lifecycle may start.
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    /// Versioned local ledger for adult, Terms, AI, and analytics consent evidence.
    static let legalConsentLedger = "legalConsentLedger.v1"
    /// The current theme mode selection persisted via AppStorage.
    static let themeMode = "themeMode"
    /// Whether Explore should be presented over the Capture workspace on a fresh app launch.
    static let opensExploreOnLaunch = "opensExploreOnLaunch"
    /// Whether multi-capture mode is enabled for the camera workflow.
    static let isMultiCaptureEnabled = "isMultiCaptureEnabled"
    /// Whether scans should wait for explicit user confirmation before submission.
    static let requiresScanConfirmation = "requiresScanConfirmation"
    /// Whether the active capture-goal indicator is visible over the Scan camera.
    static let showsCaptureGoalProgress = "showsCaptureGoalProgress"
    /// Legacy pre-migration key for the old multi-image scan mode toggle.
    static let legacyMultiImageScanMode = "multiImageScanMode"
    /// Whether expedition mode is active for low-power field capture sessions.
    static let isExpeditionModeActive = "isExpeditionModeActive"
    /// Whether haptic feedback is enabled globally.
    static let isHapticsEnabled = "isHapticsEnabled"
    /// Whether the user has an unseen scan result waiting in the Scans sheet.
    static let hasUnseenScan = "hasUnseenScan"
    /// Whether discovery-complete notifications are enabled.
    static let isPushNotificationsEnabled = "isPushNotificationsEnabled"
    /// Whether the OS has granted notification authorization for this app.
    static let hasPushNotificationAuthorization = "hasPushNotificationAuthorization"
    /// Whether achievement notifications are enabled.
    static let isAchievementNotificationsEnabled = "isAchievementNotificationsEnabled"
    /// Whether Explore activity notifications are enabled.
    static let isExploreNotificationsEnabled = "isExploreNotificationsEnabled"
    /// Whether Explore comment mention push notifications are enabled.
    static let isExploreCommentMentionNotificationsEnabled = "isExploreCommentMentionNotificationsEnabled"
    /// Whether Community identification push notifications are enabled.
    static let isCommunityIdentificationNotificationsEnabled = "isCommunityIdentificationNotificationsEnabled"
    /// Last APNs device token registered by the app, stored as lowercase hex.
    static let remotePushDeviceToken = "remotePushDeviceToken"
    /// Whether the live on-device inference viewfinder pass is paused (Legacy Viewfinder mode).
    static let isLiveInferencePaused = "isLiveInferencePaused"
    /// Whether swipe-to-zoom direction is inverted (down = zoom in, up = zoom out).
    static let invertZoomDirection = "invertZoomDirection"
    /// Whether the zoom slider is placed on the left side of the viewfinder instead of the right.
    static let zoomSideLeft = "zoomSideLeft"
    /// Whether the zoom slider overlay is visible on the camera viewfinder.
    static let zoomSliderVisible = "zoomSliderVisible"
    /// Whether captured photos and videos should also be saved to the iOS camera roll.
    static let saveToCameraRoll = "saveToCameraRoll"
    /// Whether live audio placement hints are visible while recording.
    static let audioHintsEnabled = "audioHintsEnabled"
    /// User-selected column count for the scans library grid.
    static let gridColumns = "gridColumns"
    /// Whether local `ScanCollection` changes are pending a push to the `sync-collections` Edge function.
    static let needsCollectionSync = "needsCollectionSync"
    /// Locally hidden smart collection ids, stored as a string array.
    static let hiddenSmartCollectionIDs = "hiddenSmartCollectionIDs"
    /// Prefix for the per-account unavailable-media overview dismissal signature.
    static let dismissedUnavailableMediaOverviewSignaturePrefix =
        "dismissedUnavailableMediaOverviewSignature.v1."
    /// Prefix for the per-account Profile published-media notice dismissal signature.
    static let dismissedProfilePublicationRecoverySignaturePrefix =
        "dismissedProfilePublicationRecoverySignature.v1."
    /// Prefix for per-species preferred common name. Append the scientific name to form the full key.
    /// e.g. `"speciesPreferredName_Gaillardia pulchella"` → user's chosen display name.
    static let speciesPreferredNamePrefix = "speciesPreferredName_"
    /// Dictionary of scientific name → delete timestamp for preferred-name clears waiting for cloud sync.
    static let pendingSpeciesPreferredNameDeletes = "pendingSpeciesPreferredNameDeletes"
    /// Last wall-clock attempt for preferred-name cloud sync.
    static let speciesPreferredNameSyncLastAttemptAt = "speciesPreferredNameSyncLastAttemptAt"
    /// Last successful preferred-name cloud sync completion time.
    static let speciesPreferredNameSyncLastSuccessAt = "speciesPreferredNameSyncLastSuccessAt"
    /// Last preferred-name cloud sync state: running, success, failure, or skipped.
    static let speciesPreferredNameSyncStatus = "speciesPreferredNameSyncStatus"
    /// Human-readable preferred-name cloud sync failure/skip reason for support diagnostics.
    static let speciesPreferredNameSyncMessage = "speciesPreferredNameSyncMessage"
    /// Number of preferred-name rows pushed during the last successful cloud sync.
    static let speciesPreferredNameSyncLastPushedCount = "speciesPreferredNameSyncLastPushedCount"
    /// Number of preferred-name rows pulled during the last successful cloud sync.
    static let speciesPreferredNameSyncLastPulledCount = "speciesPreferredNameSyncLastPulledCount"
    /// Whether the user has been presented with the notification request post-identification.
    static let hasPromptedForNotificationsPostIdent = "hasPromptedForNotificationsPostIdent"
    /// The user's customized ordering of the primary capture tabs, stored as a comma-separated string.
    static let captureModeOrder = "captureModeOrder"
    /// Whether the user has seen the one-time Explore onboarding prompt.
    static let hasSeenExploreOnboarding = "hasSeenExploreOnboarding"
    /// Whether the user has dismissed the Explore Identify requests banner.
    static let hasDismissedIdentifyRequestsBanner = "hasDismissedIdentifyRequestsBanner"
    /// Whether the user has dismissed the Explore Identify activity banner.
    static let hasDismissedIdentifyActivityBanner = "hasDismissedIdentifyActivityBanner"
    /// Whether the Explore feed has a newer post than the one the user most recently saw.
    static let hasUnseenExplorePost = "hasUnseenExplorePost"
    /// One-time feedback survey campaign id the user dismissed.
    static let feedbackSurveyDismissedCampaignId = "feedbackSurveyDismissedCampaignId"
    /// One-time feedback survey campaign id the user submitted.
    static let feedbackSurveySubmittedCampaignId = "feedbackSurveySubmittedCampaignId"
    /// Seconds-since-epoch timestamp for the latest feedback survey submission.
    static let feedbackSurveySubmittedAt = "feedbackSurveySubmittedAt"
    /// Prefix for per-scan Explore share state. Append the local `scanId` to form the full key.
    /// e.g. `"sharedExplorePostId_1234-uuid"` → the published Explore post id for that scan.
    static let sharedExplorePostIdPrefix = "sharedExplorePostId_"
    /// Legacy prefix for per-scan field notes used by the temporary bridge implementation.
    /// Retained so existing local drafts can be migrated into SwiftData-backed scan records.
    static let fieldNotesPrefix = "fieldNotes_"
    /// The `sharedAt` timestamp of the newest Explore post successfully loaded by the user.
    static let lastSeenExplorePostSharedAt = "lastSeenExplorePostSharedAt"
    /// Whether foreground inference-complete banners should be suppressed while the user is already viewing results.
    static let suppressInferenceBanners = "suppressInferenceBanners"
    /// Seconds-since-epoch timestamp recorded when the app moves to the background.
    static let lastBackgroundedDate = "lastBackgroundedDate"
    /// Throttle marker for the last historical cloud-to-local sync attempt.
    static let lastHistoricalSyncDate = "lastHistoricalSyncDate"
    /// A persisted 24-hour TTL dictionary of species that have already completed enrichment.
    static let enrichedSpeciesTimestamps = "enrichedSpeciesTimestamps"
    /// Version marker for one-time local similar-species cache resets.
    static let localLookalikesCacheResetVersion = "localLookalikesCacheResetVersion"
    /// Test-suite compatibility key. Production withdrawal journals are stored
    /// independently from the ledger in Keychain.
    static let analyticsRevocationIntent = "analyticsRevocationIntent.v1"
    /// Durable notice for legacy Apple-linked accounts whose server-side
    /// deletion cannot programmatically revoke a token that was never stored.
    static let pendingManualAppleRevocationNotice =
        "pendingManualAppleRevocationNotice.v1"
    /// Durable, identity-free marker written only after the backend accepts an
    /// account-deletion request. Startup retries local cache removal until it
    /// succeeds, so a termination after server acceptance cannot preserve
    /// account-owned data on the device indefinitely.
    static let pendingLocalAccountDeletionCleanup =
        "pendingLocalAccountDeletionCleanup.v1"
}

enum ManualAppleRevocationNoticeStore {
    static func isPending(
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        userDefaults.bool(
            forKey: UserDefaultsKeys.pendingManualAppleRevocationNotice
        )
    }

    @MainActor
    static func record(
        userDefaults: UserDefaults = .standard,
        eventSender: (any AppEventSending)? = nil
    ) {
        let eventSender = eventSender ?? AppDIContainer.shared.appEventPublisher
        userDefaults.set(
            true,
            forKey: UserDefaultsKeys.pendingManualAppleRevocationNotice
        )
        eventSender.send(.manualAppleRevocationNoticeRequired)
    }

    static func resolve(userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(
            forKey: UserDefaultsKeys.pendingManualAppleRevocationNotice
        )
    }
}

enum AccountDeletionLocalRecoveryState: String, Equatable {
    /// The user confirmed deletion and the durable barrier was written before
    /// Keychain capability creation. Relaunch may create or reuse the proof only
    /// while the exact cached Auth session still exists.
    case capabilityPreparationPending = "capability_preparation_pending"
    /// Protocol v2 preparation was acknowledged without creating a deletion
    /// job. The commit request has not started; recovery may cancel this state
    /// without erasing local data.
    case capabilityPreparedPending = "capability_prepared_pending"
    /// The authenticated intake may be in flight or may have committed without
    /// returning a receipt. The exact cached Auth session must be retained so
    /// the idempotent request can be retried after relaunch.
    case intakePending = "intake_pending"
    /// The server returned its durable receipt. Local Auth and SwiftData may be
    /// erased, and the marker is cleared only after both are verified.
    case cleanupPending = "cleanup_pending"
    /// Current protocol: the authenticated request may have committed and the
    /// device-held recovery capability must remain readable before any local
    /// account lifecycle can resume.
    case capabilityIntakePending = "capability_intake_pending"
    /// Current protocol: server acceptance was recovered or received. Local
    /// erasure must be acknowledged with the same capability before state is
    /// retired.
    case capabilityCleanupPending = "capability_cleanup_pending"
    /// The server acknowledged device cleanup. Relaunch re-verifies local Auth
    /// absence and idempotent data purge before capability/marker retirement;
    /// a crash after Keychain deletion can finish without the removed proof.
    case capabilityRetirementPending = "capability_retirement_pending"
    /// Durable deletion intake was definitively rejected before it could
    /// commit. Relaunch may retire only the unused Keychain proof and marker;
    /// it must not sign out or erase local data.
    case capabilityRejectionRetirementPending =
        "capability_rejection_retirement_pending"
    /// Keychain contained a proof while the UserDefaults phase was absent or
    /// secure storage could not be inspected before Auth bootstrap. Recovery is
    /// capability-only and must never submit a deletion for the current session.
    case capabilityLookupPending = "capability_lookup_pending"

    var isIntakePending: Bool {
        self == .intakePending ||
            self == .capabilityPreparationPending ||
            self == .capabilityPreparedPending ||
            self == .capabilityIntakePending
    }

    var requiresRecoveryCapability: Bool {
        self == .capabilityIntakePending ||
            self == .capabilityCleanupPending
    }
}

enum AccountDeletionLocalCleanupStore {
    static func state(
        userDefaults: UserDefaults = .standard
    ) -> AccountDeletionLocalRecoveryState? {
        let key = UserDefaultsKeys.pendingLocalAccountDeletionCleanup
        let storedValue = userDefaults.object(forKey: key)
        if let rawValue = storedValue as? String {
            // An unknown future state remains fail-closed at the non-destructive
            // intake boundary. This build must re-confirm server acceptance,
            // never infer permission to erase local state from an unknown value.
            return AccountDeletionLocalRecoveryState(rawValue: rawValue)
                ?? .intakePending
        }
        // Builds predating the two-phase protocol stored a Boolean only after
        // server acceptance. Preserve that recovery meaning during upgrade.
        if let legacyAcceptedMarker = storedValue as? Bool,
           legacyAcceptedMarker {
            return .cleanupPending
        }
        return nil
    }

    static func isPending(
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        state(userDefaults: userDefaults) != nil
    }

    @discardableResult
    @MainActor
    static func recordIntakePending(
        userDefaults: UserDefaults = .standard,
        eventSender: (any AppEventSending)? = nil
    ) -> Bool {
        record(
            .capabilityIntakePending,
            userDefaults: userDefaults,
            eventSender: eventSender
        )
    }

    @discardableResult
    @MainActor
    static func recordCapabilityPreparationPending(
        userDefaults: UserDefaults = .standard,
        eventSender: (any AppEventSending)? = nil
    ) -> Bool {
        record(
            .capabilityPreparationPending,
            userDefaults: userDefaults,
            eventSender: eventSender
        )
    }

    @discardableResult
    @MainActor
    static func recordCapabilityLookupPending(
        userDefaults: UserDefaults = .standard,
        eventSender: (any AppEventSending)? = nil,
        emitEvent: Bool = true
    ) -> Bool {
        record(
            .capabilityLookupPending,
            userDefaults: userDefaults,
            eventSender: eventSender,
            emitEvent: emitEvent
        )
    }

    @discardableResult
    @MainActor
    static func recordCapabilityPreparedPending(
        userDefaults: UserDefaults = .standard,
        eventSender: (any AppEventSending)? = nil
    ) -> Bool {
        record(
            .capabilityPreparedPending,
            userDefaults: userDefaults,
            eventSender: eventSender
        )
    }

    @discardableResult
    @MainActor
    static func recordCleanupPending(
        userDefaults: UserDefaults = .standard,
        eventSender: (any AppEventSending)? = nil
    ) -> Bool {
        record(
            .capabilityCleanupPending,
            userDefaults: userDefaults,
            eventSender: eventSender
        )
    }

    @discardableResult
    @MainActor
    static func recordCapabilityRetirementPending(
        userDefaults: UserDefaults = .standard,
        eventSender: (any AppEventSending)? = nil
    ) -> Bool {
        record(
            .capabilityRetirementPending,
            userDefaults: userDefaults,
            eventSender: eventSender
        )
    }

    @discardableResult
    @MainActor
    static func recordCapabilityRejectionRetirementPending(
        userDefaults: UserDefaults = .standard,
        eventSender: (any AppEventSending)? = nil
    ) -> Bool {
        record(
            .capabilityRejectionRetirementPending,
            userDefaults: userDefaults,
            eventSender: eventSender
        )
    }

    /// Compatibility spelling for call sites that already hold a server
    /// receipt. New deletion requests must persist `intakePending` first.
    @discardableResult
    @MainActor
    static func record(
        userDefaults: UserDefaults = .standard,
        eventSender: (any AppEventSending)? = nil
    ) -> Bool {
        record(
            .cleanupPending,
            userDefaults: userDefaults,
            eventSender: eventSender
        )
    }

    @discardableResult
    @MainActor
    private static func record(
        _ state: AccountDeletionLocalRecoveryState,
        userDefaults: UserDefaults,
        eventSender: (any AppEventSending)?,
        emitEvent: Bool = true
    ) -> Bool {
        userDefaults.set(
            state.rawValue,
            forKey: UserDefaultsKeys.pendingLocalAccountDeletionCleanup
        )
        // This marker is the local side of an irreversible request. Force the
        // preferences domain to disk, then read it back before allowing the
        // network mutation to start.
        guard userDefaults.synchronize(),
              self.state(userDefaults: userDefaults) == state else {
            return false
        }
        if emitEvent {
            let sender = eventSender ?? AppDIContainer.shared.appEventPublisher
            sender.send(.accountDeletionRecoveryStateChanged)
        }
        return true
    }

    @discardableResult
    @MainActor
    static func resolve(
        userDefaults: UserDefaults = .standard,
        eventSender: (any AppEventSending)? = nil
    ) -> Bool {
        userDefaults.removeObject(
            forKey: UserDefaultsKeys.pendingLocalAccountDeletionCleanup
        )
        guard userDefaults.synchronize(),
              state(userDefaults: userDefaults) == nil else {
            return false
        }
        let sender = eventSender ?? AppDIContainer.shared.appEventPublisher
        sender.send(.accountDeletionRecoveryStateChanged)
        return true
    }
}

enum KeychainKeys {
    /// Distinguishes OAuth-authenticated users from anonymous ghost sessions.
    static let hasAuthenticatedOAuth = "Merian_HasAuthenticatedOAuth"
    /// Retired presentation-only logout marker. Kept only so upgraded clients
    /// can delete the old Keychain entry before restoring account state.
    static let legacyGhostModeUserID = "Merian_GhostModeUserID_v1"
    /// Provider-bound, one-use proof retained until the server confirms that
    /// both the guest data merge and Auth cleanup completed.
    static let pendingGhostProfileMerge = "Merian_PendingGhostProfileMerge"
    /// Device-only, one-use proof retained until RevenueCat confirms that the
    /// StoreKit purchase moved to the fresh anonymous sign-out identity.
    static let pendingSignOutPurchaseHandoff = "Merian_PendingSignOutPurchaseHandoff_v1"
    /// Stable, device-only capability used to resolve a server-owned purchase
    /// principal. The RevenueCat ID itself is never persisted as authority.
    static let purchasePrincipalInstallationCapability =
        "Merian_PurchasePrincipalInstallationCapability_v1"
    /// Device-only monotonic counter paired with the installation capability.
    /// Every resolver attempt advances and verifies it before network I/O so a
    /// delayed request from an older Auth session cannot overwrite a newer
    /// server binding.
    static let purchasePrincipalBindingIntentGeneration =
        "Merian_PurchasePrincipalBindingIntentGeneration_v1"
    /// Monotonic device-only evidence that this capability has activated a
    /// stable principal. It blocks later missing-route or legacy fallback.
    static let purchasePrincipalStableActivationFingerprint =
        "Merian_PurchasePrincipalStableActivationFingerprint_v1"
    /// Write-ahead marker retained across a local Auth rotation until the same
    /// stable purchase principal is server-bound to the replacement session.
    static let pendingPurchasePrincipalAuthRotation =
        "Merian_PendingPurchasePrincipalAuthRotation_v1"
    /// Device-only proof used only to recover or acknowledge a deletion that
    /// the authenticated backend already accepted. The server stores its hash;
    /// the raw capability never identifies or initiates an account deletion.
    static let accountDeletionRecoveryCapability =
        "Merian_AccountDeletionRecoveryCapability_v1"
    /// Write-ahead journal that keeps analytics fail-closed if the larger
    /// consent ledger cannot persist one or more account-wide withdrawals.
    static let analyticsRevocationIntent = "Merian_AnalyticsRevocationIntent_v1"
}

enum ExploreShareStateStore {
    private static func key(for scanId: String) -> String {
        UserDefaultsKeys.sharedExplorePostIdPrefix + scanId
    }

    static func sharedPostId(for scanId: String, userDefaults: UserDefaults = .standard) -> String? {
        let value = userDefaults.string(forKey: key(for: scanId))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    static func setSharedPostId(_ postId: String?, for scanId: String, userDefaults: UserDefaults = .standard) {
        let trimmed = postId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            userDefaults.set(trimmed, forKey: key(for: scanId))
        } else {
            userDefaults.removeObject(forKey: key(for: scanId))
        }
    }

    static func clearAll(userDefaults: UserDefaults = .standard) {
        for key in userDefaults.dictionaryRepresentation().keys
        where key.hasPrefix(UserDefaultsKeys.sharedExplorePostIdPrefix) {
            userDefaults.removeObject(forKey: key)
        }
    }
}

enum FieldNotesStore {
    private static func key(for scanId: String) -> String {
        UserDefaultsKeys.fieldNotesPrefix + scanId
    }

    static func fieldNotes(for scanId: String, userDefaults: UserDefaults = .standard) -> String? {
        let value = userDefaults.string(forKey: key(for: scanId))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    static func setFieldNotes(_ fieldNotes: String?, for scanId: String, userDefaults: UserDefaults = .standard) {
        let trimmed = fieldNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fieldNotes, trimmed?.isEmpty == false {
            userDefaults.set(fieldNotes, forKey: key(for: scanId))
        } else {
            userDefaults.removeObject(forKey: key(for: scanId))
        }
    }

    static func clearAll(userDefaults: UserDefaults = .standard) {
        for key in userDefaults.dictionaryRepresentation().keys
        where key.hasPrefix(UserDefaultsKeys.fieldNotesPrefix) {
            userDefaults.removeObject(forKey: key)
        }
    }
}

enum SpeciesPreferredNameStore {
    private static func key(for scientificName: String) -> String {
        UserDefaultsKeys.speciesPreferredNamePrefix + scientificName
    }

    static func legacyPreferences(userDefaults: UserDefaults = .standard) -> [String: String] {
        let prefix = UserDefaultsKeys.speciesPreferredNamePrefix
        var preferences: [String: String] = [:]

        for (key, value) in userDefaults.dictionaryRepresentation()
        where key.hasPrefix(prefix) {
            let scientificName = String(key.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let preferredName = (value as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !scientificName.isEmpty, let preferredName, !preferredName.isEmpty else {
                continue
            }

            preferences[scientificName] = preferredName
        }

        return preferences
    }

    static func preferredName(for scientificName: String, userDefaults: UserDefaults = .standard) -> String? {
        guard !scientificName.isEmpty else { return nil }
        let value = userDefaults.string(forKey: key(for: scientificName))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    static func setPreferredName(_ name: String?, for scientificName: String, userDefaults: UserDefaults = .standard) {
        guard !scientificName.isEmpty else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, trimmed?.isEmpty == false {
            userDefaults.set(name, forKey: key(for: scientificName))
        } else {
            userDefaults.removeObject(forKey: key(for: scientificName))
        }
    }

    static func clearPreferredName(for scientificName: String, userDefaults: UserDefaults = .standard) {
        setPreferredName(nil, for: scientificName, userDefaults: userDefaults)
    }

    static func clearAll(userDefaults: UserDefaults = .standard) {
        for key in userDefaults.dictionaryRepresentation().keys
        where key.hasPrefix(UserDefaultsKeys.speciesPreferredNamePrefix) {
            userDefaults.removeObject(forKey: key)
        }
    }

    static func pendingDeleteDates(userDefaults: UserDefaults = .standard) -> [String: Date] {
        let rawValue = userDefaults.dictionary(forKey: UserDefaultsKeys.pendingSpeciesPreferredNameDeletes) ?? [:]
        var datesByScientificName: [String: Date] = [:]

        for (scientificName, value) in rawValue {
            let normalizedName = scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedName.isEmpty else { continue }

            if let timestamp = value as? Double {
                datesByScientificName[normalizedName] = Date(timeIntervalSince1970: timestamp)
            } else if let date = value as? Date {
                datesByScientificName[normalizedName] = date
            }
        }

        return datesByScientificName
    }

    static func markPendingCloudDelete(
        for scientificName: String,
        at date: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) {
        let scientificName = scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scientificName.isEmpty else { return }

        var rawValue = pendingDeleteDates(userDefaults: userDefaults)
            .mapValues(\.timeIntervalSince1970)
        rawValue[scientificName] = date.timeIntervalSince1970
        userDefaults.set(rawValue, forKey: UserDefaultsKeys.pendingSpeciesPreferredNameDeletes)
    }

    static func clearPendingCloudDelete(
        for scientificName: String,
        userDefaults: UserDefaults = .standard
    ) {
        let scientificName = scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scientificName.isEmpty else { return }

        var rawValue = pendingDeleteDates(userDefaults: userDefaults)
            .mapValues(\.timeIntervalSince1970)
        rawValue.removeValue(forKey: scientificName)

        if rawValue.isEmpty {
            userDefaults.removeObject(forKey: UserDefaultsKeys.pendingSpeciesPreferredNameDeletes)
        } else {
            userDefaults.set(rawValue, forKey: UserDefaultsKeys.pendingSpeciesPreferredNameDeletes)
        }
    }

    static func syncDiagnostics(userDefaults: UserDefaults = .standard) -> SpeciesPreferredNameSyncDiagnostics {
        let status = userDefaults.string(forKey: UserDefaultsKeys.speciesPreferredNameSyncStatus)
            .flatMap(SpeciesPreferredNameSyncDiagnostics.Status.init(rawValue:))

        return SpeciesPreferredNameSyncDiagnostics(
            lastAttemptAt: userDefaults.object(forKey: UserDefaultsKeys.speciesPreferredNameSyncLastAttemptAt) as? Date,
            lastSuccessAt: userDefaults.object(forKey: UserDefaultsKeys.speciesPreferredNameSyncLastSuccessAt) as? Date,
            status: status,
            message: userDefaults.string(forKey: UserDefaultsKeys.speciesPreferredNameSyncMessage),
            lastPushedCount: userDefaults.integer(forKey: UserDefaultsKeys.speciesPreferredNameSyncLastPushedCount),
            lastPulledCount: userDefaults.integer(forKey: UserDefaultsKeys.speciesPreferredNameSyncLastPulledCount)
        )
    }

    static func recordSyncAttempt(at date: Date = Date(), userDefaults: UserDefaults = .standard) {
        userDefaults.set(date, forKey: UserDefaultsKeys.speciesPreferredNameSyncLastAttemptAt)
        userDefaults.set(
            SpeciesPreferredNameSyncDiagnostics.Status.running.rawValue,
            forKey: UserDefaultsKeys.speciesPreferredNameSyncStatus
        )
        userDefaults.removeObject(forKey: UserDefaultsKeys.speciesPreferredNameSyncMessage)
    }

    static func recordSyncSuccess(
        at date: Date = Date(),
        pushedCount: Int,
        pulledCount: Int,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(date, forKey: UserDefaultsKeys.speciesPreferredNameSyncLastSuccessAt)
        userDefaults.set(
            SpeciesPreferredNameSyncDiagnostics.Status.success.rawValue,
            forKey: UserDefaultsKeys.speciesPreferredNameSyncStatus
        )
        userDefaults.removeObject(forKey: UserDefaultsKeys.speciesPreferredNameSyncMessage)
        userDefaults.set(max(0, pushedCount), forKey: UserDefaultsKeys.speciesPreferredNameSyncLastPushedCount)
        userDefaults.set(max(0, pulledCount), forKey: UserDefaultsKeys.speciesPreferredNameSyncLastPulledCount)
    }

    static func recordSyncFailure(
        _ message: String,
        at date: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(date, forKey: UserDefaultsKeys.speciesPreferredNameSyncLastAttemptAt)
        userDefaults.set(
            SpeciesPreferredNameSyncDiagnostics.Status.failure.rawValue,
            forKey: UserDefaultsKeys.speciesPreferredNameSyncStatus
        )
        userDefaults.set(normalizedDiagnosticMessage(message), forKey: UserDefaultsKeys.speciesPreferredNameSyncMessage)
    }

    static func recordSyncSkip(
        _ reason: String,
        at date: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(date, forKey: UserDefaultsKeys.speciesPreferredNameSyncLastAttemptAt)
        userDefaults.set(
            SpeciesPreferredNameSyncDiagnostics.Status.skipped.rawValue,
            forKey: UserDefaultsKeys.speciesPreferredNameSyncStatus
        )
        userDefaults.set(normalizedDiagnosticMessage(reason), forKey: UserDefaultsKeys.speciesPreferredNameSyncMessage)
    }

    static func clearSyncDiagnostics(userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: UserDefaultsKeys.speciesPreferredNameSyncLastAttemptAt)
        userDefaults.removeObject(forKey: UserDefaultsKeys.speciesPreferredNameSyncLastSuccessAt)
        userDefaults.removeObject(forKey: UserDefaultsKeys.speciesPreferredNameSyncStatus)
        userDefaults.removeObject(forKey: UserDefaultsKeys.speciesPreferredNameSyncMessage)
        userDefaults.removeObject(forKey: UserDefaultsKeys.speciesPreferredNameSyncLastPushedCount)
        userDefaults.removeObject(forKey: UserDefaultsKeys.speciesPreferredNameSyncLastPulledCount)
    }

    private static func normalizedDiagnosticMessage(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown sync outcome." : trimmed
    }
}

struct SpeciesNameMigrationResult: Equatable {
    let scannedCount: Int
    let promotedCount: Int
    let preservedExistingCount: Int
    let removedLegacyCount: Int
    let failedCount: Int
}

struct SpeciesPreferredNameSyncDiagnostics: Equatable, Sendable {
    enum Status: String, Equatable, Sendable {
        case running
        case success
        case failure
        case skipped
    }

    let lastAttemptAt: Date?
    let lastSuccessAt: Date?
    let status: Status?
    let message: String?
    let lastPushedCount: Int
    let lastPulledCount: Int
}

struct SpeciesPreferenceCloudRow: Decodable {
    let scientific_name: String
    let preferred_common_name: String?
    let updated_at: String
    let deleted_at: String?
}

private struct SpeciesPreferenceCloudUpsert: Encodable {
    let user_id: String
    let scientific_name: String
    let preferred_common_name: String?
    let deleted_at: String?

    enum CodingKeys: String, CodingKey {
        case user_id
        case scientific_name
        case preferred_common_name
        case deleted_at
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(user_id, forKey: .user_id)
        try container.encode(scientific_name, forKey: .scientific_name)

        if let preferred_common_name {
            try container.encode(preferred_common_name, forKey: .preferred_common_name)
        } else {
            try container.encodeNil(forKey: .preferred_common_name)
        }

        if let deleted_at {
            try container.encode(deleted_at, forKey: .deleted_at)
        } else {
            try container.encodeNil(forKey: .deleted_at)
        }
    }
}

@MainActor
enum SpeciesPreferredNameRepository {
    private struct PendingCloudSyncRequest {
        let modelContext: ModelContext
        let legacyDefaults: UserDefaults
        let force: Bool
    }

    private static let maxPreferredNameBatchSize = 1_000
    private static let cloudSyncPageSize = 500
    private static let cleanCloudSyncFreshnessInterval: TimeInterval = 60
    private static var activeCloudSyncTask: Task<Bool, Never>?
    private static var pendingCloudSyncRequest: PendingCloudSyncRequest?

    static func preferredName(
        for scientificName: String,
        modelContext: ModelContext,
        legacyDefaults: UserDefaults = .standard
    ) -> String? {
        let scientificName = normalizedScientificName(scientificName)
        guard !scientificName.isEmpty else { return nil }

        if let record = fetchPreference(for: scientificName, modelContext: modelContext) {
            let preferredName = normalizedPreferredName(record.preferredCommonName)
            if let preferredName {
                SpeciesPreferredNameStore.clearPreferredName(for: scientificName, userDefaults: legacyDefaults)
                return preferredName
            }
        }

        guard let legacyName = SpeciesPreferredNameStore.preferredName(
            for: scientificName,
            userDefaults: legacyDefaults
        ) else {
            return nil
        }

        _ = setPreferredName(
            legacyName,
            for: scientificName,
            modelContext: modelContext,
            legacyDefaults: legacyDefaults
        )
        return legacyName
    }

    static func preferredNames(
        for scientificNames: [String],
        modelContext: ModelContext,
        legacyDefaults: UserDefaults = .standard
    ) -> [String: String] {
        let normalizedNames = Array(
            Set(
                scientificNames
                    .map(normalizedScientificName)
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()

        if normalizedNames.count > maxPreferredNameBatchSize {
            MerianLog.data.error(
                "Truncating species preferred-name batch from \(normalizedNames.count, privacy: .public) to \(maxPreferredNameBatchSize, privacy: .public)"
            )
        }

        var namesByScientificName: [String: String] = [:]
        let boundedNames = Array(normalizedNames.prefix(maxPreferredNameBatchSize))
        let recordsByScientificName = fetchPreferences(for: boundedNames, modelContext: modelContext)
        namesByScientificName.reserveCapacity(boundedNames.count)

        for scientificName in boundedNames {
            if let record = recordsByScientificName[scientificName],
               let preferredName = normalizedPreferredName(record.preferredCommonName) {
                SpeciesPreferredNameStore.clearPreferredName(for: scientificName, userDefaults: legacyDefaults)
                namesByScientificName[scientificName] = preferredName
                continue
            }

            guard let legacyName = SpeciesPreferredNameStore.preferredName(
                for: scientificName,
                userDefaults: legacyDefaults
            ) else {
                continue
            }

            _ = setPreferredName(
                legacyName,
                for: scientificName,
                modelContext: modelContext,
                legacyDefaults: legacyDefaults
            )
            namesByScientificName[scientificName] = legacyName
        }

        return namesByScientificName
    }

    @discardableResult
    static func syncCloudPreferences(
        modelContext: ModelContext,
        legacyDefaults: UserDefaults = .standard,
        force: Bool = false
    ) async -> Bool {
        guard !TestExecutionCoordinator.isRunningTests else { return false }
        if let activeCloudSyncTask {
            let shouldForce = force || pendingCloudSyncRequest?.force == true
            pendingCloudSyncRequest = PendingCloudSyncRequest(
                modelContext: modelContext,
                legacyDefaults: legacyDefaults,
                force: shouldForce
            )
            return await activeCloudSyncTask.value
        }
        guard force || !hasFreshCleanCloudSync(legacyDefaults: legacyDefaults) else {
            return true
        }

        let syncTask = Task { @MainActor in
            defer {
                activeCloudSyncTask = nil
                pendingCloudSyncRequest = nil
            }

            var nextModelContext = modelContext
            var nextLegacyDefaults = legacyDefaults

            while true {
                let latestResult = await performCloudPreferenceSync(
                    modelContext: nextModelContext,
                    legacyDefaults: nextLegacyDefaults
                )

                guard let pendingCloudSyncRequest else {
                    return latestResult
                }

                nextModelContext = pendingCloudSyncRequest.modelContext
                nextLegacyDefaults = pendingCloudSyncRequest.legacyDefaults
                SpeciesPreferredNameRepository.pendingCloudSyncRequest = nil
            }
        }
        activeCloudSyncTask = syncTask
        return await syncTask.value
    }

    private static func hasFreshCleanCloudSync(legacyDefaults: UserDefaults) -> Bool {
        guard SpeciesPreferredNameStore.pendingDeleteDates(userDefaults: legacyDefaults).isEmpty else {
            return false
        }
        guard let lastSuccessAt = SpeciesPreferredNameStore.syncDiagnostics(userDefaults: legacyDefaults).lastSuccessAt else {
            return false
        }
        return Date().timeIntervalSince(lastSuccessAt) < cleanCloudSyncFreshnessInterval
    }

    private static func performCloudPreferenceSync(
        modelContext: ModelContext,
        legacyDefaults: UserDefaults
    ) async -> Bool {
        SpeciesPreferredNameStore.recordSyncAttempt(userDefaults: legacyDefaults)

        guard let accountWorkLease = try? SupabaseManager.shared
            .beginUnownedAccountBoundWork() else {
            SpeciesPreferredNameStore.recordSyncSkip(
                "No stable authenticated Supabase session.",
                userDefaults: legacyDefaults
            )
            return false
        }
        defer {
            SupabaseManager.shared.finishAccountBoundWork(accountWorkLease)
        }
        let userId = accountWorkLease.session.userID.uuidString

        do {
            let localPreferences = fetchAllPreferences(modelContext: modelContext)
            let pendingDeletes = SpeciesPreferredNameStore.pendingDeleteDates(userDefaults: legacyDefaults)
            let remoteRows = try await fetchRemotePreferences(
                userId: userId,
                accountWorkLease: accountWorkLease
            )
            guard SupabaseManager.shared
                .isAccountBoundWorkLeaseCurrent(accountWorkLease) else {
                throw SupabaseAuthTransitionError.signOutInProgress
            }
            let remoteByScientificName = Dictionary(
                uniqueKeysWithValues: remoteRows.map {
                    (normalizedScientificName($0.scientific_name), $0)
                }
            )

            let activeUpserts = activeCloudUpserts(
                userId: userId,
                localPreferences: localPreferences,
                remoteByScientificName: remoteByScientificName
            )
            let deleteUpserts = pendingDeleteUpserts(
                userId: userId,
                pendingDeletes: pendingDeletes,
                remoteByScientificName: remoteByScientificName
            )
            let upserts = activeUpserts + deleteUpserts

            if !upserts.isEmpty {
                try await SupabaseManager.shared.client
                    .from("user_species_preferences")
                    .upsert(upserts, onConflict: "user_id,scientific_name")
                    .execute()

                guard SupabaseManager.shared
                    .isAccountBoundWorkLeaseCurrent(accountWorkLease) else {
                    throw SupabaseAuthTransitionError.signOutInProgress
                }

                for upsert in deleteUpserts {
                    SpeciesPreferredNameStore.clearPendingCloudDelete(
                        for: upsert.scientific_name,
                        userDefaults: legacyDefaults
                    )
                }
            }

            guard SupabaseManager.shared
                .isAccountBoundWorkLeaseCurrent(accountWorkLease) else {
                throw SupabaseAuthTransitionError.signOutInProgress
            }
            applyRemotePreferences(
                remoteRows,
                localPreferences: localPreferences,
                pendingDeletes: pendingDeletes,
                modelContext: modelContext,
                legacyDefaults: legacyDefaults
            )
            SpeciesPreferredNameStore.recordSyncSuccess(
                pushedCount: upserts.count,
                pulledCount: remoteRows.count,
                userDefaults: legacyDefaults
            )

            MerianLog.data.debug(
                "Synced species preferred names with cloud: \(localPreferences.count, privacy: .public) local, \(remoteRows.count, privacy: .public) remote, \(upserts.count, privacy: .public) pushed."
            )
            return true
        } catch {
            SpeciesPreferredNameStore.recordSyncFailure(
                error.localizedDescription,
                userDefaults: legacyDefaults
            )
            MerianLog.data.debug("Species preferred-name cloud sync skipped or failed: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    @discardableResult
    static func migrateLegacyPreferences(
        modelContext: ModelContext,
        legacyDefaults: UserDefaults = .standard
    ) -> SpeciesNameMigrationResult {
        let legacyPreferences = SpeciesPreferredNameStore.legacyPreferences(userDefaults: legacyDefaults)
        guard !legacyPreferences.isEmpty else {
            return SpeciesNameMigrationResult(
                scannedCount: 0,
                promotedCount: 0,
                preservedExistingCount: 0,
                removedLegacyCount: 0,
                failedCount: 0
            )
        }

        let scientificNames = legacyPreferences.keys.sorted()
        let recordsByScientificName = fetchPreferences(for: scientificNames, modelContext: modelContext)

        var didMutateSwiftData = false
        var pendingPromotedCount = 0
        var preservedExistingCount = 0

        for scientificName in scientificNames {
            guard let legacyName = normalizedPreferredName(legacyPreferences[scientificName]) else { continue }

            if let existing = recordsByScientificName[scientificName],
               normalizedPreferredName(existing.preferredCommonName) != nil {
                preservedExistingCount += 1
                continue
            }

            if let existing = recordsByScientificName[scientificName] {
                existing.preferredCommonName = legacyName
                existing.updatedAt = Date()
            } else {
                modelContext.insert(
                    UserSpeciesPreference(
                        scientificName: scientificName,
                        preferredCommonName: legacyName
                    )
                )
            }
            didMutateSwiftData = true
            pendingPromotedCount += 1
        }

        do {
            if didMutateSwiftData {
                try modelContext.save()
            }

            for scientificName in scientificNames {
                SpeciesPreferredNameStore.clearPreferredName(for: scientificName, userDefaults: legacyDefaults)
            }

            if pendingPromotedCount > 0 || preservedExistingCount > 0 {
                MerianLog.data.debug(
                    "Migrated \(pendingPromotedCount, privacy: .public) legacy species preferred names and removed \(scientificNames.count, privacy: .public) legacy keys."
                )
            }

            return SpeciesNameMigrationResult(
                scannedCount: scientificNames.count,
                promotedCount: pendingPromotedCount,
                preservedExistingCount: preservedExistingCount,
                removedLegacyCount: scientificNames.count,
                failedCount: 0
            )
        } catch {
            modelContext.rollback()
            MerianLog.data.error("Failed to migrate legacy species preferred names: \(error.localizedDescription, privacy: .private)")
            return SpeciesNameMigrationResult(
                scannedCount: scientificNames.count,
                promotedCount: 0,
                preservedExistingCount: 0,
                removedLegacyCount: 0,
                failedCount: scientificNames.count
            )
        }
    }

    @discardableResult
    static func setPreferredName(
        _ name: String?,
        for scientificName: String,
        modelContext: ModelContext,
        legacyDefaults: UserDefaults = .standard
    ) -> Bool {
        let scientificName = normalizedScientificName(scientificName)
        guard !scientificName.isEmpty else { return false }

        guard let preferredName = normalizedPreferredName(name) else {
            return clearPreferredName(
                for: scientificName,
                modelContext: modelContext,
                legacyDefaults: legacyDefaults
            )
        }

        do {
            if let existing = fetchPreference(for: scientificName, modelContext: modelContext) {
                existing.preferredCommonName = preferredName
                existing.updatedAt = Date()
            } else {
                modelContext.insert(
                    UserSpeciesPreference(
                        scientificName: scientificName,
                        preferredCommonName: preferredName
                    )
                )
            }

            try modelContext.save()
            SpeciesPreferredNameStore.clearPreferredName(for: scientificName, userDefaults: legacyDefaults)
            SpeciesPreferredNameStore.clearPendingCloudDelete(for: scientificName, userDefaults: legacyDefaults)
            scheduleCloudSync(modelContext: modelContext, legacyDefaults: legacyDefaults)
            return true
        } catch {
            modelContext.rollback()
            MerianLog.data.error("Failed to save species preferred name for \(scientificName, privacy: .private): \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    @discardableResult
    static func clearPreferredName(
        for scientificName: String,
        modelContext: ModelContext,
        legacyDefaults: UserDefaults = .standard
    ) -> Bool {
        let scientificName = normalizedScientificName(scientificName)
        guard !scientificName.isEmpty else { return false }

        guard let existing = fetchPreference(for: scientificName, modelContext: modelContext) else {
            SpeciesPreferredNameStore.clearPreferredName(for: scientificName, userDefaults: legacyDefaults)
            SpeciesPreferredNameStore.markPendingCloudDelete(for: scientificName, userDefaults: legacyDefaults)
            return true
        }

        do {
            modelContext.delete(existing)
            try modelContext.save()
            SpeciesPreferredNameStore.clearPreferredName(for: scientificName, userDefaults: legacyDefaults)
            SpeciesPreferredNameStore.markPendingCloudDelete(for: scientificName, userDefaults: legacyDefaults)
            scheduleCloudSync(modelContext: modelContext, legacyDefaults: legacyDefaults)
            return true
        } catch {
            modelContext.rollback()
            MerianLog.data.error("Failed to clear species preferred name for \(scientificName, privacy: .private): \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    private static func fetchPreference(
        for scientificName: String,
        modelContext: ModelContext
    ) -> UserSpeciesPreference? {
        let targetScientificName = scientificName
        var descriptor = FetchDescriptor<UserSpeciesPreference>(
            predicate: #Predicate<UserSpeciesPreference> { $0.scientificName == targetScientificName }
        )
        descriptor.fetchLimit = 1

        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            MerianLog.data.error("Failed to fetch species preferred name for \(scientificName, privacy: .private): \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    private static func fetchPreferences(
        for scientificNames: [String],
        modelContext: ModelContext
    ) -> [String: UserSpeciesPreference] {
        guard !scientificNames.isEmpty else { return [:] }

        let targetScientificNames = scientificNames
        var descriptor = FetchDescriptor<UserSpeciesPreference>(
            predicate: #Predicate<UserSpeciesPreference> { targetScientificNames.contains($0.scientificName) }
        )
        descriptor.fetchLimit = targetScientificNames.count

        do {
            let records = try modelContext.fetch(descriptor)
            var recordsByScientificName: [String: UserSpeciesPreference] = [:]
            recordsByScientificName.reserveCapacity(records.count)
            for record in records where recordsByScientificName[record.scientificName] == nil {
                recordsByScientificName[record.scientificName] = record
            }
            return recordsByScientificName
        } catch {
            MerianLog.data.error("Failed to batch fetch species preferred names: \(error.localizedDescription, privacy: .private)")
            return [:]
        }
    }

    private static func fetchAllPreferences(modelContext: ModelContext) -> [UserSpeciesPreference] {
        var descriptor = FetchDescriptor<UserSpeciesPreference>(
            sortBy: [SortDescriptor(\.updatedAt, order: .forward)]
        )
        descriptor.fetchLimit = maxPreferredNameBatchSize

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            MerianLog.data.error("Failed to fetch local species preferred names for cloud sync: \(error.localizedDescription, privacy: .private)")
            return []
        }
    }

    private static func fetchRemotePreferences(
        userId: String,
        accountWorkLease: AccountBoundWorkLease
    ) async throws -> [SpeciesPreferenceCloudRow] {
        var rows: [SpeciesPreferenceCloudRow] = []
        rows.reserveCapacity(cloudSyncPageSize)

        var offset = 0
        while true {
            let page: [SpeciesPreferenceCloudRow] = try await SupabaseManager.shared.client
                .from("user_species_preferences")
                .select("scientific_name, preferred_common_name, updated_at, deleted_at")
                .eq("user_id", value: userId)
                .order("updated_at", ascending: true)
                .range(from: offset, to: offset + cloudSyncPageSize - 1)
                .execute()
                .value

            guard SupabaseManager.shared
                .isAccountBoundWorkLeaseCurrent(accountWorkLease) else {
                throw SupabaseAuthTransitionError.signOutInProgress
            }

            rows.append(contentsOf: page)
            if page.count < cloudSyncPageSize { break }
            offset += cloudSyncPageSize
        }

        return rows
    }

    private static func activeCloudUpserts(
        userId: String,
        localPreferences: [UserSpeciesPreference],
        remoteByScientificName: [String: SpeciesPreferenceCloudRow]
    ) -> [SpeciesPreferenceCloudUpsert] {
        localPreferences.compactMap { preference in
            let scientificName = normalizedScientificName(preference.scientificName)
            guard !scientificName.isEmpty,
                  let preferredName = normalizedPreferredName(preference.preferredCommonName) else {
                return nil
            }

            if !needsActiveCloudUpsert(
                preferredName: preferredName,
                updatedAt: preference.updatedAt,
                remote: remoteByScientificName[scientificName]
            ) {
                return nil
            }

            return SpeciesPreferenceCloudUpsert(
                user_id: userId,
                scientific_name: scientificName,
                preferred_common_name: preferredName,
                deleted_at: nil
            )
        }
    }

    private static func pendingDeleteUpserts(
        userId: String,
        pendingDeletes: [String: Date],
        remoteByScientificName: [String: SpeciesPreferenceCloudRow]
    ) -> [SpeciesPreferenceCloudUpsert] {
        pendingDeletes.compactMap { scientificName, deletedAt in
            let scientificName = normalizedScientificName(scientificName)
            guard !scientificName.isEmpty else { return nil }

            if !needsPendingDeleteCloudUpsert(
                deletedAt: deletedAt,
                remote: remoteByScientificName[scientificName]
            ) {
                return nil
            }

            return SpeciesPreferenceCloudUpsert(
                user_id: userId,
                scientific_name: scientificName,
                preferred_common_name: nil,
                deleted_at: cloudString(deletedAt)
            )
        }
    }

    static func needsActiveCloudUpsert(
        preferredName: String,
        updatedAt: Date,
        remote: SpeciesPreferenceCloudRow?
    ) -> Bool {
        guard let remote else { return true }

        if remote.deleted_at == nil,
           normalizedPreferredName(remote.preferred_common_name) == normalizedPreferredName(preferredName) {
            return false
        }

        guard let remoteUpdatedAt = cloudDate(remote.updated_at) else {
            return true
        }
        return remoteUpdatedAt <= updatedAt
    }

    static func needsPendingDeleteCloudUpsert(
        deletedAt: Date,
        remote: SpeciesPreferenceCloudRow?
    ) -> Bool {
        guard let remote else { return true }
        if remote.deleted_at != nil { return false }
        guard let remoteUpdatedAt = cloudDate(remote.updated_at) else {
            return true
        }
        return remoteUpdatedAt <= deletedAt
    }

    private static func applyRemotePreferences(
        _ remoteRows: [SpeciesPreferenceCloudRow],
        localPreferences: [UserSpeciesPreference],
        pendingDeletes: [String: Date],
        modelContext: ModelContext,
        legacyDefaults: UserDefaults
    ) {
        guard !remoteRows.isEmpty else { return }

        var localByScientificName = Dictionary(
            uniqueKeysWithValues: localPreferences.map {
                (normalizedScientificName($0.scientificName), $0)
            }
        )
        var didMutate = false

        for remote in remoteRows {
            let scientificName = normalizedScientificName(remote.scientific_name)
            guard !scientificName.isEmpty,
                  let remoteUpdatedAt = cloudDate(remote.updated_at) else {
                continue
            }

            if remote.deleted_at != nil {
                if let localPreference = localByScientificName[scientificName],
                   remoteUpdatedAt >= localPreference.updatedAt {
                    modelContext.delete(localPreference)
                    localByScientificName.removeValue(forKey: scientificName)
                    SpeciesPreferredNameStore.clearPreferredName(for: scientificName, userDefaults: legacyDefaults)
                    didMutate = true
                }
                SpeciesPreferredNameStore.clearPendingCloudDelete(for: scientificName, userDefaults: legacyDefaults)
                continue
            }

            if let pendingDelete = pendingDeletes[scientificName],
               pendingDelete >= remoteUpdatedAt {
                continue
            }

            guard let remotePreferredName = normalizedPreferredName(remote.preferred_common_name) else {
                continue
            }

            if let localPreference = localByScientificName[scientificName] {
                if normalizedPreferredName(localPreference.preferredCommonName) == remotePreferredName {
                    SpeciesPreferredNameStore.clearPreferredName(for: scientificName, userDefaults: legacyDefaults)
                    SpeciesPreferredNameStore.clearPendingCloudDelete(for: scientificName, userDefaults: legacyDefaults)
                    continue
                }
                guard remoteUpdatedAt > localPreference.updatedAt else { continue }
                localPreference.preferredCommonName = remotePreferredName
                localPreference.updatedAt = remoteUpdatedAt
            } else {
                let preference = UserSpeciesPreference(
                    scientificName: scientificName,
                    preferredCommonName: remotePreferredName,
                    updatedAt: remoteUpdatedAt
                )
                modelContext.insert(preference)
                localByScientificName[scientificName] = preference
            }
            SpeciesPreferredNameStore.clearPreferredName(for: scientificName, userDefaults: legacyDefaults)
            SpeciesPreferredNameStore.clearPendingCloudDelete(for: scientificName, userDefaults: legacyDefaults)
            didMutate = true
        }

        guard didMutate else { return }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            MerianLog.data.error("Failed to apply remote species preferred names: \(error.localizedDescription, privacy: .private)")
        }
    }

    private static func cloudString(_ date: Date) -> String {
        DateUtilities.iso8601FractionalFormatter.string(from: date)
    }

    private static func cloudDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return DateUtilities.iso8601FractionalFormatter.date(from: value)
            ?? DateUtilities.iso8601Formatter.date(from: value)
    }

    private static func scheduleCloudSync(
        modelContext: ModelContext,
        legacyDefaults: UserDefaults
    ) {
        guard !TestExecutionCoordinator.isRunningTests else { return }
        Task { @MainActor in
            await syncCloudPreferences(modelContext: modelContext, legacyDefaults: legacyDefaults, force: true)
        }
    }

    private static func normalizedScientificName(_ scientificName: String) -> String {
        scientificName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedPreferredName(_ name: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    @ObservationIgnored private var isReloadingFromDefaults = false

    var hasCompletedOnboarding: Bool {
        didSet { persistBool(hasCompletedOnboarding, oldValue: oldValue, key: UserDefaultsKeys.hasCompletedOnboarding) }
    }
    var themeMode: ThemeMode {
        didSet { persistString(themeMode.rawValue, oldValue: oldValue.rawValue, key: UserDefaultsKeys.themeMode) }
    }
    var opensExploreOnLaunch: Bool {
        didSet {
            persistBool(opensExploreOnLaunch, oldValue: oldValue, key: UserDefaultsKeys.opensExploreOnLaunch)
        }
    }
    var isMultiCaptureEnabled: Bool {
        didSet { persistBool(isMultiCaptureEnabled, oldValue: oldValue, key: UserDefaultsKeys.isMultiCaptureEnabled) }
    }
    var requiresScanConfirmation: Bool {
        didSet {
            persistBool(requiresScanConfirmation, oldValue: oldValue, key: UserDefaultsKeys.requiresScanConfirmation)
        }
    }
    var showsCaptureGoalProgress: Bool {
        didSet {
            persistBool(
                showsCaptureGoalProgress,
                oldValue: oldValue,
                key: UserDefaultsKeys.showsCaptureGoalProgress
            )
        }
    }
    var isExpeditionModeActive: Bool {
        didSet { persistBool(isExpeditionModeActive, oldValue: oldValue, key: UserDefaultsKeys.isExpeditionModeActive) }
    }
    var isHapticsEnabled: Bool {
        didSet { persistBool(isHapticsEnabled, oldValue: oldValue, key: UserDefaultsKeys.isHapticsEnabled) }
    }
    var hasUnseenScan: Bool {
        didSet { persistBool(hasUnseenScan, oldValue: oldValue, key: UserDefaultsKeys.hasUnseenScan) }
    }
    var isPushNotificationsEnabled: Bool {
        didSet { persistBool(isPushNotificationsEnabled, oldValue: oldValue, key: UserDefaultsKeys.isPushNotificationsEnabled) }
    }
    var hasPromptedForNotificationsPostIdent: Bool {
        didSet { persistBool(hasPromptedForNotificationsPostIdent, oldValue: oldValue, key: UserDefaultsKeys.hasPromptedForNotificationsPostIdent) }
    }
    var isAchievementNotificationsEnabled: Bool {
        didSet { persistBool(isAchievementNotificationsEnabled, oldValue: oldValue, key: UserDefaultsKeys.isAchievementNotificationsEnabled) }
    }
    var isExploreNotificationsEnabled: Bool {
        didSet { persistBool(isExploreNotificationsEnabled, oldValue: oldValue, key: UserDefaultsKeys.isExploreNotificationsEnabled) }
    }
    var isExploreCommentMentionNotificationsEnabled: Bool {
        didSet {
            persistBool(
                isExploreCommentMentionNotificationsEnabled,
                oldValue: oldValue,
                key: UserDefaultsKeys.isExploreCommentMentionNotificationsEnabled
            )
        }
    }
    var isCommunityIdentificationNotificationsEnabled: Bool {
        didSet {
            persistBool(
                isCommunityIdentificationNotificationsEnabled,
                oldValue: oldValue,
                key: UserDefaultsKeys.isCommunityIdentificationNotificationsEnabled
            )
        }
    }
    var hasSeenExploreOnboarding: Bool {
        didSet { persistBool(hasSeenExploreOnboarding, oldValue: oldValue, key: UserDefaultsKeys.hasSeenExploreOnboarding) }
    }
    var hasUnseenExplorePost: Bool {
        didSet { persistBool(hasUnseenExplorePost, oldValue: oldValue, key: UserDefaultsKeys.hasUnseenExplorePost) }
    }
    var lastSeenExplorePostSharedAt: String {
        didSet { persistString(lastSeenExplorePostSharedAt, oldValue: oldValue, key: UserDefaultsKeys.lastSeenExplorePostSharedAt) }
    }
    var feedbackSurveyDismissedCampaignId: String {
        didSet {
            persistString(
                feedbackSurveyDismissedCampaignId,
                oldValue: oldValue,
                key: UserDefaultsKeys.feedbackSurveyDismissedCampaignId
            )
        }
    }
    var feedbackSurveySubmittedCampaignId: String {
        didSet {
            persistString(
                feedbackSurveySubmittedCampaignId,
                oldValue: oldValue,
                key: UserDefaultsKeys.feedbackSurveySubmittedCampaignId
            )
        }
    }
    var feedbackSurveySubmittedAt: TimeInterval {
        didSet {
            persistDouble(
                feedbackSurveySubmittedAt,
                oldValue: oldValue,
                key: UserDefaultsKeys.feedbackSurveySubmittedAt
            )
        }
    }
    var invertZoomDirection: Bool {
        didSet { persistBool(invertZoomDirection, oldValue: oldValue, key: UserDefaultsKeys.invertZoomDirection) }
    }
    var zoomSideLeft: Bool {
        didSet { persistBool(zoomSideLeft, oldValue: oldValue, key: UserDefaultsKeys.zoomSideLeft) }
    }
    var zoomSliderVisible: Bool {
        didSet { persistBool(zoomSliderVisible, oldValue: oldValue, key: UserDefaultsKeys.zoomSliderVisible) }
    }
    var isLiveInferencePaused: Bool {
        didSet { persistBool(isLiveInferencePaused, oldValue: oldValue, key: UserDefaultsKeys.isLiveInferencePaused) }
    }
    var suppressInferenceBanners: Bool {
        didSet { persistBool(suppressInferenceBanners, oldValue: oldValue, key: UserDefaultsKeys.suppressInferenceBanners) }
    }
    var saveToCameraRoll: Bool {
        didSet { persistBool(saveToCameraRoll, oldValue: oldValue, key: UserDefaultsKeys.saveToCameraRoll) }
    }
    var audioHintsEnabled: Bool {
        didSet { persistBool(audioHintsEnabled, oldValue: oldValue, key: UserDefaultsKeys.audioHintsEnabled) }
    }
    var captureModeOrderRaw: String {
        didSet { persistString(captureModeOrderRaw, oldValue: oldValue, key: UserDefaultsKeys.captureModeOrder) }
    }
    var gridColumns: Int {
        didSet {
            let normalized = min(max(gridColumns, 1), 3)
            if gridColumns != normalized {
                gridColumns = normalized
                return
            }
            persistInt(gridColumns, oldValue: oldValue, key: UserDefaultsKeys.gridColumns)
        }
    }

    init(
        userDefaults: UserDefaults = .standard,
        observeExternalChanges: Bool = true
    ) {
        self.userDefaults = userDefaults

        userDefaults.register(defaults: [
            UserDefaultsKeys.themeMode: ThemeMode.system.rawValue,
            UserDefaultsKeys.opensExploreOnLaunch: false,
            UserDefaultsKeys.isMultiCaptureEnabled: false,
            UserDefaultsKeys.requiresScanConfirmation: false,
            UserDefaultsKeys.showsCaptureGoalProgress: true,
            UserDefaultsKeys.isExpeditionModeActive: false,
            UserDefaultsKeys.isHapticsEnabled: true,
            UserDefaultsKeys.hasUnseenScan: false,
            UserDefaultsKeys.isPushNotificationsEnabled: false,
            UserDefaultsKeys.hasPromptedForNotificationsPostIdent: false,
            UserDefaultsKeys.isAchievementNotificationsEnabled: true,
            UserDefaultsKeys.isExploreNotificationsEnabled: true,
            UserDefaultsKeys.isExploreCommentMentionNotificationsEnabled: true,
            UserDefaultsKeys.isCommunityIdentificationNotificationsEnabled: true,
            UserDefaultsKeys.hasSeenExploreOnboarding: false,
            UserDefaultsKeys.hasUnseenExplorePost: false,
            UserDefaultsKeys.lastSeenExplorePostSharedAt: "",
            UserDefaultsKeys.feedbackSurveyDismissedCampaignId: "",
            UserDefaultsKeys.feedbackSurveySubmittedCampaignId: "",
            UserDefaultsKeys.feedbackSurveySubmittedAt: 0,
            UserDefaultsKeys.invertZoomDirection: false,
            UserDefaultsKeys.zoomSideLeft: true,
            UserDefaultsKeys.zoomSliderVisible: true,
            UserDefaultsKeys.isLiveInferencePaused: UIDevice.current.isModernIPhone,
            UserDefaultsKeys.suppressInferenceBanners: false,
            UserDefaultsKeys.saveToCameraRoll: false,
            UserDefaultsKeys.audioHintsEnabled: true,
            UserDefaultsKeys.captureModeOrder: "visual,audio,describe",
            UserDefaultsKeys.gridColumns: 3
        ])

        hasCompletedOnboarding = userDefaults.bool(forKey: UserDefaultsKeys.hasCompletedOnboarding)
        themeMode = ThemeMode(
            rawValue: userDefaults.string(forKey: UserDefaultsKeys.themeMode) ?? ThemeMode.system.rawValue
        ) ?? .system
        opensExploreOnLaunch = userDefaults.bool(forKey: UserDefaultsKeys.opensExploreOnLaunch)
        isMultiCaptureEnabled = userDefaults.bool(forKey: UserDefaultsKeys.isMultiCaptureEnabled)
        requiresScanConfirmation = userDefaults.bool(forKey: UserDefaultsKeys.requiresScanConfirmation)
        showsCaptureGoalProgress = userDefaults.bool(forKey: UserDefaultsKeys.showsCaptureGoalProgress)
        isExpeditionModeActive = userDefaults.bool(forKey: UserDefaultsKeys.isExpeditionModeActive)
        isHapticsEnabled = userDefaults.bool(forKey: UserDefaultsKeys.isHapticsEnabled)
        hasUnseenScan = userDefaults.bool(forKey: UserDefaultsKeys.hasUnseenScan)
        isPushNotificationsEnabled = userDefaults.bool(forKey: UserDefaultsKeys.isPushNotificationsEnabled)
        hasPromptedForNotificationsPostIdent = userDefaults.bool(forKey: UserDefaultsKeys.hasPromptedForNotificationsPostIdent)
        isAchievementNotificationsEnabled = userDefaults.bool(forKey: UserDefaultsKeys.isAchievementNotificationsEnabled)
        isExploreNotificationsEnabled = userDefaults.bool(forKey: UserDefaultsKeys.isExploreNotificationsEnabled)
        isExploreCommentMentionNotificationsEnabled = userDefaults.bool(
            forKey: UserDefaultsKeys.isExploreCommentMentionNotificationsEnabled
        )
        isCommunityIdentificationNotificationsEnabled = userDefaults.bool(
            forKey: UserDefaultsKeys.isCommunityIdentificationNotificationsEnabled
        )
        hasSeenExploreOnboarding = userDefaults.bool(forKey: UserDefaultsKeys.hasSeenExploreOnboarding)
        hasUnseenExplorePost = userDefaults.bool(forKey: UserDefaultsKeys.hasUnseenExplorePost)
        lastSeenExplorePostSharedAt = userDefaults.string(forKey: UserDefaultsKeys.lastSeenExplorePostSharedAt) ?? ""
        feedbackSurveyDismissedCampaignId = userDefaults.string(forKey: UserDefaultsKeys.feedbackSurveyDismissedCampaignId) ?? ""
        feedbackSurveySubmittedCampaignId = userDefaults.string(forKey: UserDefaultsKeys.feedbackSurveySubmittedCampaignId) ?? ""
        feedbackSurveySubmittedAt = userDefaults.double(forKey: UserDefaultsKeys.feedbackSurveySubmittedAt)
        invertZoomDirection = userDefaults.bool(forKey: UserDefaultsKeys.invertZoomDirection)
        zoomSideLeft = userDefaults.bool(forKey: UserDefaultsKeys.zoomSideLeft)
        zoomSliderVisible = userDefaults.bool(forKey: UserDefaultsKeys.zoomSliderVisible)
        isLiveInferencePaused = userDefaults.object(forKey: UserDefaultsKeys.isLiveInferencePaused) as? Bool
            ?? UIDevice.current.isModernIPhone
        suppressInferenceBanners = userDefaults.bool(forKey: UserDefaultsKeys.suppressInferenceBanners)
        saveToCameraRoll = userDefaults.bool(forKey: UserDefaultsKeys.saveToCameraRoll)
        audioHintsEnabled = userDefaults.bool(forKey: UserDefaultsKeys.audioHintsEnabled)
        captureModeOrderRaw = userDefaults.string(forKey: UserDefaultsKeys.captureModeOrder) ?? "visual,audio,describe"
        gridColumns = min(max(userDefaults.integer(forKey: UserDefaultsKeys.gridColumns), 1), 3)

        if observeExternalChanges {
            defaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: userDefaults,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reloadFromDefaults()
                }
            }
        }
    }

    deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    func applyCaptureModeOrder(_ modes: [CaptureMode]) {
        captureModeOrderRaw = modes.map(\.rawValue).joined(separator: ",")
    }

    func refreshFromDefaults() {
        reloadFromDefaults()
    }

    private func reloadFromDefaults() {
        isReloadingFromDefaults = true
        defer { isReloadingFromDefaults = false }

        hasCompletedOnboarding = userDefaults.bool(forKey: UserDefaultsKeys.hasCompletedOnboarding)
        themeMode = ThemeMode(
            rawValue: userDefaults.string(forKey: UserDefaultsKeys.themeMode) ?? ThemeMode.system.rawValue
        ) ?? .system
        opensExploreOnLaunch = userDefaults.bool(forKey: UserDefaultsKeys.opensExploreOnLaunch)
        isMultiCaptureEnabled = userDefaults.bool(forKey: UserDefaultsKeys.isMultiCaptureEnabled)
        requiresScanConfirmation = userDefaults.bool(forKey: UserDefaultsKeys.requiresScanConfirmation)
        showsCaptureGoalProgress = userDefaults.bool(forKey: UserDefaultsKeys.showsCaptureGoalProgress)
        isExpeditionModeActive = userDefaults.bool(forKey: UserDefaultsKeys.isExpeditionModeActive)
        isHapticsEnabled = userDefaults.bool(forKey: UserDefaultsKeys.isHapticsEnabled)
        hasUnseenScan = userDefaults.bool(forKey: UserDefaultsKeys.hasUnseenScan)
        isPushNotificationsEnabled = userDefaults.bool(forKey: UserDefaultsKeys.isPushNotificationsEnabled)
        hasPromptedForNotificationsPostIdent = userDefaults.bool(forKey: UserDefaultsKeys.hasPromptedForNotificationsPostIdent)
        isAchievementNotificationsEnabled = userDefaults.bool(forKey: UserDefaultsKeys.isAchievementNotificationsEnabled)
        isExploreNotificationsEnabled = userDefaults.bool(forKey: UserDefaultsKeys.isExploreNotificationsEnabled)
        isExploreCommentMentionNotificationsEnabled = userDefaults.bool(
            forKey: UserDefaultsKeys.isExploreCommentMentionNotificationsEnabled
        )
        isCommunityIdentificationNotificationsEnabled = userDefaults.bool(
            forKey: UserDefaultsKeys.isCommunityIdentificationNotificationsEnabled
        )
        hasSeenExploreOnboarding = userDefaults.bool(forKey: UserDefaultsKeys.hasSeenExploreOnboarding)
        hasUnseenExplorePost = userDefaults.bool(forKey: UserDefaultsKeys.hasUnseenExplorePost)
        lastSeenExplorePostSharedAt = userDefaults.string(forKey: UserDefaultsKeys.lastSeenExplorePostSharedAt) ?? ""
        feedbackSurveyDismissedCampaignId = userDefaults.string(forKey: UserDefaultsKeys.feedbackSurveyDismissedCampaignId) ?? ""
        feedbackSurveySubmittedCampaignId = userDefaults.string(forKey: UserDefaultsKeys.feedbackSurveySubmittedCampaignId) ?? ""
        feedbackSurveySubmittedAt = userDefaults.double(forKey: UserDefaultsKeys.feedbackSurveySubmittedAt)
        invertZoomDirection = userDefaults.bool(forKey: UserDefaultsKeys.invertZoomDirection)
        zoomSideLeft = userDefaults.bool(forKey: UserDefaultsKeys.zoomSideLeft)
        zoomSliderVisible = userDefaults.bool(forKey: UserDefaultsKeys.zoomSliderVisible)
        isLiveInferencePaused = userDefaults.object(forKey: UserDefaultsKeys.isLiveInferencePaused) as? Bool
            ?? UIDevice.current.isModernIPhone
        suppressInferenceBanners = userDefaults.bool(forKey: UserDefaultsKeys.suppressInferenceBanners)
        saveToCameraRoll = userDefaults.bool(forKey: UserDefaultsKeys.saveToCameraRoll)
        audioHintsEnabled = userDefaults.bool(forKey: UserDefaultsKeys.audioHintsEnabled)
        captureModeOrderRaw = userDefaults.string(forKey: UserDefaultsKeys.captureModeOrder) ?? "visual,audio,describe"
        gridColumns = min(max(userDefaults.integer(forKey: UserDefaultsKeys.gridColumns), 1), 3)
    }

    private func persistBool(_ newValue: Bool, oldValue: Bool, key: String) {
        guard !isReloadingFromDefaults, newValue != oldValue else { return }
        userDefaults.set(newValue, forKey: key)
    }

    private func persistInt(_ newValue: Int, oldValue: Int, key: String) {
        guard !isReloadingFromDefaults, newValue != oldValue else { return }
        userDefaults.set(newValue, forKey: key)
    }

    private func persistDouble(_ newValue: Double, oldValue: Double, key: String) {
        guard !isReloadingFromDefaults, newValue != oldValue else { return }
        userDefaults.set(newValue, forKey: key)
    }

    private func persistString(_ newValue: String, oldValue: String, key: String) {
        guard !isReloadingFromDefaults, newValue != oldValue else { return }
        userDefaults.set(newValue, forKey: key)
    }
}

#if DEBUG
extension AppSettings {
    static var preview: AppSettings {
        let suiteName = "merian.preview.app-settings"
        let previewDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        previewDefaults.removePersistentDomain(forName: suiteName)
        return AppSettings(userDefaults: previewDefaults, observeExternalChanges: false)
    }
}
#endif

import Foundation

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
    /// Cached unread Explore notification count shown on the app icon.
    static let exploreUnreadNotificationBadgeCount =
        "exploreUnreadNotificationBadgeCount"
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
    /// Legacy account-derived count used by the local Firefly badge policy.
    static let unlockedSpeciesCount = "Merian_UnlockedSpeciesCount"
    /// Legacy account-derived Firefly badge state.
    static let hasFireflyBadge = "Merian_HasFireflyBadge"
    /// Legacy account-derived set of achievement types already presented.
    static let unlockedAchievements = "Merian_UnlockedAchievements"
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
    /// Write-ahead journal for a server-prepared, capability-bound Auth
    /// rotation. The raw one-use proof stays device-only until the exact fresh
    /// anonymous destination claims it; the v1 key also recognizes older
    /// client-only markers and keeps them fail-closed.
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

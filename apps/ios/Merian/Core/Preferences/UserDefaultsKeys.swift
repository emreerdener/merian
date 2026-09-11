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
    /// Prefixes for V51 account-scoped preferred-name sync metadata. Append a
    /// lowercased Supabase user UUID to form the full key.
    static let pendingSpeciesPreferredNameDeletesV2Prefix =
        "pendingSpeciesPreferredNameDeletes.v2."
    static let speciesPreferredNameSyncLastAttemptAtV2Prefix =
        "speciesPreferredNameSyncLastAttemptAt.v2."
    static let speciesPreferredNameSyncLastSuccessAtV2Prefix =
        "speciesPreferredNameSyncLastSuccessAt.v2."
    static let speciesPreferredNameSyncStatusV2Prefix =
        "speciesPreferredNameSyncStatus.v2."
    static let speciesPreferredNameSyncMessageV2Prefix =
        "speciesPreferredNameSyncMessage.v2."
    static let speciesPreferredNameSyncLastPushedCountV2Prefix =
        "speciesPreferredNameSyncLastPushedCount.v2."
    static let speciesPreferredNameSyncLastPulledCountV2Prefix =
        "speciesPreferredNameSyncLastPulledCount.v2."
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
    /// Durable, identity-free account-deletion recovery phase. It is written
    /// before destructive intake and advances through local cleanup and proof
    /// retirement so launch recovery can resume without inferring authority.
    static let pendingLocalAccountDeletionCleanup =
        "pendingLocalAccountDeletionCleanup.v1"
}

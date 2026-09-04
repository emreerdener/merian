import Foundation

/// Removes account-derived values and caches that are intentionally stored
/// outside SwiftData.
///
/// Account deletion keeps device-level presentation settings, but per-scan and
/// per-species values must not cross into the next authenticated account.
enum AccountScopedPreferences {
    static let cacheKeyPrefixes: Set<String> = [
        UserDefaultsKeys.captureGoalContextPrefix,
        UserDefaultsKeys.firstFieldTripAchievementProgressPrefix,
        UserDefaultsKeys.dismissedUnavailableMediaOverviewSignaturePrefix,
        UserDefaultsKeys.dismissedProfilePublicationRecoverySignaturePrefix
    ]

    static let cacheKeys: Set<String> = [
        UserDefaultsKeys.hasUnseenScan,
        UserDefaultsKeys.needsCollectionSync,
        UserDefaultsKeys.hiddenSmartCollectionIDs,
        UserDefaultsKeys.hasDismissedIdentifyRequestsBanner,
        UserDefaultsKeys.hasDismissedIdentifyActivityBanner,
        UserDefaultsKeys.hasUnseenExplorePost,
        UserDefaultsKeys.exploreUnreadNotificationBadgeCount,
        UserDefaultsKeys.lastSeenExplorePostSharedAt,
        UserDefaultsKeys.feedbackSurveyDismissedCampaignId,
        UserDefaultsKeys.feedbackSurveySubmittedCampaignId,
        UserDefaultsKeys.feedbackSurveySubmittedAt,
        UserDefaultsKeys.lastHistoricalSyncDate,
        UserDefaultsKeys.unlockedSpeciesCount,
        UserDefaultsKeys.hasFireflyBadge,
        UserDefaultsKeys.unlockedAchievements
    ]

    static func purgeAndVerify(
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        ExploreShareStateStore.clearAll(userDefaults: userDefaults)
        FieldNotesStore.clearAll(userDefaults: userDefaults)
        SpeciesPreferredNameStore.clearAllAccountData(
            userDefaults: userDefaults
        )
        for key in cacheKeys {
            userDefaults.removeObject(forKey: key)
        }
        for key in userDefaults.dictionaryRepresentation().keys
        where cacheKeyPrefixes.contains(where: key.hasPrefix) {
            userDefaults.removeObject(forKey: key)
        }

        guard userDefaults.synchronize() else { return false }
        return !ExploreShareStateStore.hasStoredValues(
            userDefaults: userDefaults
        ) && !FieldNotesStore.hasStoredValues(
            userDefaults: userDefaults
        ) && !SpeciesPreferredNameStore.hasStoredAccountData(
            userDefaults: userDefaults
        ) && !hasStoredCacheValues(userDefaults: userDefaults)
    }

    private static func hasStoredCacheValues(
        userDefaults: UserDefaults
    ) -> Bool {
        let hasPrefixedValue = userDefaults.dictionaryRepresentation().keys
            .contains { key in
                cacheKeyPrefixes.contains(where: key.hasPrefix)
            }
        guard !hasPrefixedValue else { return true }

        let hasEnabledFlag = [
            UserDefaultsKeys.hasUnseenScan,
            UserDefaultsKeys.needsCollectionSync,
            UserDefaultsKeys.hasDismissedIdentifyRequestsBanner,
            UserDefaultsKeys.hasDismissedIdentifyActivityBanner,
            UserDefaultsKeys.hasUnseenExplorePost
        ].contains { userDefaults.bool(forKey: $0) }
        let hasStringValue = [
            UserDefaultsKeys.lastSeenExplorePostSharedAt,
            UserDefaultsKeys.feedbackSurveyDismissedCampaignId,
            UserDefaultsKeys.feedbackSurveySubmittedCampaignId
        ].contains {
            !(userDefaults.string(forKey: $0) ?? "").isEmpty
        }
        let hasHiddenCollections = !(userDefaults.stringArray(
            forKey: UserDefaultsKeys.hiddenSmartCollectionIDs
        ) ?? []).isEmpty
        let hasSurveyTimestamp = userDefaults.double(
            forKey: UserDefaultsKeys.feedbackSurveySubmittedAt
        ) != 0
        let hasHistoricalSyncThrottle = userDefaults.object(
            forKey: UserDefaultsKeys.lastHistoricalSyncDate
        ) != nil
        let hasUnregisteredAccountState = [
            UserDefaultsKeys.exploreUnreadNotificationBadgeCount,
            UserDefaultsKeys.unlockedSpeciesCount,
            UserDefaultsKeys.hasFireflyBadge,
            UserDefaultsKeys.unlockedAchievements
        ].contains { userDefaults.object(forKey: $0) != nil }

        return hasEnabledFlag || hasStringValue || hasHiddenCollections
            || hasSurveyTimestamp || hasHistoricalSyncThrottle
            || hasUnregisteredAccountState
    }
}

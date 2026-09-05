import Foundation
@testable import Merian
import Testing

@Suite("Account-Scoped Preferences")
struct AccountScopedPreferencesTests {
    @Test func purgeInventoryClassifiesEveryDirectAccountCache() {
        #expect(AccountScopedPreferences.cacheKeyPrefixes == [
            UserDefaultsKeys.captureGoalContextPrefix,
            UserDefaultsKeys.firstFieldTripAchievementProgressPrefix,
            UserDefaultsKeys.dismissedUnavailableMediaOverviewSignaturePrefix,
            UserDefaultsKeys
                .dismissedProfilePublicationRecoverySignaturePrefix
        ])
        #expect(AccountScopedPreferences.cacheKeys == [
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
        ])
    }

    @Test func purgeRemovesAccountValuesAndPreservesDeviceSettings() {
        let suiteName =
            "merian.tests.account-scoped-preferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        ExploreShareStateStore.setSharedPostId(
            "explore-post",
            for: "scan-id",
            userDefaults: defaults
        )
        FieldNotesStore.setFieldNotes(
            "Private note",
            for: "scan-id",
            userDefaults: defaults
        )
        let ownerUserID = UUID()
        SpeciesPreferredNameStore.setLegacyPreferredName(
            "Bur Oak",
            for: "Quercus macrocarpa",
            userDefaults: defaults
        )
        SpeciesPreferredNameStore.markPendingCloudDelete(
            for: "Quercus alba",
            ownerUserID: ownerUserID,
            userDefaults: defaults
        )
        SpeciesPreferredNameStore.recordSyncSuccess(
            ownerUserID: ownerUserID,
            pushedCount: 1,
            pulledCount: 2,
            userDefaults: defaults
        )
        for prefix in AccountScopedPreferences.cacheKeyPrefixes {
            defaults.set("account cache", forKey: prefix + "owner-id")
        }
        defaults.set(true, forKey: UserDefaultsKeys.hasUnseenScan)
        defaults.set(true, forKey: UserDefaultsKeys.needsCollectionSync)
        defaults.set(
            ["nearby"],
            forKey: UserDefaultsKeys.hiddenSmartCollectionIDs
        )
        defaults.set(
            true,
            forKey: UserDefaultsKeys.hasDismissedIdentifyRequestsBanner
        )
        defaults.set(
            true,
            forKey: UserDefaultsKeys.hasDismissedIdentifyActivityBanner
        )
        defaults.set(true, forKey: UserDefaultsKeys.hasUnseenExplorePost)
        defaults.set(
            7,
            forKey: UserDefaultsKeys.exploreUnreadNotificationBadgeCount
        )
        defaults.set(
            "2026-09-04T12:00:00Z",
            forKey: UserDefaultsKeys.lastSeenExplorePostSharedAt
        )
        defaults.set(
            "campaign",
            forKey: UserDefaultsKeys.feedbackSurveyDismissedCampaignId
        )
        defaults.set(
            "campaign",
            forKey: UserDefaultsKeys.feedbackSurveySubmittedCampaignId
        )
        defaults.set(
            1_000.0,
            forKey: UserDefaultsKeys.feedbackSurveySubmittedAt
        )
        defaults.set(
            Date(timeIntervalSince1970: 1_000),
            forKey: UserDefaultsKeys.lastHistoricalSyncDate
        )
        defaults.set(12, forKey: UserDefaultsKeys.unlockedSpeciesCount)
        defaults.set(true, forKey: UserDefaultsKeys.hasFireflyBadge)
        defaults.set(
            ["fieldNaturalist"],
            forKey: UserDefaultsKeys.unlockedAchievements
        )
        defaults.set("dark", forKey: UserDefaultsKeys.themeMode)
        defaults.set(true, forKey: UserDefaultsKeys.saveToCameraRoll)

        #expect(AccountScopedPreferences.purgeAndVerify(
            userDefaults: defaults
        ))
        #expect(!ExploreShareStateStore.hasStoredValues(
            userDefaults: defaults
        ))
        #expect(!FieldNotesStore.hasStoredValues(userDefaults: defaults))
        #expect(!SpeciesPreferredNameStore.hasStoredAccountData(
            userDefaults: defaults
        ))
        for prefix in AccountScopedPreferences.cacheKeyPrefixes {
            #expect(!defaults.dictionaryRepresentation().keys.contains {
                $0.hasPrefix(prefix)
            })
        }
        #expect(!defaults.bool(forKey: UserDefaultsKeys.hasUnseenScan))
        #expect(!defaults.bool(forKey: UserDefaultsKeys.needsCollectionSync))
        #expect(
            defaults.stringArray(
                forKey: UserDefaultsKeys.hiddenSmartCollectionIDs
            ) == nil
        )
        #expect(!defaults.bool(
            forKey: UserDefaultsKeys.hasDismissedIdentifyRequestsBanner
        ))
        #expect(!defaults.bool(
            forKey: UserDefaultsKeys.hasDismissedIdentifyActivityBanner
        ))
        #expect(!defaults.bool(forKey: UserDefaultsKeys.hasUnseenExplorePost))
        #expect(defaults.object(
            forKey: UserDefaultsKeys.exploreUnreadNotificationBadgeCount
        ) == nil)
        let persistedValues = defaults.persistentDomain(forName: suiteName)
            ?? [:]
        for registeredAccountKey in [
            UserDefaultsKeys.lastSeenExplorePostSharedAt,
            UserDefaultsKeys.feedbackSurveyDismissedCampaignId,
            UserDefaultsKeys.feedbackSurveySubmittedCampaignId,
            UserDefaultsKeys.feedbackSurveySubmittedAt
        ] {
            #expect(persistedValues[registeredAccountKey] == nil)
        }
        #expect(defaults.object(
            forKey: UserDefaultsKeys.lastHistoricalSyncDate
        ) == nil)
        #expect(defaults.object(
            forKey: UserDefaultsKeys.unlockedSpeciesCount
        ) == nil)
        #expect(defaults.object(
            forKey: UserDefaultsKeys.hasFireflyBadge
        ) == nil)
        #expect(defaults.object(
            forKey: UserDefaultsKeys.unlockedAchievements
        ) == nil)
        #expect(
            defaults.string(forKey: UserDefaultsKeys.themeMode) == "dark"
        )
        #expect(defaults.bool(forKey: UserDefaultsKeys.saveToCameraRoll))
    }

    @MainActor
    @Test func runtimeResetDelegatesToEachStateOwnerOnce() {
        var events: [String] = []

        AccountScopedRuntimeState.reset(
            dependencies: .init(
                refreshSettings: { events.append("settings") },
                resetGamification: { events.append("gamification") },
                resetAppIconBadge: { events.append("badge") },
                clearImageCache: { events.append("images") }
            )
        )

        #expect(events == ["settings", "gamification", "badge", "images"])
    }
}

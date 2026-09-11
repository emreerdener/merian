import Foundation
import Testing

@Suite("UserDefaults key registry")
struct UserDefaultsKeysTests {
    @Test func persistedStringsRemainExactAndComplete() throws {
        let source = try String(
            contentsOf: try registryURL(),
            encoding: .utf8
        )
        let pattern = #"static let\s+([A-Za-z0-9_]+)\s*=\s*\"([^\"]+)\""#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..., in: source)
        let entries = try regex.matches(in: source, range: range).map { match in
            let nameRange = try #require(Range(match.range(at: 1), in: source))
            let valueRange = try #require(Range(match.range(at: 2), in: source))
            return (String(source[nameRange]), String(source[valueRange]))
        }
        let actual = Dictionary(uniqueKeysWithValues: entries)

        #expect(actual == Self.expectedValues)
    }

    private static let expectedValues: [String: String] = [
        "captureGoalContextPrefix": "captureGoalContext.v1.",
        "firstFieldTripAchievementProgressPrefix":
            "firstFieldTripAchievementProgress.v1.",
        "hasCompletedOnboarding": "hasCompletedOnboarding",
        "legalConsentLedger": "legalConsentLedger.v1",
        "themeMode": "themeMode",
        "opensExploreOnLaunch": "opensExploreOnLaunch",
        "isMultiCaptureEnabled": "isMultiCaptureEnabled",
        "requiresScanConfirmation": "requiresScanConfirmation",
        "showsCaptureGoalProgress": "showsCaptureGoalProgress",
        "legacyMultiImageScanMode": "multiImageScanMode",
        "isExpeditionModeActive": "isExpeditionModeActive",
        "isHapticsEnabled": "isHapticsEnabled",
        "hasUnseenScan": "hasUnseenScan",
        "isPushNotificationsEnabled": "isPushNotificationsEnabled",
        "hasPushNotificationAuthorization":
            "hasPushNotificationAuthorization",
        "isAchievementNotificationsEnabled":
            "isAchievementNotificationsEnabled",
        "isExploreNotificationsEnabled": "isExploreNotificationsEnabled",
        "isExploreCommentMentionNotificationsEnabled":
            "isExploreCommentMentionNotificationsEnabled",
        "isCommunityIdentificationNotificationsEnabled":
            "isCommunityIdentificationNotificationsEnabled",
        "remotePushDeviceToken": "remotePushDeviceToken",
        "isLiveInferencePaused": "isLiveInferencePaused",
        "invertZoomDirection": "invertZoomDirection",
        "zoomSideLeft": "zoomSideLeft",
        "zoomSliderVisible": "zoomSliderVisible",
        "saveToCameraRoll": "saveToCameraRoll",
        "audioHintsEnabled": "audioHintsEnabled",
        "gridColumns": "gridColumns",
        "needsCollectionSync": "needsCollectionSync",
        "hiddenSmartCollectionIDs": "hiddenSmartCollectionIDs",
        "dismissedUnavailableMediaOverviewSignaturePrefix":
            "dismissedUnavailableMediaOverviewSignature.v1.",
        "dismissedProfilePublicationRecoverySignaturePrefix":
            "dismissedProfilePublicationRecoverySignature.v1.",
        "speciesPreferredNamePrefix": "speciesPreferredName_",
        "pendingSpeciesPreferredNameDeletes":
            "pendingSpeciesPreferredNameDeletes",
        "speciesPreferredNameSyncLastAttemptAt":
            "speciesPreferredNameSyncLastAttemptAt",
        "speciesPreferredNameSyncLastSuccessAt":
            "speciesPreferredNameSyncLastSuccessAt",
        "speciesPreferredNameSyncStatus": "speciesPreferredNameSyncStatus",
        "speciesPreferredNameSyncMessage": "speciesPreferredNameSyncMessage",
        "speciesPreferredNameSyncLastPushedCount":
            "speciesPreferredNameSyncLastPushedCount",
        "speciesPreferredNameSyncLastPulledCount":
            "speciesPreferredNameSyncLastPulledCount",
        "pendingSpeciesPreferredNameDeletesV2Prefix":
            "pendingSpeciesPreferredNameDeletes.v2.",
        "speciesPreferredNameSyncLastAttemptAtV2Prefix":
            "speciesPreferredNameSyncLastAttemptAt.v2.",
        "speciesPreferredNameSyncLastSuccessAtV2Prefix":
            "speciesPreferredNameSyncLastSuccessAt.v2.",
        "speciesPreferredNameSyncStatusV2Prefix":
            "speciesPreferredNameSyncStatus.v2.",
        "speciesPreferredNameSyncMessageV2Prefix":
            "speciesPreferredNameSyncMessage.v2.",
        "speciesPreferredNameSyncLastPushedCountV2Prefix":
            "speciesPreferredNameSyncLastPushedCount.v2.",
        "speciesPreferredNameSyncLastPulledCountV2Prefix":
            "speciesPreferredNameSyncLastPulledCount.v2.",
        "hasPromptedForNotificationsPostIdent":
            "hasPromptedForNotificationsPostIdent",
        "captureModeOrder": "captureModeOrder",
        "hasSeenExploreOnboarding": "hasSeenExploreOnboarding",
        "hasDismissedIdentifyRequestsBanner":
            "hasDismissedIdentifyRequestsBanner",
        "hasDismissedIdentifyActivityBanner":
            "hasDismissedIdentifyActivityBanner",
        "hasUnseenExplorePost": "hasUnseenExplorePost",
        "exploreUnreadNotificationBadgeCount":
            "exploreUnreadNotificationBadgeCount",
        "feedbackSurveyDismissedCampaignId":
            "feedbackSurveyDismissedCampaignId",
        "feedbackSurveySubmittedCampaignId":
            "feedbackSurveySubmittedCampaignId",
        "feedbackSurveySubmittedAt": "feedbackSurveySubmittedAt",
        "sharedExplorePostIdPrefix": "sharedExplorePostId_",
        "fieldNotesPrefix": "fieldNotes_",
        "lastSeenExplorePostSharedAt": "lastSeenExplorePostSharedAt",
        "suppressInferenceBanners": "suppressInferenceBanners",
        "lastBackgroundedDate": "lastBackgroundedDate",
        "lastHistoricalSyncDate": "lastHistoricalSyncDate",
        "unlockedSpeciesCount": "Merian_UnlockedSpeciesCount",
        "hasFireflyBadge": "Merian_HasFireflyBadge",
        "unlockedAchievements": "Merian_UnlockedAchievements",
        "enrichedSpeciesTimestamps": "enrichedSpeciesTimestamps",
        "localLookalikesCacheResetVersion":
            "localLookalikesCacheResetVersion",
        "analyticsRevocationIntent": "analyticsRevocationIntent.v1",
        "pendingManualAppleRevocationNotice":
            "pendingManualAppleRevocationNotice.v1",
        "pendingLocalAccountDeletionCleanup":
            "pendingLocalAccountDeletionCleanup.v1"
    ]

    private func registryURL() throws -> URL {
        try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Core/Preferences/UserDefaultsKeys.swift"
        )
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("project.yml").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}

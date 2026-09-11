import Foundation
@testable import Merian

@MainActor
var milestoneFeedbackSystemPresenter: MilestoneToastPresenter {
    AppDIContainer.shared.milestoneToastPresenter
}

@MainActor
func resetMilestoneFeedbackGlobalState() {
    milestoneFeedbackSystemPresenter.resetForTesting()
    GamificationManager.shared.unlockedAchievements = []
    UserDefaults.standard.removeObject(
        forKey: UserDefaultsKeys.unlockedAchievements
    )
    UserDefaults.standard.set(
        false,
        forKey: UserDefaultsKeys.hasPushNotificationAuthorization
    )
    UserDefaults.standard.set(
        true,
        forKey: UserDefaultsKeys.isAchievementNotificationsEnabled
    )
}

enum MilestoneFeedbackTestFixtures {
    @MainActor
    static var isolatedCoordinatorDependencies:
        ScanMilestoneCoordinator.Dependencies {
        ScanMilestoneCoordinator.Dependencies(
            currentAccountID: { nil },
            acknowledgeFieldTripProgress: { _ in },
            saveFirstFieldTripAchievement: { _, _ in },
            evaluateAchievementsForNotifications: { $0 }
        )
    }

    @MainActor
    static func coordinator(
        progressResolver: @escaping ScanMilestoneCoordinator.ProgressResolver,
        achievementResolver: @escaping ScanMilestoneCoordinator.AchievementResolver,
        fieldTripsAvailabilityResolver: @escaping ScanMilestoneCoordinator.FieldTripsAvailabilityResolver = { true },
        retryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(15)],
        maximumRetryTaskCount: Int = 16,
        eventSender: (any AppEventSending)? = nil,
        presenter: MilestoneToastPresenter,
        dependencies: ScanMilestoneCoordinator.Dependencies? = nil
    ) -> ScanMilestoneCoordinator {
        ScanMilestoneCoordinator(
            progressResolver: progressResolver,
            achievementResolver: achievementResolver,
            fieldTripsAvailabilityResolver: fieldTripsAvailabilityResolver,
            retryDelays: retryDelays,
            maximumRetryTaskCount: maximumRetryTaskCount,
            eventSender: eventSender ?? AppEventPublisher(),
            presenter: presenter,
            dependencies: dependencies ?? isolatedCoordinatorDependencies
        )
    }

    static var legacyDomesticPetScanDate: Date {
        Date(timeIntervalSince1970: 1_783_119_600)
    }

    static var freshDomesticPetScanDate: Date {
        Date(timeIntervalSince1970: 1_783_126_800)
    }

    static func completedAward(
        _ type: AchievementType,
        lastInteractionDate: Date = Date(),
        unlockedAt: Date? = nil
    ) -> AwardPayload {
        AwardPayload(
            type: type,
            currentCount: type.definition.targetCount,
            lastInteractionDate: lastInteractionDate,
            unlockedAt: unlockedAt ?? lastInteractionDate
        )
    }

    static func milestoneSpecies() -> SpeciesData {
        SpeciesData(
            scanId: "milestone-scan",
            commonName: "Vine Sphinx",
            scientificName: "Eumorpha vitis",
            insightData: InsightData(aiReasoning: "A sphinx moth.", hazardType: "none"),
            confidenceScore: 0.97,
            isBiological: true,
            isLiveCapture: true,
            isInvasive: false,
            ecologyType: "wild"
        )
    }

    static func progressResult(
        challengeCommonName: String? = "Bumble Bee",
        challengePrompt: String = "Bee",
        standardIncludesNewItem: Bool = true
    ) -> FieldTripProgressResult {
        let standardItem = FieldTripProgressCompletedItem(
            itemId: "item-1",
            prompt: "Spider",
            commonName: "Vine Sphinx",
            scientificName: "Eumorpha vitis",
            completedAt: "2026-07-18T14:00:00Z"
        )
        let challengeItem = FieldTripProgressCompletedItem(
            itemId: "challenge-item-1",
            prompt: challengePrompt,
            commonName: challengeCommonName,
            scientificName: "Bombus impatiens",
            completedAt: "2026-07-18T14:00:00Z"
        )

        return FieldTripProgressResult(
            fieldTripUpdates: [
                FieldTripProgressUpdate(
                    userFieldTripId: "trip-1",
                    templateId: "template-1",
                    slug: "backyard_safari",
                    title: "Backyard Safari",
                    currentLevelNumber: 2,
                    currentLevelTitle: "Level 2",
                    completedCount: 0,
                    targetCount: 6,
                    isComplete: false,
                    creditedLevelNumber: 1,
                    creditedLevelTitle: "Level 1",
                    creditedCompletedCount: 4,
                    creditedTargetCount: 4,
                    newlyCompletedItems: standardIncludesNewItem ? [standardItem] : [],
                    removedItemIds: nil
                )
            ],
            challengeUpdates: [
                FieldTripChallengeProgressUpdate(
                    participationId: "participation-1",
                    challengeId: "challenge-1",
                    slug: "summer_pollinators",
                    title: "Summer pollinators",
                    currentLevelNumber: 1,
                    currentLevelTitle: "Level 1",
                    completedCount: 2,
                    targetCount: 4,
                    isComplete: false,
                    badgeAwardedAt: nil,
                    suggestedHashtags: ["summerpollinators"],
                    creditedLevelNumber: 1,
                    creditedLevelTitle: "Level 1",
                    creditedCompletedCount: 2,
                    creditedTargetCount: 4,
                    newlyCompletedItems: [challengeItem],
                    removedItemIds: nil
                )
            ]
        )
    }
}

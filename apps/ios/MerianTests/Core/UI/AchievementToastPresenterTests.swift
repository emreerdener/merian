import Foundation
@testable import Merian
import Testing

@MainActor
struct AchievementToastPresenterTests {
    private let unlockedAchievementsKey = "Merian_UnlockedAchievements"

    init() {
        AchievementToastPresenter.shared.resetForTesting()
        GamificationManager.shared.unlockedAchievements = []
        UserDefaults.standard.removeObject(forKey: unlockedAchievementsKey)
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.hasPushNotificationAuthorization)
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.isAchievementNotificationsEnabled)
    }

    @Test func previewAchievementUnlockPresentsWithoutPersistingUnlock() {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.isAchievementNotificationsEnabled)

        MilestoneToastPresenter.shared.previewAchievementUnlock(completedAward(.domesticCat))

        #expect(MilestoneToastPresenter.shared.activeItem?.award?.type == .domesticCat)
        #expect(MilestoneToastPresenter.shared.activeItem?.source == .preview)
        #expect(GamificationManager.shared.unlockedAchievements.isEmpty)
        #expect(UserDefaults.standard.stringArray(forKey: unlockedAchievementsKey) == nil)
    }

    @Test func queuedAchievementUnlocksPresentFIFO() {
        MilestoneToastPresenter.shared.previewAchievementUnlock(completedAward(.domesticCat))
        MilestoneToastPresenter.shared.previewAchievementUnlock(completedAward(.domesticDog))
        MilestoneToastPresenter.shared.previewAchievementUnlock(completedAward(.nocturnal))

        #expect(MilestoneToastPresenter.shared.activeItem?.award?.type == .domesticCat)
        #expect(MilestoneToastPresenter.shared.queuedItemCount == 2)

        let firstID = MilestoneToastPresenter.shared.activeItem?.id
        MilestoneToastPresenter.shared.dismissActiveItem(id: firstID)

        #expect(MilestoneToastPresenter.shared.activeItem?.award?.type == .domesticDog)
        #expect(MilestoneToastPresenter.shared.queuedItemCount == 1)

        let secondID = MilestoneToastPresenter.shared.activeItem?.id
        MilestoneToastPresenter.shared.dismissActiveItem(id: secondID)

        #expect(MilestoneToastPresenter.shared.activeItem?.award?.type == .nocturnal)
        #expect(MilestoneToastPresenter.shared.queuedItemCount == 0)

        let thirdID = MilestoneToastPresenter.shared.activeItem?.id
        MilestoneToastPresenter.shared.dismissActiveItem(id: thirdID)

        #expect(MilestoneToastPresenter.shared.activeItem == nil)
    }

    @Test func mixedMilestoneQueuePresentsFIFO() {
        MilestoneToastPresenter.shared.previewAchievementUnlock(completedAward(.domesticCat))
        MilestoneToastPresenter.shared.previewNewToMerianMilestone()
        MilestoneToastPresenter.shared.previewAchievementUnlock(completedAward(.domesticDog))

        #expect(MilestoneToastPresenter.shared.activeItem?.award?.type == .domesticCat)
        #expect(MilestoneToastPresenter.shared.queuedItemCount == 2)

        let firstID = MilestoneToastPresenter.shared.activeItem?.id
        MilestoneToastPresenter.shared.dismissActiveItem(id: firstID)

        guard case .dictionary(let milestone) = MilestoneToastPresenter.shared.activeItem?.payload else {
            Issue.record("Expected New to Naturebook milestone to present second")
            return
        }

        #expect(milestone == .newToMerian)
        #expect(MilestoneToastPresenter.shared.queuedItemCount == 1)

        let secondID = MilestoneToastPresenter.shared.activeItem?.id
        MilestoneToastPresenter.shared.dismissActiveItem(id: secondID)

        #expect(MilestoneToastPresenter.shared.activeItem?.award?.type == .domesticDog)
    }

    @Test func completedAchievementUnlockEnqueuesToastWhenAchievementNotificationsAreEnabled() {
        GamificationManager.shared.evaluateAchievementsForNotifications(awards: [completedAward(.domesticDog)])

        #expect(MilestoneToastPresenter.shared.activeItem?.award?.type == .domesticDog)
        #expect(MilestoneToastPresenter.shared.activeItem?.source == .unlock)
        #expect(GamificationManager.shared.unlockedAchievements.contains(.domesticDog))
    }

    @Test func legacyDomesticPetAchievementCompletionIsPersistedWithoutToast() {
        GamificationManager.shared.evaluateAchievementsForNotifications(awards: [
            completedAward(.domesticCat, lastInteractionDate: legacyDomesticPetScanDate)
        ])

        #expect(MilestoneToastPresenter.shared.activeItem == nil)
        #expect(GamificationManager.shared.unlockedAchievements.contains(.domesticCat))
    }

    @Test func legacyCatAndFreshDogOnlyToastFreshDog() {
        GamificationManager.shared.evaluateAchievementsForNotifications(awards: [
            completedAward(.domesticCat, lastInteractionDate: legacyDomesticPetScanDate),
            completedAward(.domesticDog, lastInteractionDate: freshDomesticPetScanDate)
        ])

        #expect(MilestoneToastPresenter.shared.activeItem?.award?.type == .domesticDog)
        #expect(MilestoneToastPresenter.shared.queuedItemCount == 0)
        #expect(GamificationManager.shared.unlockedAchievements.contains(.domesticCat))
        #expect(GamificationManager.shared.unlockedAchievements.contains(.domesticDog))
    }

    @Test func legacyUnlockWithFreshRepeatScanIsPersistedWithoutToast() {
        GamificationManager.shared.evaluateAchievementsForNotifications(awards: [
            completedAward(
                .domesticDog,
                lastInteractionDate: freshDomesticPetScanDate,
                unlockedAt: legacyDomesticPetScanDate
            )
        ])

        #expect(MilestoneToastPresenter.shared.activeItem == nil)
        #expect(GamificationManager.shared.unlockedAchievements.contains(.domesticDog))
    }

    @Test func completedAchievementUnlockDoesNotEnqueueToastWhenAchievementNotificationsAreDisabled() {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.isAchievementNotificationsEnabled)

        GamificationManager.shared.evaluateAchievementsForNotifications(awards: [completedAward(.domesticCat)])

        #expect(MilestoneToastPresenter.shared.activeItem == nil)
        #expect(GamificationManager.shared.unlockedAchievements.contains(.domesticCat))
    }

    @Test func previewNewToMerianMilestonePresentsWithoutPersistingUnlock() {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.isAchievementNotificationsEnabled)

        MilestoneToastPresenter.shared.previewNewToMerianMilestone()

        guard case .dictionary(let milestone) = MilestoneToastPresenter.shared.activeItem?.payload else {
            Issue.record("Expected New to Naturebook milestone")
            return
        }

        #expect(milestone == .newToMerian)
        #expect(MilestoneToastPresenter.shared.activeItem?.source == .preview)
        #expect(GamificationManager.shared.unlockedAchievements.isEmpty)
        #expect(UserDefaults.standard.stringArray(forKey: unlockedAchievementsKey) == nil)
    }

    @Test func scanMilestonesWaitForProgressThenPresentInRequiredOrder() async {
        let presenter = MilestoneToastPresenter()
        var progressContinuation: CheckedContinuation<FieldTripProgressResult?, Never>?
        let achievement = completedAward(.domesticDog)
        let coordinator = ScanMilestoneCoordinator(
            progressResolver: { _ in
                await withCheckedContinuation { continuation in
                    progressContinuation = continuation
                }
            },
            achievementResolver: { _ in [achievement] },
            presenter: presenter
        )
        var species = milestoneSpecies()
        species.isNewToMerianDictionary = true

        let task = Task {
            await coordinator.processCompletedScan(
                scanId: "ordered-scan",
                speciesData: species,
                modelContainer: nil
            )
        }

        while progressContinuation == nil {
            await Task.yield()
        }
        #expect(presenter.activeItem == nil)

        progressContinuation?.resume(returning: progressResult())
        await task.value

        guard case .fieldTrip(let fieldTrip) = presenter.activeItem?.payload else {
            Issue.record("Expected Field trip progress first")
            return
        }
        #expect(fieldTrip.message == "Vine Sphinx counts toward Backyard safari")
        #expect(fieldTrip.completedCount == 4)
        #expect(fieldTrip.targetCount == 4)

        presenter.dismissActiveItem(id: presenter.activeItem?.id)
        guard case .fieldTrip(let challenge) = presenter.activeItem?.payload else {
            Issue.record("Expected seasonal challenge second")
            return
        }
        #expect(challenge.destination == .fieldTripChallenge(challengeId: "challenge-1"))

        presenter.dismissActiveItem(id: presenter.activeItem?.id)
        #expect(presenter.activeItem?.award?.type == .domesticDog)

        presenter.dismissActiveItem(id: presenter.activeItem?.id)
        guard case .dictionary(let milestone) = presenter.activeItem?.payload else {
            Issue.record("Expected New to Naturebook last")
            return
        }
        #expect(milestone == .newToMerian)
    }

    @Test func failedProgressStillReleasesAchievementAndDictionaryMilestones() async {
        let presenter = MilestoneToastPresenter()
        let achievement = completedAward(.domesticCat)
        let coordinator = ScanMilestoneCoordinator(
            progressResolver: { _ in nil },
            achievementResolver: { _ in [achievement] },
            presenter: presenter
        )
        var species = milestoneSpecies()
        species.isNewToMerianDictionary = true

        await coordinator.processCompletedScan(
            scanId: "failed-progress-scan",
            speciesData: species,
            modelContainer: nil
        )

        #expect(presenter.activeItem?.award?.type == .domesticCat)
        presenter.dismissActiveItem(id: presenter.activeItem?.id)
        guard case .dictionary = presenter.activeItem?.payload else {
            Issue.record("Expected dictionary milestone after achievement")
            return
        }
    }

    @Test func noMatchingProgressStillReleasesAchievementAndDictionaryMilestones() async {
        let presenter = MilestoneToastPresenter()
        let achievement = completedAward(.domesticDog)
        let coordinator = ScanMilestoneCoordinator(
            progressResolver: { _ in
                FieldTripProgressResult(fieldTripUpdates: [], challengeUpdates: [])
            },
            achievementResolver: { _ in [achievement] },
            presenter: presenter
        )
        var species = milestoneSpecies()
        species.isNewToMerianDictionary = true

        await coordinator.processCompletedScan(
            scanId: "no-match-scan",
            speciesData: species,
            modelContainer: nil
        )

        #expect(presenter.activeItem?.award?.type == .domesticDog)
        presenter.dismissActiveItem(id: presenter.activeItem?.id)
        guard case .dictionary = presenter.activeItem?.payload else {
            Issue.record("Expected dictionary milestone after achievement")
            return
        }
    }

    @Test func liveAndBackgroundCompletionRaceProcessesScanOnce() async {
        let presenter = MilestoneToastPresenter()
        var resolverCalls = 0
        var progressContinuation: CheckedContinuation<FieldTripProgressResult?, Never>?
        let coordinator = ScanMilestoneCoordinator(
            progressResolver: { _ in
                resolverCalls += 1
                return await withCheckedContinuation { continuation in
                    progressContinuation = continuation
                }
            },
            achievementResolver: { _ in [] },
            presenter: presenter
        )

        let liveTask = Task {
            await coordinator.processCompletedScan(
                scanId: "race-scan",
                speciesData: nil,
                modelContainer: nil
            )
        }
        while progressContinuation == nil {
            await Task.yield()
        }
        let backgroundTask = Task {
            await coordinator.processCompletedScan(
                scanId: "race-scan",
                speciesData: nil,
                modelContainer: nil
            )
        }

        await backgroundTask.value
        progressContinuation?.resume(returning: nil)
        await liveTask.value

        #expect(resolverCalls == 1)
    }

    @Test func progressMappingKeepsStandardBeforeChallengeAndFallsBackToPrompt() {
        let result = progressResult(
            challengeCommonName: "   ",
            challengePrompt: "Bee or wasp"
        )

        let milestones = ScanMilestoneCoordinator.milestones(from: result)

        #expect(milestones.count == 2)
        #expect(milestones[0].tripTitle == "Backyard safari")
        #expect(milestones[0].destination == .fieldTrip(templateId: "template-1", checklistItemId: "item-1"))
        #expect(milestones[1].tripTitle == "Summer pollinators")
        #expect(milestones[1].speciesLabel == "Bee or wasp")
        #expect(milestones[1].destination == .fieldTripChallenge(challengeId: "challenge-1"))
    }

    @Test func progressMappingIgnoresUpdatesWithoutNewlyCompletedItems() {
        let result = progressResult(standardIncludesNewItem: false)

        let milestones = ScanMilestoneCoordinator.milestones(from: result)

        #expect(milestones.count == 1)
        #expect(milestones[0].tripTitle == "Summer pollinators")
        #expect(milestones[0].destination == .fieldTripChallenge(challengeId: "challenge-1"))
    }

    private var legacyDomesticPetScanDate: Date {
        Date(timeIntervalSince1970: 1_783_119_600)
    }

    private var freshDomesticPetScanDate: Date {
        Date(timeIntervalSince1970: 1_783_126_800)
    }

    private func completedAward(
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

    private func milestoneSpecies() -> SpeciesData {
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

    private func progressResult(
        challengeCommonName: String? = "Bumble Bee",
        challengePrompt: String = "Bee",
        standardIncludesNewItem: Bool = true
    ) -> FieldTripProgressResult {
        let standardItem = FieldTripProgressCompletedItem(
            itemId: "item-1",
            prompt: "Butterfly or moth",
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
                    title: "Backyard safari",
                    currentLevelNumber: 2,
                    currentLevelTitle: "Level 2",
                    completedCount: 0,
                    targetCount: 6,
                    isComplete: false,
                    creditedLevelNumber: 1,
                    creditedLevelTitle: "Level 1",
                    creditedCompletedCount: 4,
                    creditedTargetCount: 4,
                    newlyCompletedItems: standardIncludesNewItem ? [standardItem] : []
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
                    newlyCompletedItems: [challengeItem]
                )
            ]
        )
    }
}

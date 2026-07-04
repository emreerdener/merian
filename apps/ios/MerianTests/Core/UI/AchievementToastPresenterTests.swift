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
            Issue.record("Expected New to Merian milestone to present second")
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
            Issue.record("Expected New to Merian milestone")
            return
        }

        #expect(milestone == .newToMerian)
        #expect(MilestoneToastPresenter.shared.activeItem?.source == .preview)
        #expect(GamificationManager.shared.unlockedAchievements.isEmpty)
        #expect(UserDefaults.standard.stringArray(forKey: unlockedAchievementsKey) == nil)
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
}

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

        AchievementToastPresenter.shared.previewAchievementUnlock(completedAward(.domesticCat))

        #expect(AchievementToastPresenter.shared.activeUnlock?.award.type == .domesticCat)
        #expect(AchievementToastPresenter.shared.activeUnlock?.source == .preview)
        #expect(GamificationManager.shared.unlockedAchievements.isEmpty)
        #expect(UserDefaults.standard.stringArray(forKey: unlockedAchievementsKey) == nil)
    }

    @Test func queuedAchievementUnlocksPresentFIFO() {
        AchievementToastPresenter.shared.previewAchievementUnlock(completedAward(.domesticCat))
        AchievementToastPresenter.shared.previewAchievementUnlock(completedAward(.domesticDog))
        AchievementToastPresenter.shared.previewAchievementUnlock(completedAward(.nocturnal))

        #expect(AchievementToastPresenter.shared.activeUnlock?.award.type == .domesticCat)
        #expect(AchievementToastPresenter.shared.queuedUnlockCount == 2)

        let firstID = AchievementToastPresenter.shared.activeUnlock?.id
        AchievementToastPresenter.shared.dismissActiveUnlock(id: firstID)

        #expect(AchievementToastPresenter.shared.activeUnlock?.award.type == .domesticDog)
        #expect(AchievementToastPresenter.shared.queuedUnlockCount == 1)

        let secondID = AchievementToastPresenter.shared.activeUnlock?.id
        AchievementToastPresenter.shared.dismissActiveUnlock(id: secondID)

        #expect(AchievementToastPresenter.shared.activeUnlock?.award.type == .nocturnal)
        #expect(AchievementToastPresenter.shared.queuedUnlockCount == 0)

        let thirdID = AchievementToastPresenter.shared.activeUnlock?.id
        AchievementToastPresenter.shared.dismissActiveUnlock(id: thirdID)

        #expect(AchievementToastPresenter.shared.activeUnlock == nil)
    }

    @Test func completedAchievementUnlockEnqueuesToastWhenAchievementNotificationsAreEnabled() {
        GamificationManager.shared.evaluateAchievementsForNotifications(awards: [completedAward(.domesticDog)])

        #expect(AchievementToastPresenter.shared.activeUnlock?.award.type == .domesticDog)
        #expect(AchievementToastPresenter.shared.activeUnlock?.source == .unlock)
        #expect(GamificationManager.shared.unlockedAchievements.contains(.domesticDog))
    }

    @Test func completedAchievementUnlockDoesNotEnqueueToastWhenAchievementNotificationsAreDisabled() {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.isAchievementNotificationsEnabled)

        GamificationManager.shared.evaluateAchievementsForNotifications(awards: [completedAward(.domesticCat)])

        #expect(AchievementToastPresenter.shared.activeUnlock == nil)
        #expect(GamificationManager.shared.unlockedAchievements.contains(.domesticCat))
    }

    private func completedAward(_ type: AchievementType) -> AwardPayload {
        AwardPayload(
            type: type,
            currentCount: type.definition.targetCount,
            lastInteractionDate: Date()
        )
    }
}

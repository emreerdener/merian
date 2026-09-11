import Foundation
@testable import Merian
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.gamificationManager))
struct MilestoneAchievementPolicyTests {
    private let unlockedAchievementsKey = UserDefaultsKeys.unlockedAchievements

    init() {
        resetMilestoneFeedbackGlobalState()
    }

    @Test func completedAchievementUnlockReturnsTypedPresentationPayloadWhenEnabled() {
        let eligible = GamificationManager.shared.evaluateAchievementsForNotifications(
            awards: [MilestoneFeedbackTestFixtures.completedAward(.domesticDog)]
        )

        #expect(eligible.map(\.type) == [.domesticDog])
        #expect(milestoneFeedbackSystemPresenter.activeItem == nil)
        #expect(GamificationManager.shared.unlockedAchievements.contains(.domesticDog))
    }

    @Test func legacyDomesticPetAchievementCompletionIsPersistedWithoutToast() {
        let eligible = GamificationManager.shared.evaluateAchievementsForNotifications(awards: [
            MilestoneFeedbackTestFixtures.completedAward(.domesticCat, lastInteractionDate: MilestoneFeedbackTestFixtures.legacyDomesticPetScanDate)
        ])

        #expect(eligible.isEmpty)
        #expect(milestoneFeedbackSystemPresenter.activeItem == nil)
        #expect(GamificationManager.shared.unlockedAchievements.contains(.domesticCat))
    }

    @Test func legacyCatAndFreshDogOnlyReturnsFreshDog() {
        let eligible = GamificationManager.shared.evaluateAchievementsForNotifications(awards: [
            MilestoneFeedbackTestFixtures.completedAward(.domesticCat, lastInteractionDate: MilestoneFeedbackTestFixtures.legacyDomesticPetScanDate),
            MilestoneFeedbackTestFixtures.completedAward(.domesticDog, lastInteractionDate: MilestoneFeedbackTestFixtures.freshDomesticPetScanDate)
        ])

        #expect(eligible.map(\.type) == [.domesticDog])
        #expect(milestoneFeedbackSystemPresenter.activeItem == nil)
        #expect(GamificationManager.shared.unlockedAchievements.contains(.domesticCat))
        #expect(GamificationManager.shared.unlockedAchievements.contains(.domesticDog))
    }

    @Test func legacyUnlockWithFreshRepeatScanIsPersistedWithoutToast() {
        let eligible = GamificationManager.shared.evaluateAchievementsForNotifications(awards: [
            MilestoneFeedbackTestFixtures.completedAward(
                .domesticDog,
                lastInteractionDate: MilestoneFeedbackTestFixtures.freshDomesticPetScanDate,
                unlockedAt: MilestoneFeedbackTestFixtures.legacyDomesticPetScanDate
            )
        ])

        #expect(eligible.isEmpty)
        #expect(milestoneFeedbackSystemPresenter.activeItem == nil)
        #expect(GamificationManager.shared.unlockedAchievements.contains(.domesticDog))
    }

    @Test func completedAchievementUnlockIsNotPresentationEligibleWhenNotificationsAreDisabled() {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.isAchievementNotificationsEnabled)

        let eligible = GamificationManager.shared.evaluateAchievementsForNotifications(
            awards: [MilestoneFeedbackTestFixtures.completedAward(.domesticCat)]
        )

        #expect(eligible.isEmpty)
        #expect(milestoneFeedbackSystemPresenter.activeItem == nil)
        #expect(GamificationManager.shared.unlockedAchievements.contains(.domesticCat))
    }

    @Test func previewNewToMerianMilestonePresentsWithoutPersistingUnlock() {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.isAchievementNotificationsEnabled)

        milestoneFeedbackSystemPresenter.previewNewToMerianMilestone()

        guard case .dictionary(let milestone) = milestoneFeedbackSystemPresenter.activeItem?.payload else {
            Issue.record("Expected New to Naturebook milestone")
            return
        }

        #expect(milestone == .newToMerian)
        #expect(milestoneFeedbackSystemPresenter.activeItem?.source == .preview)
        #expect(GamificationManager.shared.unlockedAchievements.isEmpty)
        #expect(UserDefaults.standard.stringArray(forKey: unlockedAchievementsKey) == nil)
    }

    @Test func firstFieldTripAchievementNotificationIsDeduplicated() {
        let progress = FirstFieldTripAchievementProgress(
            kind: .standardOuting,
            completedAt: "2026-07-18T14:00:00Z",
            templateSlug: "backyard_safari",
            challengeId: nil
        )
        guard let award = progress.awardPayload else {
            Issue.record("Expected a valid first Field trip award")
            return
        }

        let first = GamificationManager.shared.evaluateAchievementsForNotifications(
            awards: [award]
        )
        let duplicate = GamificationManager.shared.evaluateAchievementsForNotifications(
            awards: [award]
        )

        #expect(first.map(\.type) == [.firstFieldTrip])
        #expect(duplicate.isEmpty)
    }

    @Test func firstFieldTripAchievementProgressCachesPerAccountAndMergesAward() throws {
        let progress = FirstFieldTripAchievementProgress(
            kind: .seasonalChallenge,
            completedAt: "2026-07-18T14:00:00.123Z",
            templateSlug: nil,
            challengeId: "challenge-1"
        )
        let suiteName = "FirstFieldTripAchievementProgressStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        FirstFieldTripAchievementProgressStore.save(
            progress,
            accountId: "ACCOUNT-A",
            userDefaults: defaults
        )

        #expect(
            FirstFieldTripAchievementProgressStore.load(
                accountId: "account-a",
                userDefaults: defaults
            ) == progress
        )
        #expect(
            FirstFieldTripAchievementProgressStore.load(
                accountId: "account-b",
                userDefaults: defaults
            ) == nil
        )

        let locked = AwardPayload(
            type: .firstFieldTrip,
            currentCount: 0,
            lastInteractionDate: nil
        )
        let merged = [locked].mergingFirstFieldTripAchievement(progress)
        #expect(merged.count == 1)
        #expect(merged[0].isCompleted)
        #expect(
            merged[0].destination
                == .fieldTripChallenge(challengeId: "challenge-1")
        )
    }
}

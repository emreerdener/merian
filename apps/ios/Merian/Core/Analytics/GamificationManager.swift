import Foundation
import Observation
import os

/// Manages gamification state: species unlock count, badges, and achievements.
@MainActor
@Observable final class GamificationManager {
    static let shared = GamificationManager()

    // MARK: - State

    var unlockedSpeciesCount: Int
    var hasFireflyBadge: Bool
    var showTerrariumSheet: Bool = false
    var unlockedAchievements: Set<AchievementType>

    // MARK: - Storage Keys

    private let defaults = UserDefaults.standard
    private let speciesCountKey        = "Merian_UnlockedSpeciesCount"
    private let fireflyBadgeKey        = "Merian_HasFireflyBadge"
    private let unlockedAchievementsKey = "Merian_UnlockedAchievements"
    // 2026-07-04 00:00:00 UTC: cat/dog achievements shipped after users already
    // had scan history, so legacy completions should be seeded without a toast.
    private let retroactiveAchievementNotificationCutoffs: [AchievementType: Date] = [
        .domesticCat: Date(timeIntervalSince1970: 1_783_123_200),
        .domesticDog: Date(timeIntervalSince1970: 1_783_123_200)
    ]

    private init() {
        unlockedSpeciesCount = defaults.integer(forKey: speciesCountKey)
        hasFireflyBadge      = defaults.bool(forKey: fireflyBadgeKey)
        unlockedAchievements = Set(
            (defaults.stringArray(forKey: unlockedAchievementsKey) ?? [])
                .compactMap(AchievementType.init(rawValue:))
        )
    }

    // MARK: - Recording

    /// Records a newly discovered species and evaluates badge unlocks.
    func recordNewSpeciesDiscovered() {
        unlockedSpeciesCount += 1
        defaults.set(unlockedSpeciesCount, forKey: speciesCountKey)
        MerianLog.general.debug("Species count: \(self.unlockedSpeciesCount, privacy: .public)")

        // 5 unique species unlocks the Firefly Badge.
        if unlockedSpeciesCount >= 5 && !hasFireflyBadge {
            unlockFireflyBadge()
        }
    }

    /// Checks `awards` for newly completed achievements and triggers notifications if enabled.
    /// Returns the unlocks eligible for an in-app toast so scan completion can batch them
    /// behind any Field trip progress notifications.
    @discardableResult
    func evaluateAchievementsForNotifications(
        awards: [AwardPayload],
        enqueueToasts: Bool = true
    ) -> [AwardPayload] {
        var toastEligibleAwards: [AwardPayload] = []

        for award in awards where award.isCompleted {
            guard !unlockedAchievements.contains(award.type) else { continue }

            unlockedAchievements.insert(award.type)
            defaults.set(unlockedAchievements.map(\.rawValue), forKey: unlockedAchievementsKey)
            MerianLog.general.debug("Achievement unlocked: \(award.title, privacy: .public)")

            let achievementsEnabled = defaults.object(forKey: UserDefaultsKeys.isAchievementNotificationsEnabled) as? Bool ?? true
            let systemPushEnabled = defaults.bool(forKey: UserDefaultsKeys.hasPushNotificationAuthorization)

            if achievementsEnabled && shouldNotifyUnlock(for: award) {
                toastEligibleAwards.append(award)

                if enqueueToasts {
                    AchievementToastPresenter.shared.enqueueAchievementUnlock(award)
                }

                if systemPushEnabled {
                    PushNotificationManager.shared.sendAchievementUnlockedNotification(achievementTitle: award.title)
                }
            }
        }

        return toastEligibleAwards
    }

    // MARK: - Private

    private func shouldNotifyUnlock(for award: AwardPayload) -> Bool {
        guard let cutoff = retroactiveAchievementNotificationCutoffs[award.type],
              let unlockedAt = award.unlockedAt ?? award.lastInteractionDate else {
            return true
        }

        return unlockedAt >= cutoff
    }

    private func unlockFireflyBadge() {
        hasFireflyBadge = true
        defaults.set(true, forKey: fireflyBadgeKey)
        MerianLog.general.debug("Firefly Badge unlocked.")
        HapticManager.shared.triggerSelectionPulse()
    }
}

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
    var unlockedAchievements: Set<String>

    // MARK: - Storage Keys

    private let defaults = UserDefaults.standard
    private let speciesCountKey        = "Merian_UnlockedSpeciesCount"
    private let fireflyBadgeKey        = "Merian_HasFireflyBadge"
    private let unlockedAchievementsKey = "Merian_UnlockedAchievements"

    private init() {
        unlockedSpeciesCount = defaults.integer(forKey: speciesCountKey)
        hasFireflyBadge      = defaults.bool(forKey: fireflyBadgeKey)
        unlockedAchievements = Set(defaults.stringArray(forKey: unlockedAchievementsKey) ?? [])
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
    func evaluateAchievementsForNotifications(awards: [AwardPayload]) {
        for award in awards where award.isCompleted {
            guard !unlockedAchievements.contains(award.type) else { continue }

            unlockedAchievements.insert(award.type)
            defaults.set(Array(unlockedAchievements), forKey: unlockedAchievementsKey)
            MerianLog.general.debug("Achievement unlocked: \(award.title, privacy: .public)")

            if defaults.bool(forKey: "isAchievementNotificationsEnabled") {
                PushNotificationManager.shared.sendAchievementUnlockedNotification(achievementTitle: award.title)
            }
        }
    }

    // MARK: - Private

    private func unlockFireflyBadge() {
        hasFireflyBadge = true
        defaults.set(true, forKey: fireflyBadgeKey)
        MerianLog.general.debug("Firefly Badge unlocked.")
        HapticManager.shared.triggerSelectionPulse()
    }
}

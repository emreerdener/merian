import Foundation
import Combine
import Observation
import os

// MARK: - Core Gamification Engine
/// Tracks Gamification mechanics like Streaks, Badges, and Unlocked Species to drive the Digital Terrarium state.
@MainActor
@Observable final class GamificationManager {
    // MARK: - Singleton Architecture
    static let shared = GamificationManager()
    
    // MARK: - State Management
    var unlockedSpeciesCount: Int
    var hasFireflyBadge: Bool
    var showTerrariumSheet: Bool = false
    var unlockedAchievements: Set<String>
    
    // MARK: - Persistent Storage Keys
    private let defaults = UserDefaults.standard
    private let speciesCountKey = "Merian_UnlockedSpeciesCount"
    private let fireflyBadgeKey = "Merian_HasFireflyBadge"
    private let unlockedAchievementsKey = "Merian_UnlockedAchievements"
    
    // MARK: - Lifecycle Bootstrapping
    private init() {
        self.unlockedSpeciesCount = defaults.integer(forKey: speciesCountKey)
        self.hasFireflyBadge = defaults.bool(forKey: fireflyBadgeKey)
        
        if let stored = defaults.stringArray(forKey: unlockedAchievementsKey) {
            self.unlockedAchievements = Set(stored)
        } else {
            self.unlockedAchievements = []
        }
    }
    
    // MARK: - Badge Execution Triggers
    /// Called when a taxonomic scan validates natively or offline queue hits 200 OK
    func recordNewSpeciesDiscovered() {
        self.unlockedSpeciesCount += 1
        self.defaults.set(self.unlockedSpeciesCount, forKey: self.speciesCountKey)
        
        MerianLog.general.debug("🏆 Gamification: Species count increased to \(self.unlockedSpeciesCount, privacy: .public)")
        
        // Example threshold: hitting 5 distinct taxonomies unlocks the ecosystem fireflies
        if self.unlockedSpeciesCount >= 5 && !self.hasFireflyBadge {
            self.unlockFireflyBadge()
        }
    }
    
    /// Evaluates if any achievement organically resolved exactly this session natively.
    func evaluateAchievementsForNotifications(awards: [AwardPayload]) {
        for award in awards where award.isCompleted {
            if !self.unlockedAchievements.contains(award.type) {
                // IT'S A NEW UNLOCK!
                self.unlockedAchievements.insert(award.type)
                self.defaults.set(Array(self.unlockedAchievements), forKey: self.unlockedAchievementsKey)
                
                MerianLog.general.debug("🏆 Gamification: New achievement evaluated offline: \(award.title, privacy: .public)")
                
                if self.defaults.bool(forKey: "isAchievementNotificationsEnabled") {
                    PushNotificationManager.shared.sendAchievementUnlockedNotification(achievementTitle: award.title)
                }
            }
        }
    }
    
    private func unlockFireflyBadge() {
        self.hasFireflyBadge = true
        self.defaults.set(true, forKey: self.fireflyBadgeKey)
        MerianLog.general.debug("🏆 Gamification: Firefly Badge Unlocked!")
        // Trigger any necessary Apple native Haptics or Telemetry here
        HapticManager.shared.triggerSelectionPulse()
    }
}

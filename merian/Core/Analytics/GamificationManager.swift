import Foundation
import Combine
import Observation

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
    
    // MARK: - Persistent Storage Keys
    private let defaults = UserDefaults.standard
    private let speciesCountKey = "Merian_UnlockedSpeciesCount"
    private let fireflyBadgeKey = "Merian_HasFireflyBadge"
    
    // MARK: - Lifecycle Bootstrapping
    private init() {
        self.unlockedSpeciesCount = defaults.integer(forKey: speciesCountKey)
        self.hasFireflyBadge = defaults.bool(forKey: fireflyBadgeKey)
    }
    
    // MARK: - Badge Execution Triggers
    /// Called when a taxonomic scan validates natively or offline queue hits 200 OK
    func recordNewSpeciesDiscovered() {
        unlockedSpeciesCount += 1
        defaults.set(unlockedSpeciesCount, forKey: speciesCountKey)
        
        print("🏆 Gamification: Species count increased to \(unlockedSpeciesCount)")
        
        // Example threshold: hitting 5 distinct taxonomies unlocks the ecosystem fireflies
        if unlockedSpeciesCount >= 5 && !hasFireflyBadge {
            unlockFireflyBadge()
        }
    }
    
    private func unlockFireflyBadge() {
        hasFireflyBadge = true
        defaults.set(true, forKey: fireflyBadgeKey)
        print("🏆 Gamification: Firefly Badge Unlocked!")
        // Trigger any necessary Apple native Haptics or Telemetry here
        HapticManager.shared.triggerSelectionPulse()
    }
}

import Foundation
import Combine

/// Tracks Gamification mechanics like Streaks, Badges, and Unlocked Species to drive the Digital Terrarium state.
@MainActor
final class GamificationManager: ObservableObject {
    static let shared = GamificationManager()
    
    @Published var unlockedSpeciesCount: Int
    @Published var hasFireflyBadge: Bool
    
    @Published var showTerrariumSheet: Bool = false
    
    private let defaults = UserDefaults.standard
    private let speciesCountKey = "Merian_UnlockedSpeciesCount"
    private let fireflyBadgeKey = "Merian_HasFireflyBadge"
    
    private init() {
        self.unlockedSpeciesCount = defaults.integer(forKey: speciesCountKey)
        self.hasFireflyBadge = defaults.bool(forKey: fireflyBadgeKey)
    }
    
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

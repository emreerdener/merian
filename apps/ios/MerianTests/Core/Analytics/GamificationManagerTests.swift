import Testing
@testable import Merian
import Foundation

@MainActor
struct GamificationManagerTests {

    init() {
        // Reset UserDefaults for a clean state each run
        UserDefaults.standard.removeObject(forKey: "Merian_UnlockedSpeciesCount")
        UserDefaults.standard.removeObject(forKey: "Merian_HasFireflyBadge")
        
        // Ensure GamificationManager resets to zero for this run
        GamificationManager.shared.unlockedSpeciesCount = 0
        GamificationManager.shared.hasFireflyBadge = false
    }

    @Test func testRecordNewSpeciesDiscoveredIncrementsCount() {
        // Arrange
        let manager = GamificationManager.shared
        let initialCount = manager.unlockedSpeciesCount

        // Act
        manager.recordNewSpeciesDiscovered()

        // Assert
        #expect(manager.unlockedSpeciesCount == initialCount + 1, "The unlocked species count should increment by exactly 1")
    }

    @Test func testFireflyBadgeUnlocksAtFiveSpecies() {
        // Arrange
        let manager = GamificationManager.shared
        
        // Reset state explicitly for this test
        manager.unlockedSpeciesCount = 0
        manager.hasFireflyBadge = false

        // Act & Assert
        // First 4 discoveries should NOT unlock the badge
        for _ in 0..<4 {
            manager.recordNewSpeciesDiscovered()
            #expect(manager.hasFireflyBadge == false, "Badge should remain locked before 5 discoveries")
        }

        // 5th discovery should unlock the badge
        manager.recordNewSpeciesDiscovered()
        #expect(manager.hasFireflyBadge == true, "Badge should be unlocked upon reaching 5 discoveries")
        #expect(manager.unlockedSpeciesCount == 5, "Unlocked species count should be exactly 5")
    }
    
    @Test func testFireflyBadgeDoesNotReUnlock() {
         // Arrange
        let manager = GamificationManager.shared
        
        // Reset state explicitly for this test to exactly 5
        manager.unlockedSpeciesCount = 5
        manager.hasFireflyBadge = true
        
        // Act
        manager.recordNewSpeciesDiscovered()
        
        // Assert
        #expect(manager.hasFireflyBadge == true, "Badge should remain unlocked")
        #expect(manager.unlockedSpeciesCount == 6, "Unlocked species count should be exactly 6")
    }
}

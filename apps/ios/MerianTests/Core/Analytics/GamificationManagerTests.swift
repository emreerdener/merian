import Foundation
@testable import Merian
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.gamificationManager))
struct GamificationManagerTests {

    init() {
        GamificationManager.shared.resetAccountState()
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

    @Test func resetAccountStateClearsMemoryAndPersistedValues() {
        let manager = GamificationManager.shared
        manager.unlockedSpeciesCount = 12
        manager.hasFireflyBadge = true
        manager.unlockedAchievements = [.domesticCat]
        UserDefaults.standard.set(
            12,
            forKey: UserDefaultsKeys.unlockedSpeciesCount
        )
        UserDefaults.standard.set(
            true,
            forKey: UserDefaultsKeys.hasFireflyBadge
        )
        UserDefaults.standard.set(
            [AchievementType.domesticCat.rawValue],
            forKey: UserDefaultsKeys.unlockedAchievements
        )

        manager.resetAccountState()

        #expect(manager.unlockedSpeciesCount == 0)
        #expect(!manager.hasFireflyBadge)
        #expect(manager.unlockedAchievements.isEmpty)
        #expect(UserDefaults.standard.object(
            forKey: UserDefaultsKeys.unlockedSpeciesCount
        ) == nil)
        #expect(UserDefaults.standard.object(
            forKey: UserDefaultsKeys.hasFireflyBadge
        ) == nil)
        #expect(UserDefaults.standard.object(
            forKey: UserDefaultsKeys.unlockedAchievements
        ) == nil)
    }
}

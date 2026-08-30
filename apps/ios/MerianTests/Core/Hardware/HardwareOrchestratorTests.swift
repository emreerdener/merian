import Foundation
@testable import Merian
import Testing

@MainActor
@Suite(.serialized)
struct HardwareOrchestratorTests {
    
    init() {
        AppTelemetry.initialize()
    }

    private func makeAppSettings() -> AppSettings {
        let suiteName = "merian.tests.hardware.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        userDefaults.removePersistentDomain(forName: suiteName)
        return AppSettings(userDefaults: userDefaults, observeExternalChanges: false)
    }

    private func makeOrchestrator(
        appSettings: AppSettings? = nil,
        functionalProAccessProvider: @escaping @MainActor () -> Bool = { true }
    ) -> HardwareOrchestrator {
        HardwareOrchestrator(
            appSettings: appSettings ?? makeAppSettings(),
            observeSystemChanges: false,
            functionalProAccessProvider: functionalProAccessProvider
        )
    }

    @Test func testPersistedExpeditionModeWaitsForFunctionalEntitlement() {
        let appSettings = makeAppSettings()
        var hasFunctionalProAccess = false
        let orchestrator = makeOrchestrator(
            appSettings: appSettings,
            functionalProAccessProvider: { hasFunctionalProAccess }
        )

        appSettings.isExpeditionModeActive = true
        orchestrator.evaluateConstraints(thermalState: .nominal)
        #expect(orchestrator.isExpeditionModeActive == false)
        #expect(orchestrator.targetFPS == 60)
        #expect(orchestrator.isGlassmorphismEnabled == true)

        hasFunctionalProAccess = true
        orchestrator.evaluateConstraints(thermalState: .nominal)
        #expect(orchestrator.isExpeditionModeActive == true)
        #expect(orchestrator.targetFPS == 24)
        #expect(orchestrator.isGlassmorphismEnabled == false)
    }
    
    @Test func testExpeditionModeDisablesBackgroundSyncs() async throws {
        // Arrange
        let appSettings = makeAppSettings()
        let orchestrator = makeOrchestrator(appSettings: appSettings)
        let originalOrchestrator = OfflineQueueManager.shared.hardwareOrchestrator
        OfflineQueueManager.shared.hardwareOrchestrator = orchestrator
        appSettings.isExpeditionModeActive = false
        orchestrator.isIdleLocked = false
        defer {
            appSettings.isExpeditionModeActive = false
            OfflineQueueManager.shared.hardwareOrchestrator = originalOrchestrator
            orchestrator.isIdleLocked = false
            orchestrator.evaluateConstraints(thermalState: .nominal)
        }
        
        // Assert base execution sets Expedition mode bounds internally
        appSettings.isExpeditionModeActive = true
        orchestrator.evaluateConstraints(thermalState: .nominal)
        #expect(orchestrator.isExpeditionModeActive == true, "ExpeditionMode maps to UserDefaults")
        
        let initialUploadTries = OfflineQueueManager.shared.unsyncedItemsCount
        
        // Act: Fire Offline Sync dynamically with Expedition bounds active
        OfflineQueueManager.shared.syncPendingScans()
        
        // Assert Offline Queue skips syncing while battery bounds are aggressive
        #expect(OfflineQueueManager.shared.unsyncedItemsCount == initialUploadTries, "Pending offline queue should short-circuit and completely ignore queue execution natively when protecting hardware limits")
        
    }
    
    @Test func testThermalStateThrottlingProperlyReducesFPS() {
        let appSettings = makeAppSettings()
        let orchestrator = makeOrchestrator(appSettings: appSettings)
        
        // Arrange & base boundaries disabled
        appSettings.isExpeditionModeActive = false
        orchestrator.isIdleLocked = false
        defer {
            appSettings.isExpeditionModeActive = false
            orchestrator.isIdleLocked = false
            orchestrator.evaluateConstraints(thermalState: .nominal)
        }
        
        // 1. Act & Assert Nominal
        orchestrator.evaluateConstraints(thermalState: .nominal)
        #expect(orchestrator.targetFPS == 60)
        #expect(orchestrator.isGlassmorphismEnabled == true)
        #expect(orchestrator.isCriticalHeatWarningActive == false)
        
        // 2. Act & Assert Fair (Light Heat)
        orchestrator.evaluateConstraints(thermalState: .fair)
        #expect(orchestrator.targetFPS == 45)
        #expect(orchestrator.isGlassmorphismEnabled == true)
        
        // 3. Act & Assert Serious (Noticeable iPhone Heating)
        orchestrator.evaluateConstraints(thermalState: .serious)
        #expect(orchestrator.targetFPS == 30)
        #expect(orchestrator.isGlassmorphismEnabled == false) // Thermal bounds must automatically drop expensive UI modifiers
        
        // 4. Act & Assert Critical State (Sunlight Exposure Danger limits)
        orchestrator.evaluateConstraints(thermalState: .critical)
        #expect(orchestrator.targetFPS == 15)
        #expect(orchestrator.isGlassmorphismEnabled == false)
        #expect(orchestrator.isCriticalHeatWarningActive == true)
        
        // 5. Assert Expedition Mode completely overrides physical heat maps
        appSettings.isExpeditionModeActive = true
        orchestrator.evaluateConstraints(thermalState: .nominal)
        #expect(orchestrator.targetFPS == 24)
        #expect(orchestrator.isGlassmorphismEnabled == false)
    }
    
    @Test func testIdleLockPreventsThermalOverride() {
        let orchestrator = makeOrchestrator()
        
        // Set standard
        orchestrator.evaluateConstraints(thermalState: .nominal)
        #expect(orchestrator.targetFPS == 60)
        
        // Lock constraints at runtime to freeze AI inference frame arrays
        orchestrator.targetFPS = 1
        orchestrator.isIdleLocked = true
        
        // Attempt to manipulate boundary via Thermal notifications
        orchestrator.evaluateConstraints(thermalState: .nominal)
        
        #expect(orchestrator.targetFPS == 1, "Idle lock MUST physically block any heat/power checks natively until unlock bounds are fired.")
        
        // Unlock dynamically forces immediate re-evaluation natively ensuring fluid transition bounds
        orchestrator.isIdleLocked = false
        #expect(orchestrator.targetFPS == 60, "Unlocking isIdleLocked must implicitly call evaluateConstraints()")
    }
    
    @Test func testExpeditionModeOverridesSettings() {
        let appSettings = makeAppSettings()
        let orchestrator = makeOrchestrator(appSettings: appSettings)
        defer {
            appSettings.isExpeditionModeActive = false
            orchestrator.isIdleLocked = false
            orchestrator.evaluateConstraints(thermalState: .nominal)
        }
        
        // Assert nominal map
        appSettings.isExpeditionModeActive = false
        orchestrator.evaluateConstraints(thermalState: .nominal)
        #expect(orchestrator.targetFPS == 60)
        
        // Simulate User toggling "Expedition Mode" in SettingsView
        appSettings.isExpeditionModeActive = true
        orchestrator.evaluateConstraints(thermalState: .nominal)
        
        #expect(orchestrator.targetFPS == 24)
        #expect(orchestrator.isGlassmorphismEnabled == false)
    }
}

import Testing
import Foundation
import TelemetryClient
@testable import Merian

@MainActor
@Suite(.serialized)
struct HardwareOrchestratorTests {
    
    init() {
        AppTelemetry.initialize()
    }
    
    @Test func testExpeditionModeDisablesBackgroundSyncs() async throws {
        // Arrange
        let orchestrator = HardwareOrchestrator.shared
        AppSettings.shared.isExpeditionModeActive = false
        orchestrator.isIdleLocked = false
        defer {
            AppSettings.shared.isExpeditionModeActive = false
            orchestrator.isIdleLocked = false
            orchestrator.evaluateConstraints(thermalState: .nominal)
        }
        
        // Assert base execution sets Expedition mode bounds internally
        AppSettings.shared.isExpeditionModeActive = true
        orchestrator.evaluateConstraints(thermalState: .nominal)
        #expect(orchestrator.isExpeditionModeActive == true, "ExpeditionMode maps to UserDefaults")
        
        let initialUploadTries = OfflineQueueManager.shared.unsyncedItemsCount
        
        // Act: Fire Offline Sync dynamically with Expedition bounds active
        OfflineQueueManager.shared.syncPendingScans()
        
        // Assert Offline Queue skips syncing while battery bounds are aggressive
        #expect(OfflineQueueManager.shared.unsyncedItemsCount == initialUploadTries, "Pending offline queue should short-circuit and completely ignore queue execution natively when protecting hardware limits")
        
    }
    
    @Test func testThermalStateThrottlingProperlyReducesFPS() {
        let orchestrator = HardwareOrchestrator.shared
        
        // Arrange & base boundaries disabled
        AppSettings.shared.isExpeditionModeActive = false
        orchestrator.isIdleLocked = false
        defer {
            AppSettings.shared.isExpeditionModeActive = false
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
        AppSettings.shared.isExpeditionModeActive = true
        orchestrator.evaluateConstraints(thermalState: .nominal)
        #expect(orchestrator.targetFPS == 24)
        #expect(orchestrator.isGlassmorphismEnabled == false)
    }
    
    @Test func testIdleLockPreventsThermalOverride() {
        let orchestrator = HardwareOrchestrator.shared
        
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
        let orchestrator = HardwareOrchestrator.shared
        defer {
            AppSettings.shared.isExpeditionModeActive = false
            orchestrator.isIdleLocked = false
            orchestrator.evaluateConstraints(thermalState: .nominal)
        }
        
        // Assert nominal map
        AppSettings.shared.isExpeditionModeActive = false
        orchestrator.evaluateConstraints(thermalState: .nominal)
        #expect(orchestrator.targetFPS == 60)
        
        // Simulate User toggling "Expedition Mode" in SettingsView
        AppSettings.shared.isExpeditionModeActive = true
        orchestrator.evaluateConstraints(thermalState: .nominal)
        
        #expect(orchestrator.targetFPS == 24)
        #expect(orchestrator.isGlassmorphismEnabled == false)
    }
}

@MainActor
struct AudioCaptureManagerLifecycleTests {
    @Test func testCancelledStartupCleansPendingRecordingResources() async throws {
        let manager = AudioCaptureManager()
        let fileName = "\(UUID().uuidString).wav"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try Data("pending-audio".utf8).write(to: fileURL)

        manager.debugStageStartupState(
            fileName: fileName,
            dspTask: Task {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        )

        manager.debugHandleCancelledStartup()
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false, "Cancelled recording startup must remove the pending temp file")
        #expect(manager.debugHasDSPTask == false, "Cancelled recording startup must cancel and clear the DSP task")
        #expect(manager.debugPendingFileName == nil, "Cancelled recording startup must clear pending file bookkeeping")
    }
}

@MainActor
struct SpeechManagerLifecycleTests {
    @Test func testCancelledStartupResetsDictationState() {
        let manager = SpeechManager()
        manager.audioLevel = 0.75
        manager.isRecording = true

        manager.debugHandleStartupCancellation()

        #expect(manager.audioLevel == 0.0, "Cancelled dictation startup must reset the live level meter")
        #expect(manager.isRecording == false, "Cancelled dictation startup must leave recording disabled")
    }
}

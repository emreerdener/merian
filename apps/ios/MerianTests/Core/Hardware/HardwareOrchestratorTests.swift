import Testing
import AVFoundation
import Foundation
@testable import Merian

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

    private func makeOrchestrator(appSettings: AppSettings? = nil) -> HardwareOrchestrator {
        HardwareOrchestrator(
            appSettings: appSettings ?? makeAppSettings(),
            observeSystemChanges: false
        )
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

@MainActor
struct AudioCaptureManagerLifecycleTests {
    @Test func testFreshInstallCleanupDoesNotInitializeMicrophoneInput() {
        let manager = AudioCaptureManager()

        #expect(manager.debugHasAudioEngine == false)
        manager.reset()
        #expect(
            manager.debugHasAudioEngine == false,
            "Lifecycle cleanup before the first recording must not initialize AVAudioEngine input"
        )
    }

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

    @Test func testMaxDurationRecordingAutoSubmitsWhenEnabled() {
        let manager = AudioCaptureManager()
        let fileName = "\(UUID().uuidString).wav"

        manager.debugStageRecordingForFinish(fileName: fileName, autoSubmitOnMaxDuration: true)
        manager.debugFinishRecording(reachedMaxDuration: true)

        #expect(manager.audioFilePath == fileName, "Max-duration audio should move directly to submission when auto-submit is enabled")
        #expect(manager.pendingPlaybackPath == nil, "Auto-submitted audio should not pause in review")
        #expect(manager.isRecording == false)
    }

    @Test func testMaxDurationRecordingStaysInReviewWhenAutoSubmitDisabled() {
        let manager = AudioCaptureManager()
        let fileName = "\(UUID().uuidString).wav"

        manager.debugStageRecordingForFinish(fileName: fileName, autoSubmitOnMaxDuration: false)
        manager.debugFinishRecording(reachedMaxDuration: true)

        #expect(manager.audioFilePath == nil, "Confirmation-enabled audio should not submit automatically")
        #expect(manager.pendingPlaybackPath == fileName)
        #expect(manager.isRecording == false)
    }

    @Test func testEarlyStoppedRecordingStaysInReviewEvenWhenAutoSubmitEnabled() {
        let manager = AudioCaptureManager()
        let fileName = "\(UUID().uuidString).wav"

        manager.debugStageRecordingForFinish(fileName: fileName, autoSubmitOnMaxDuration: true)
        manager.debugFinishRecording(reachedMaxDuration: false)

        #expect(manager.audioFilePath == nil, "Manual early stops should still let the user review the shorter clip")
        #expect(manager.pendingPlaybackPath == fileName)
        #expect(manager.isRecording == false)
    }
}

struct SpectrogramActorTests {
    @Test func testProcessColumnsUsesEveryFFTWindowInBuffer() async throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(SpectrogramActor.fftSize * 2)
        ))
        buffer.frameLength = AVAudioFrameCount(SpectrogramActor.fftSize * 2)

        let channel = try #require(buffer.floatChannelData?[0])
        for sampleIndex in 0..<(SpectrogramActor.fftSize * 2) {
            let phase = 2 * Float.pi * 1_200 * Float(sampleIndex) / 48_000
            channel[sampleIndex] = sinf(phase) * 0.5
        }

        let actor = SpectrogramActor()
        let columns = await actor.processColumns(buffer: buffer)

        #expect(columns.count == 2, "A 4096-frame tap buffer should produce two 2048-frame spectrogram windows")
        #expect(SpectrogramActor.outputBinCount == 128)
        #expect(columns.allSatisfy { $0.magnitudes.count == SpectrogramActor.outputBinCount })
        #expect(columns.contains { ($0.magnitudes.max() ?? 0) > 0 })
    }
}

struct SpectrogramRendererTests {
    @Test func testRasterLayoutsUseFitAndLiveDimensions() throws {
        let columns = (0..<3).map { columnIndex in
            SpectrogramColumn(
                magnitudes: (0..<SpectrogramActor.outputBinCount).map { binIndex in
                    Float(columnIndex + binIndex + 1) / Float(SpectrogramActor.outputBinCount + 3)
                },
                rms: 0.1,
                peak: 0.2
            )
        }

        let fitRaster = try #require(SpectrogramRenderer.raster(columns: columns, layout: .fitToData))
        #expect(fitRaster.width == columns.count)
        #expect(fitRaster.height == SpectrogramActor.outputBinCount)

        let liveRaster = try #require(SpectrogramRenderer.raster(
            columns: columns,
            layout: .liveHorizon(capacity: 10)
        ))
        #expect(liveRaster.width == 10)
        #expect(liveRaster.height == SpectrogramActor.outputBinCount)

        let background = SpectrogramPalette.backgroundRGBA
        let hasSignalPixel = stride(from: 0, to: liveRaster.pixels.count, by: 4).contains { offset in
            liveRaster.pixels[offset] != background.red ||
            liveRaster.pixels[offset + 1] != background.green ||
            liveRaster.pixels[offset + 2] != background.blue
        }
        #expect(hasSignalPixel, "Rendered raster should include signal-colored pixels, not only the background")

        let image = try #require(SpectrogramRenderer.cgImage(columns: columns, layout: .liveHorizon(capacity: 10)))
        #expect(image.width == 10)
        #expect(image.height == SpectrogramActor.outputBinCount)
    }
}

@MainActor
struct SpeechManagerLifecycleTests {
    @Test func testStoppingBeforeFirstDictationDoesNotInitializeMicrophoneInput() {
        let manager = SpeechManager()

        #expect(manager.debugHasAudioEngine == false)
        manager.stopDictation()
        #expect(
            manager.debugHasAudioEngine == false,
            "Dictation cleanup before the first user action must not initialize AVAudioEngine input"
        )
    }

    @Test func testCancelledStartupResetsDictationState() {
        let manager = SpeechManager()
        manager.audioLevel = 0.75
        manager.isRecording = true

        manager.debugHandleStartupCancellation()

        #expect(manager.audioLevel == 0.0, "Cancelled dictation startup must reset the live level meter")
        #expect(manager.isRecording == false, "Cancelled dictation startup must leave recording disabled")
    }
}

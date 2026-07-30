import AVFoundation
@testable import Merian
import XCTest

private actor CameraTargetFPSControlledSleeper {
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func sleep() async {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func pendingCount() -> Int {
        continuations.count
    }

    func resumeOldest() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}

@MainActor
private final class CameraTargetFPSTestState {
    var currentFPS = 60
    var appliedFPS: [Int] = []
}

@MainActor
final class CameraManagerTests: XCTestCase {

    var cameraManager: CameraManager!

    override func setUp() async throws {
        cameraManager = CameraManager.shared
        // Clean state
        cameraManager.stopSession()
        cameraManager.isLiveInferencePaused = false
        HardwareOrchestrator.shared.isIdleLocked = false
    }

    override func tearDown() async throws {
        cameraManager.stopSession()
        cameraManager = nil
    }

    func testInitialState() {
        XCTAssertFalse(cameraManager.isSessionRunning)
        XCTAssertNil(cameraManager.subjectDistanceInMeters)
        XCTAssertFalse(cameraManager.isFlashEnabled)
        XCTAssertFalse(cameraManager.isLiveInferencePaused)
        XCTAssertEqual(cameraManager.zoomFactor, 1.0)
        XCTAssertEqual(cameraManager.maxZoomFactor, 1.0)
        XCTAssertFalse(cameraManager.isZoomSupported)
    }

    func testVideoAudioOnlyUsesPreviouslyGrantedMicrophoneAccess() {
        XCTAssertFalse(
            CameraVideoAudioPermissionPolicy.shouldIncludeAudio(for: .undetermined),
            "Video capture must not trigger the first microphone permission request"
        )
        XCTAssertFalse(
            CameraVideoAudioPermissionPolicy.shouldIncludeAudio(for: .denied)
        )
        XCTAssertTrue(
            CameraVideoAudioPermissionPolicy.shouldIncludeAudio(for: .granted)
        )
    }

    // MARK: - Target FPS Debounce

    func testTargetFPSDebouncerReadsCurrentTargetAfterDelay() async {
        let sleeper = CameraTargetFPSControlledSleeper()
        let state = CameraTargetFPSTestState()
        let debouncer = CameraTargetFPSDebouncer(
            sleep: { _ in await sleeper.sleep() }
        )

        let applicationTask = debouncer.schedule(
            currentTargetFPS: { state.currentFPS },
            apply: { state.appliedFPS.append($0) }
        )
        await waitForPendingSleepCount(1, in: sleeper)

        state.currentFPS = 15
        await sleeper.resumeOldest()
        await applicationTask.value

        XCTAssertEqual(
            state.appliedFPS,
            [15],
            "The FPS value must be read after the debounce window, not captured when scheduling"
        )
    }

    func testTargetFPSDebouncerRejectsReplacedGeneration() async {
        let sleeper = CameraTargetFPSControlledSleeper()
        let state = CameraTargetFPSTestState()
        let debouncer = CameraTargetFPSDebouncer(
            sleep: { _ in await sleeper.sleep() }
        )

        let replacedTask = debouncer.schedule(
            currentTargetFPS: { state.currentFPS },
            apply: { state.appliedFPS.append($0) }
        )
        await waitForPendingSleepCount(1, in: sleeper)

        state.currentFPS = 30
        let replacementTask = debouncer.schedule(
            currentTargetFPS: { state.currentFPS },
            apply: { state.appliedFPS.append($0) }
        )
        await waitForPendingSleepCount(2, in: sleeper)

        // The injected sleeper intentionally ignores cooperative cancellation.
        // Resuming the replaced task must still fail its generation check.
        await sleeper.resumeOldest()
        await replacedTask.value
        XCTAssertTrue(state.appliedFPS.isEmpty)

        state.currentFPS = 15
        await sleeper.resumeOldest()
        await replacementTask.value

        XCTAssertEqual(
            state.appliedFPS,
            [15],
            "Only the latest generation may read and apply the current target"
        )
    }

    private func waitForPendingSleepCount(
        _ expectedCount: Int,
        in sleeper: CameraTargetFPSControlledSleeper,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<1_000 {
            if await sleeper.pendingCount() >= expectedCount {
                return
            }
            await Task.yield()
        }

        XCTFail(
            "Timed out waiting for \(expectedCount) pending FPS debounce sleep(s)",
            file: file,
            line: line
        )
    }

    // MARK: - Video Recording Generations

    func testVideoRecordingGenerationBindsCallbacksToExpectedURL() {
        let generation = CameraVideoRecordingGeneration(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            outputURL: URL(fileURLWithPath: "/tmp/recording-a.mp4")
        )

        XCTAssertTrue(
            generation.matches(
                callbackURL: URL(fileURLWithPath: "/tmp/./recording-a.mp4")
            )
        )
        XCTAssertFalse(
            generation.matches(
                callbackURL: URL(fileURLWithPath: "/tmp/recording-b.mp4")
            ),
            "A delayed AVFoundation callback must not match the next recording's URL"
        )
    }

    func testVideoRecordingGenerationRejectsABAActions() {
        let generationA = CameraVideoRecordingGeneration(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            outputURL: URL(fileURLWithPath: "/tmp/recording-a.mp4")
        )
        let generationB = CameraVideoRecordingGeneration(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            outputURL: URL(fileURLWithPath: "/tmp/recording-b.mp4")
        )
        let staleTimeout = CameraVideoRecordingScheduledAction(
            generation: generationA,
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        )
        let staleStop = CameraVideoRecordingScheduledAction(
            generation: generationA,
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        )
        var activeBGate = CameraVideoRecordingGenerationGate(generation: generationB)

        XCTAssertFalse(activeBGate.matches(generationA))
        XCTAssertFalse(activeBGate.matches(callbackURL: generationA.outputURL))
        XCTAssertFalse(activeBGate.installTimeoutAction(staleTimeout))
        XCTAssertFalse(activeBGate.installStopAction(staleStop))
        XCTAssertFalse(activeBGate.acceptsTimeoutAction(staleTimeout))
        XCTAssertFalse(activeBGate.acceptsStopAction(staleStop))
        XCTAssertEqual(activeBGate.generation, generationB)
    }

    func testVideoRecordingGenerationRejectsCooperativelyCancelledReplacedTasks() {
        let generation = CameraVideoRecordingGeneration(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            outputURL: URL(fileURLWithPath: "/tmp/recording-a.mp4")
        )
        let firstTimeout = CameraVideoRecordingScheduledAction(
            generation: generation,
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        )
        let replacementTimeout = CameraVideoRecordingScheduledAction(
            generation: generation,
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        )
        let firstStop = CameraVideoRecordingScheduledAction(
            generation: generation,
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        )
        let replacementStop = CameraVideoRecordingScheduledAction(
            generation: generation,
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        )
        var gate = CameraVideoRecordingGenerationGate(generation: generation)

        XCTAssertTrue(gate.installTimeoutAction(firstTimeout))
        XCTAssertTrue(gate.acceptsTimeoutAction(firstTimeout))
        XCTAssertTrue(gate.installTimeoutAction(replacementTimeout))
        XCTAssertFalse(
            gate.acceptsTimeoutAction(firstTimeout),
            "Cancellation is cooperative, so the replaced timeout needs an independent action token"
        )
        XCTAssertTrue(gate.acceptsTimeoutAction(replacementTimeout))

        XCTAssertTrue(gate.installStopAction(firstStop))
        XCTAssertTrue(gate.acceptsStopAction(firstStop))
        XCTAssertTrue(gate.installStopAction(replacementStop))
        XCTAssertFalse(gate.acceptsStopAction(firstStop))
        XCTAssertTrue(gate.acceptsStopAction(replacementStop))
        gate.clearStopAction()
        XCTAssertFalse(gate.acceptsStopAction(replacementStop))
    }

    func testStopSessionAndWaitPublishesStoppedStateBeforeReturning() async {
        await cameraManager.stopSessionAndWait()

        XCTAssertFalse(cameraManager.isSessionRunning)
        XCTAssertFalse(cameraManager.isFlashEnabled)
    }

    // MARK: - Zoom

    func testSetZoomClampsAtMinimum() {
        // Any value below 1.0 must clamp to 1.0 — negative zoom is not physically meaningful.
        cameraManager.setZoom(factor: -5.0)
        XCTAssertEqual(cameraManager.zoomFactor, 1.0)
    }

    func testSetZoomClampsAtMaximum() {
        // Without a camera session, maxZoomFactor is 1.0. Values above it must clamp down.
        cameraManager.setZoom(factor: 100.0)
        XCTAssertLessThanOrEqual(cameraManager.zoomFactor, cameraManager.maxZoomFactor)
    }

    func testSetZoomDoesNotProduceNegativeValue() {
        cameraManager.setZoom(factor: -999.0)
        XCTAssertGreaterThanOrEqual(cameraManager.zoomFactor, 1.0)
    }

    func testIsZoomSupportedRequiresMinimumRange() {
        // maxZoomFactor is 1.0 without a running session — hardware support must not be reported.
        XCTAssertFalse(cameraManager.isZoomSupported)
    }

    func testThrottleToIdleState() {
        cameraManager.throttleToIdleState()
        
        XCTAssertTrue(HardwareOrchestrator.shared.isIdleLocked)
        XCTAssertTrue(cameraManager.isLiveInferencePaused)
    }

    func testRestoreFromIdleState() {
        // First throttle
        cameraManager.throttleToIdleState()
        XCTAssertTrue(HardwareOrchestrator.shared.isIdleLocked)
        XCTAssertTrue(cameraManager.isLiveInferencePaused)
        
        // Then restore
        cameraManager.restoreFromIdleState()
        XCTAssertFalse(HardwareOrchestrator.shared.isIdleLocked)
        XCTAssertFalse(cameraManager.isLiveInferencePaused)
    }
    
    func testLegacyViewfinderToggle() {
        // Assert base
        XCTAssertFalse(cameraManager.isLiveInferencePaused)
        
        // Assert toggle
        cameraManager.isLiveInferencePaused = true
        XCTAssertTrue(cameraManager.isLiveInferencePaused)
        
        // Ensure returning bounds to false works
        cameraManager.isLiveInferencePaused = false
        XCTAssertFalse(cameraManager.isLiveInferencePaused)
    }
}

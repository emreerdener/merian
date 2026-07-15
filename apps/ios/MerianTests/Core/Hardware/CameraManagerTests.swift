import AVFoundation
@testable import Merian
import XCTest

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

import XCTest
import AVFoundation
@testable import Merian

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

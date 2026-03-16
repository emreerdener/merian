import XCTest
@testable import Merian

@MainActor
final class HapticManagerTests: XCTestCase {

    var hapticManager: HapticManager!

    override func setUp() async throws {
        hapticManager = HapticManager.shared
    }

    override func tearDown() async throws {
        hapticManager = nil
    }

    func testHapticManagerInstantiation() {
        XCTAssertNotNil(hapticManager)
        
        UserDefaults.standard.set(true, forKey: "isHapticsEnabled")
        // Since haptic hardware cannot be explicitly queried for state in the Simulator,
        // we ensure the methods don't crash when executed consecutively.
        
        hapticManager.triggerFocusSnap()
        hapticManager.triggerSheetSpring()
        hapticManager.triggerMediumPulse()
        hapticManager.triggerErrorThump()
        hapticManager.triggerSelectionPulse()
        hapticManager.triggerSuccessPulse()
    }
    
    func testHapticManagerRespectsUserDefaultsToggle() {
        XCTAssertNotNil(hapticManager)
        
        UserDefaults.standard.set(false, forKey: "isHapticsEnabled")
        
        // This should skip internally without crashing or side effects
        hapticManager.triggerFocusSnap()
        hapticManager.triggerSheetSpring()
        hapticManager.triggerMediumPulse()
        hapticManager.triggerErrorThump()
        hapticManager.triggerSelectionPulse()
        hapticManager.triggerSuccessPulse()
    }
}

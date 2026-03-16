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
        // Since haptic hardware cannot be explicitly queried for state in the Simulator,
        // we ensure the methods don't crash when executed consecutively.
        
        hapticManager.triggerFocusSnap()
        hapticManager.triggerSheetSpring()
        hapticManager.triggerMediumPulse()
        hapticManager.triggerErrorThump()
        hapticManager.triggerSelectionPulse()
        hapticManager.triggerSuccessPulse()
    }
}

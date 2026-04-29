import XCTest
@testable import Merian

@MainActor
final class UsageManagerTests: XCTestCase {

    override func setUp() async throws {
        // Clear underlying UserDefaults for a fresh test environment
        let deviceId = DeviceIdentityManager.shared.deviceId
        UserDefaults.standard.removeObject(forKey: "Merian_LastScanDate_\(deviceId)")
        UserDefaults.standard.removeObject(forKey: "Merian_ScansUsedToday_\(deviceId)")
    }

    override func tearDown() async throws {
        let deviceId = DeviceIdentityManager.shared.deviceId
        UserDefaults.standard.removeObject(forKey: "Merian_LastScanDate_\(deviceId)")
        UserDefaults.standard.removeObject(forKey: "Merian_ScansUsedToday_\(deviceId)")
    }

    func testFreeScansStartsAtMaxAndConsumedProperly() {
        let usageManager = UsageManager.shared
        
        // Reset state
        usageManager.evaluateDailyRefresh()
        
        XCTAssertEqual(usageManager.freeScansRemaining, 2)
        // Consume one
        usageManager.consumeScan()
        XCTAssertEqual(usageManager.freeScansRemaining, 1)
        
        // Refund one
        usageManager.refundScan()
        XCTAssertEqual(usageManager.freeScansRemaining, 2)
    }

    func testCanPerformScanRespectsDailyQuotaForFreeTier() {
        let usageManager = UsageManager.shared

        usageManager.evaluateDailyRefresh()
        XCTAssertTrue(usageManager.canPerformScan(isProActive: false))

        usageManager.consumeScan()
        usageManager.consumeScan()

        XCTAssertEqual(usageManager.freeScansRemaining, 0)
        XCTAssertFalse(usageManager.canPerformScan(isProActive: false))
        XCTAssertTrue(usageManager.canPerformScan(isProActive: true))
    }
}

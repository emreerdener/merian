@testable import Merian
import XCTest

@MainActor
final class UsageManagerTests: XCTestCase {

    override func setUp() async throws {
        // Clear underlying UserDefaults for a fresh test environment
        let deviceId = DeviceIdentityManager.shared.deviceId
        UserDefaults.standard.removeObject(forKey: "Merian_LastScanDate_\(deviceId)")
        UserDefaults.standard.removeObject(forKey: "Merian_ScansUsedToday_\(deviceId)")
        UserDefaults.standard.removeObject(forKey: "Merian_MeteredScanDates_\(deviceId)")
        FeatureFlags.setDebugOverride(false, for: .unlimitedFreeScans)
        UsageManager.debugFreeScanLimitOverride = nil
        UsageManager.shared.evaluateDailyRefresh()
    }

    override func tearDown() async throws {
        let deviceId = DeviceIdentityManager.shared.deviceId
        UserDefaults.standard.removeObject(forKey: "Merian_LastScanDate_\(deviceId)")
        UserDefaults.standard.removeObject(forKey: "Merian_ScansUsedToday_\(deviceId)")
        UserDefaults.standard.removeObject(forKey: "Merian_MeteredScanDates_\(deviceId)")
        FeatureFlags.setDebugOverride(nil, for: .unlimitedFreeScans)
        UsageManager.debugFreeScanLimitOverride = nil
        UsageManager.shared.evaluateDailyRefresh()
    }

    func testFreeScansStartsAtMaxAndConsumedProperly() {
        let usageManager = UsageManager.shared
        
        // Reset state
        usageManager.evaluateDailyRefresh()
        
        XCTAssertEqual(usageManager.freeScansRemaining, 1)
        // Consume one
        usageManager.consumeScan()
        XCTAssertEqual(usageManager.freeScansRemaining, 0)
        
        // Refund one
        usageManager.refundScan()
        XCTAssertEqual(usageManager.freeScansRemaining, 1)
    }

    func testCanPerformScanRespectsDailyQuotaForFreeTier() {
        let usageManager = UsageManager.shared

        usageManager.evaluateDailyRefresh()
        XCTAssertTrue(usageManager.canPerformScan(isProActive: false))

        usageManager.consumeScan()

        XCTAssertEqual(usageManager.freeScansRemaining, 0)
        XCTAssertFalse(usageManager.canPerformScan(isProActive: false))
        XCTAssertTrue(usageManager.canPerformScan(isProActive: true))
    }

    func testDebugOverrideDisablesFreeScanLimitWithoutConsumingQuota() {
        let usageManager = UsageManager.shared
        UsageManager.debugFreeScanLimitOverride = true

        usageManager.evaluateDailyRefresh()
        XCTAssertTrue(usageManager.canPerformScan(isProActive: false))
        XCTAssertEqual(usageManager.freeScansRemaining, usageManager.maxFreeScansPerDay)

        usageManager.consumeScan()
        usageManager.consumeScan()

        XCTAssertTrue(usageManager.canPerformScan(isProActive: false))
        XCTAssertEqual(usageManager.freeScansRemaining, usageManager.maxFreeScansPerDay)
    }

    func testFeatureFlagDisablesFreeScanLimitWithoutConsumingQuota() {
        let usageManager = UsageManager.shared
        FeatureFlags.setDebugOverride(true, for: .unlimitedFreeScans)

        usageManager.evaluateDailyRefresh()
        XCTAssertTrue(usageManager.canPerformScan(isProActive: false))
        XCTAssertEqual(usageManager.freeScansRemaining, usageManager.maxFreeScansPerDay)

        usageManager.consumeScan()
        usageManager.consumeScan()

        XCTAssertTrue(usageManager.canPerformScan(isProActive: false))
        XCTAssertEqual(usageManager.freeScansRemaining, usageManager.maxFreeScansPerDay)
    }

    func testServerComplimentaryPlanRefundsOnlyItsOptimisticFlashMeter() {
        let usageManager = UsageManager.shared
        usageManager.consumeScan(scanId: "scan-a")
        XCTAssertEqual(usageManager.freeScansRemaining, 0)

        usageManager.reconcileServerPlanUsed("pro_complimentary", scanId: "scan-a")
        XCTAssertEqual(usageManager.freeScansRemaining, 1)

        usageManager.reconcileServerPlanUsed("pro_complimentary", scanId: "unmetered")
        XCTAssertEqual(usageManager.freeScansRemaining, 1)
    }

    func testServerFlashFallbackConsumesAtMostOnce() {
        let usageManager = UsageManager.shared
        usageManager.reconcileServerPlanUsed("free", scanId: "scan-fallback")
        usageManager.reconcileServerPlanUsed("free", scanId: "scan-fallback")
        XCTAssertEqual(usageManager.freeScansRemaining, 0)
    }
}

import XCTest
@testable import Merian

final class AppTelemetryTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Must initialize before track calls so the isInitialized guard passes.
        // Without this every track method silently no-ops and the test covers nothing.
        AppTelemetry.initialize()
    }

    func testAllTrackMethodsDoNotCrash() {
        AppTelemetry.trackScan(isPro: true)
        AppTelemetry.trackScan(isPro: false)
        AppTelemetry.trackNewDiscovery(isPro: true)
        AppTelemetry.trackNewDiscovery(isPro: false)
        AppTelemetry.trackPaywallImpression()
        AppTelemetry.trackThermalThrottling(fpsLimit: 15)
        AppTelemetry.trackError("UnitTestTrigger")
        AppTelemetry.trackOfflineQueued()
        AppTelemetry.trackOnboardingCompleted()
        AppTelemetry.trackExploreNotificationsFetchFailed(context: "sheet_load")
        AppTelemetry.trackAchievementDetailOpened(type: "fungi", state: "in_progress")
        AppTelemetry.trackAchievementContributionOpened(type: "fungi")
        AppTelemetry.trackExploreNotificationOpenFailed(type: "comment")
    }

    func testIsInitializedAfterSetUp() {
        XCTAssertTrue(AppTelemetry.isInitialized, "setUp() must call initialize() so track methods are not silently no-oped")
    }
}

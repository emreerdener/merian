@testable import Merian
import XCTest

final class AppTelemetryTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Must initialize before track calls so the isInitialized guard passes.
        // Without this every track method silently no-ops and the test covers nothing.
        AppTelemetry.initialize()
    }

    func testAllTrackMethodsDoNotCrash() {
        AppTelemetry.trackScan(isPro: true, isSubscribed: true, inferenceTier: "pro")
        AppTelemetry.trackScan(isPro: true, isSubscribed: false, inferenceTier: "pro")
        AppTelemetry.trackScan(isPro: false, isSubscribed: false, inferenceTier: "flash")
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
        AppTelemetry.trackSpeciesDictionaryOpened(entryPoint: "insight_similar_species")
        AppTelemetry.trackSpeciesDictionaryLoaded(entryPoint: "insight_similar_species", contentQuality: "sparse")
        AppTelemetry.trackSpeciesDictionaryNotFound(entryPoint: "explore_detail_similar_species")
        AppTelemetry.trackSpeciesDictionaryRetry(entryPoint: "explore_detail_similar_species")
        AppTelemetry.trackSpeciesDictionaryImageFallback(entryPoint: "insight_similar_species", source: "gbif")
        AppTelemetry.trackStartupStoreRecovery(outcome: "safe_mode", reason: "unit_test")
    }

    func testIsInitializedAfterSetUp() {
        XCTAssertTrue(AppTelemetry.isInitialized, "setUp() must call initialize() so track methods are not silently no-oped")
    }

    func testScanTelemetryParametersDistinguishPaidTrialAndFree() {
        XCTAssertEqual(
            AppTelemetry.scanTelemetryParameters(isPro: true, isSubscribed: true, inferenceTier: "pro"),
            ["tier": "Pro", "plan": "pro_paid", "inferenceTier": "pro"]
        )
        XCTAssertEqual(
            AppTelemetry.scanTelemetryParameters(isPro: true, isSubscribed: false, inferenceTier: "pro"),
            ["tier": "Pro", "plan": "pro_trial", "inferenceTier": "pro"]
        )
        XCTAssertEqual(
            AppTelemetry.scanTelemetryParameters(isPro: true, isSubscribed: true, inferenceTier: "flash"),
            ["tier": "Free", "plan": "free", "inferenceTier": "flash"]
        )
    }
}

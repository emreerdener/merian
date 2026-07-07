@testable import Merian
import XCTest

final class AppTelemetryTests: XCTestCase {
    private struct CapturedEvent {
        let name: String
        let properties: [String: Any]
    }

    private var capturedEvents: [CapturedEvent] = []

    override func setUp() {
        super.setUp()
        capturedEvents = []
        AppTelemetry.installCaptureHandlerForTesting { [weak self] event, properties in
            self?.capturedEvents.append(CapturedEvent(name: event, properties: properties))
        }
        // Must initialize before track calls so the isInitialized guard passes.
        // Without this every track method silently no-ops and the test covers nothing.
        AppTelemetry.initialize()
    }

    override func tearDown() {
        AppTelemetry.installCaptureHandlerForTesting(nil)
        super.tearDown()
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

        XCTAssertEqual(capturedEvents.map(\.name), [
            "ClientScanCompleted",
            "ClientScanCompleted",
            "ClientScanCompleted",
            "NewSpeciesDiscovered",
            "NewSpeciesDiscovered",
            "PaywallViewed",
            "CaptureThermalThrottled",
            "ClientErrorCaptured",
            "ScanQueuedForSync",
            "OnboardingCompleted",
            "ExploreNotificationsFetchFailed",
            "AchievementDetailOpened",
            "AchievementContributionOpened",
            "ExploreNotificationOpenFailed",
            "SpeciesDictionaryOpened",
            "SpeciesDictionaryPageLoaded",
            "SpeciesDictionaryNotFound",
            "SpeciesDictionaryRetry",
            "SpeciesDictionaryReferenceImageFallback",
            "StartupStoreRecovery"
        ])
        XCTAssertTrue(capturedEvents.allSatisfy { $0.properties["event_source"] as? String == "ios_client" })
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

    func testScanCapturedEventIncludesPlanTierAndClientSource() {
        AppTelemetry.trackScan(isPro: true, isSubscribed: false, inferenceTier: "pro")

        let event = capturedEvents.first
        XCTAssertEqual(event?.name, "ClientScanCompleted")
        XCTAssertEqual(event?.properties["tier"] as? String, "Pro")
        XCTAssertEqual(event?.properties["plan"] as? String, "pro_trial")
        XCTAssertEqual(event?.properties["inferenceTier"] as? String, "pro")
        XCTAssertEqual(event?.properties["event_source"] as? String, "ios_client")
    }
}

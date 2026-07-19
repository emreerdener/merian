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
        AppTelemetry.trackExternalImageImport(outcome: "staged")
        AppTelemetry.trackCaptureGoalIndicator(action: .shown, source: .fieldTrip)
        AppTelemetry.trackCaptureGoalIndicator(action: .opened, source: .fieldTrip)
        AppTelemetry.trackCaptureGoalIndicator(action: .next, source: .fieldTrip)
        AppTelemetry.trackCaptureGoalIndicator(action: .previous, source: .fieldTrip)
        AppTelemetry.trackCaptureGoalIndicator(action: .zeroStateShown, source: .fieldTrip)
        AppTelemetry.trackCaptureGoalIndicator(action: .zeroStateOpened, source: .fieldTrip)
        AppTelemetry.trackOnboardingCompleted()
        AppTelemetry.trackExploreNotificationsFetchFailed(context: "sheet_load")
        AppTelemetry.trackAchievementDetailOpened(type: "fungi", state: "in_progress")
        AppTelemetry.trackAchievementContributionOpened(type: "fungi")
        AppTelemetry.trackExploreNotificationOpenFailed(type: "comment")
        AppTelemetry.trackExploreAudioPlaybackStarted(surface: "feed")
        AppTelemetry.trackExploreAudioPlaybackCompleted(surface: "detail")
        AppTelemetry.trackExploreAudioPlaybackFailed(surface: "detail")
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
            "ExternalImageImport",
            "CaptureGoalIndicator",
            "CaptureGoalIndicator",
            "CaptureGoalIndicator",
            "CaptureGoalIndicator",
            "CaptureGoalIndicator",
            "CaptureGoalIndicator",
            "OnboardingCompleted",
            "ExploreNotificationsFetchFailed",
            "AchievementDetailOpened",
            "AchievementContributionOpened",
            "ExploreNotificationOpenFailed",
            "ExploreAudioPlaybackStarted",
            "ExploreAudioPlaybackCompleted",
            "ExploreAudioPlaybackFailed",
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

    func testStartupStoreRecoveryIncludesDiagnosticProperties() {
        AppTelemetry.trackStartupStoreRecovery(
            outcome: "safe_mode",
            reason: "unit_test",
            properties: [
                "selected_strategy": "recent-source-v48",
                "attempts": "recent-v48-known-good:failure"
            ]
        )

        let event = capturedEvents.first
        XCTAssertEqual(event?.name, "StartupStoreRecovery")
        XCTAssertEqual(event?.properties["outcome"] as? String, "safe_mode")
        XCTAssertEqual(event?.properties["reason"] as? String, "unit_test")
        XCTAssertEqual(event?.properties["selected_strategy"] as? String, "recent-source-v48")
        XCTAssertEqual(event?.properties["attempts"] as? String, "recent-v48-known-good:failure")
        XCTAssertEqual(event?.properties["event_source"] as? String, "ios_client")
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

    func testExploreAudioPlaybackEventsContainOnlySurfaceAndClientSource() {
        AppTelemetry.trackExploreAudioPlaybackStarted(surface: "feed")
        AppTelemetry.trackExploreAudioPlaybackCompleted(surface: "detail")
        AppTelemetry.trackExploreAudioPlaybackFailed(surface: "detail")

        XCTAssertEqual(capturedEvents.map(\.name), [
            "ExploreAudioPlaybackStarted",
            "ExploreAudioPlaybackCompleted",
            "ExploreAudioPlaybackFailed"
        ])
        for event in capturedEvents {
            XCTAssertEqual(Set(event.properties.keys), ["surface", "event_source"])
            XCTAssertEqual(event.properties["event_source"] as? String, "ios_client")
        }
    }

    func testExternalImageImportEventContainsOnlyOutcomeAndClientSource() {
        AppTelemetry.trackExternalImageImport(outcome: "blocked_quota")

        let event = capturedEvents.first
        XCTAssertEqual(event?.name, "ExternalImageImport")
        XCTAssertEqual(event?.properties["outcome"] as? String, "blocked_quota")
        XCTAssertEqual(Set(event?.properties.keys.map { $0 } ?? []), ["outcome", "event_source"])
    }

    func testCaptureGoalIndicatorContainsOnlyCoarseActionSourceAndClientSource() {
        AppTelemetry.trackCaptureGoalIndicator(action: .zeroStateOpened, source: .fieldTrip)

        let event = capturedEvents.first
        XCTAssertEqual(event?.name, "CaptureGoalIndicator")
        XCTAssertEqual(event?.properties["action"] as? String, "zero_state_opened")
        XCTAssertEqual(event?.properties["source"] as? String, "field_trip")
        XCTAssertEqual(
            Set(event?.properties.keys.map { $0 } ?? []),
            ["action", "source", "event_source"]
        )
    }
}

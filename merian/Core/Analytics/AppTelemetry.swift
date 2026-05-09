import Foundation
import os
import TelemetryClient

/// Thin wrapper around TelemetryDeck for anonymous, PII-free analytics.
enum AppTelemetry {

    // MARK: - State

    private static let lock = NSLock()
    private nonisolated(unsafe) static var _isInitialized = false

    static var isInitialized: Bool {
        get { lock.withLock { _isInitialized } }
        set { lock.withLock { _isInitialized = newValue } }
    }

    // MARK: - Setup

    /// Initializes TelemetryDeck with the app's configured ID.
    static func initialize() {
        guard !MerianEnvironment.telemetryAppID.isEmpty else {
            MerianLog.general.error("TelemetryDeck configuration skipped because TELEMETRY_APP_ID is missing.")
            isInitialized = false
            return
        }

        let configuration = TelemetryDeck.Config(appID: MerianEnvironment.telemetryAppID)
        TelemetryDeck.initialize(config: configuration)
        isInitialized = true
        MerianLog.general.debug("TelemetryDeck initialized.")
    }

    // MARK: - Scan Events

    /// Records a completed scan.
    static func trackScan(isPro: Bool) {
        send("ScanCompleted", with: ["tier": isPro ? "Pro" : "Free"])
    }

    /// Records a new species discovery.
    static func trackNewDiscovery(isPro: Bool) {
        send("NewSpeciesDiscovered", with: ["tier": isPro ? "Pro" : "Free"])
    }

    // MARK: - Monetization Events

    /// Records a paywall impression.
    static func trackPaywallImpression() {
        send("PaywallViewed")
    }

    // MARK: - Offline Queue Events

    /// Records a scan successfully queued for offline sync.
    static func trackOfflineQueued() {
        send("OfflineQueuedScan")
    }

    // MARK: - Activation Events

    /// Records the user completing onboarding.
    static func trackOnboardingCompleted() {
        send("OnboardingCompleted")
    }

    // MARK: - Explore Events

    /// Records a user-visible Explore notifications fetch failure.
    static func trackExploreNotificationsFetchFailed(context: String) {
        send("ExploreNotificationsFetchFailed", with: ["context": context])
    }

    /// Records the user opening the Explore map tab.
    static func trackExploreMapOpened() {
        send("ExploreMapOpened")
    }

    /// Records an explicit map-area search action.
    static func trackExploreMapSearchTriggered(reason: String) {
        send("ExploreMapSearchTriggered", with: ["reason": reason])
    }

    /// Records tapping a cluster on the Explore map.
    static func trackExploreMapClusterTapped() {
        send("ExploreMapClusterTapped")
    }

    /// Records opening a map preview from a waypoint tap.
    static func trackExploreMapPreviewOpened(coordinateVisibility: String) {
        send("ExploreMapPreviewOpened", with: ["coordinateVisibility": coordinateVisibility])
    }

    /// Records opening the Explore detail flow from the map preview.
    static func trackExploreMapDetailOpened(entryPoint: String) {
        send("ExploreMapDetailOpened", with: ["entryPoint": entryPoint])
    }

    // MARK: - Achievement Events

    /// Records opening an achievement detail sheet.
    static func trackAchievementDetailOpened(type: String, state: String) {
        send("AchievementDetailOpened", with: ["type": type, "state": state])
    }

    /// Records opening a qualifying scan from an achievement detail sheet.
    static func trackAchievementContributionOpened(type: String) {
        send("AchievementContributionOpened", with: ["type": type])
    }

    /// Records a failed attempt to open an Explore notification target.
    static func trackExploreNotificationOpenFailed(type: String) {
        send("ExploreNotificationOpenFailed", with: ["type": type])
    }

    // MARK: - Hardware Events

    /// Records a thermal throttling event.
    static func trackThermalThrottling(fpsLimit: Int) {
        send("ThermalThrottled", with: ["targetFPS": String(fpsLimit)])
    }

    // MARK: - Error Events

    /// Records a named error domain for custom error tracking.
    static func trackError(_ errorDomain: String) {
        send("SystemError", with: ["domain": errorDomain])
    }

    // MARK: - Private

    private static func send(_ signal: String, with params: [String: String]? = nil) {
        guard isInitialized else {
            MerianLog.general.warning("AppTelemetry.send() called before initialize() — signal '\(signal)' dropped.")
            return
        }
        if let params {
            TelemetryDeck.signal(signal, parameters: params)
        } else {
            TelemetryDeck.signal(signal)
        }
    }
}

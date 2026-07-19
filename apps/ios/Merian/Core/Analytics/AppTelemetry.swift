import Foundation
import os

/// Thin app-wide facade for PII-free product analytics.
enum AppTelemetry {
    typealias CaptureHandler = (_ event: String, _ properties: [String: Any]) -> Void

    enum CaptureGoalIndicatorAction: String {
        case shown
        case opened
        case next
        case previous
        case zeroStateShown = "zero_state_shown"
        case zeroStateOpened = "zero_state_opened"
    }

    // MARK: - State

    private static let lock = NSLock()
    private nonisolated(unsafe) static var _isInitialized = false
    private nonisolated(unsafe) static var captureHandlerForTesting: CaptureHandler?

    static var isInitialized: Bool {
        get { lock.withLock { _isInitialized } }
        set { lock.withLock { _isInitialized = newValue } }
    }

    // MARK: - Setup

    /// Initializes the app analytics facade with PostHog as the only event sink.
    static func initialize() {
        if TestExecutionCoordinator.isRunningTests {
            isInitialized = testCaptureHandler != nil
            return
        }

        PostHogManager.shared.configure()
        isInitialized = PostHogManager.shared.isConfigured
        if isInitialized {
            MerianLog.general.debug("AppTelemetry initialized with PostHog.")
        } else {
            MerianLog.general.error("AppTelemetry configuration skipped because PostHog is not configured.")
        }
    }

    static func installCaptureHandlerForTesting(_ handler: CaptureHandler?) {
        lock.withLock {
            captureHandlerForTesting = handler
            _isInitialized = false
        }
    }

    // MARK: - Scan Events

    /// Records a completed scan.
    static func trackScan(isPro: Bool, isSubscribed: Bool, inferenceTier: String? = nil) {
        send("ClientScanCompleted", with: scanTelemetryParameters(
            isPro: isPro,
            isSubscribed: isSubscribed,
            inferenceTier: inferenceTier
        ))
    }

    static func scanTelemetryParameters(isPro: Bool, isSubscribed: Bool, inferenceTier: String? = nil) -> [String: String] {
        let normalizedInferenceTier = inferenceTier?.lowercased()
        let usedProModel = normalizedInferenceTier == "pro" || (normalizedInferenceTier == nil && isPro)
        let plan = usedProModel ? (isSubscribed ? "pro_paid" : "pro_trial") : "free"
        return [
            "tier": usedProModel ? "Pro" : "Free",
            "plan": plan,
            "inferenceTier": normalizedInferenceTier ?? (usedProModel ? "pro" : "flash")
        ]
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
        send("ScanQueuedForSync")
    }

    // MARK: - External Image Import Events

    static func trackExternalImageImport(outcome: String) {
        send("ExternalImageImport", with: ["outcome": outcome])
    }

    // MARK: - Capture Goal Events

    /// Records coarse indicator engagement without goal, outing, or account identity.
    static func trackCaptureGoalIndicator(
        action: CaptureGoalIndicatorAction,
        source: CaptureGoalSourceKind
    ) {
        send("CaptureGoalIndicator", with: [
            "action": action.rawValue,
            "source": source.rawValue
        ])
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

    /// Records a user-initiated public audio playback without media or species identity.
    static func trackExploreAudioPlaybackStarted(surface: String) {
        send("ExploreAudioPlaybackStarted", with: ["surface": surface])
    }

    static func trackExploreAudioPlaybackCompleted(surface: String) {
        send("ExploreAudioPlaybackCompleted", with: ["surface": surface])
    }

    static func trackExploreAudioPlaybackFailed(surface: String) {
        send("ExploreAudioPlaybackFailed", with: ["surface": surface])
    }

    static func trackExploreAudioBoost(event: String, surface: String, gainBand: String? = nil) {
        var properties = ["surface": surface, "action": event]
        if let gainBand { properties["gainBand"] = gainBand }
        send("ExploreAudioBoostChanged", with: properties)
    }

    static func trackInsightAudioBoost(event: String, gainBand: String? = nil) {
        var properties = ["surface": "insight", "action": event]
        if let gainBand { properties["gainBand"] = gainBand }
        send("InsightAudioBoostChanged", with: properties)
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

    // MARK: - Species Dictionary Events

    /// Records opening the species dictionary sheet without attaching species identity.
    static func trackSpeciesDictionaryOpened(entryPoint: String) {
        send("SpeciesDictionaryOpened", with: ["entryPoint": entryPoint])
    }

    /// Records a successful species dictionary load without attaching species identity.
    static func trackSpeciesDictionaryLoaded(entryPoint: String, contentQuality: String) {
        send("SpeciesDictionaryPageLoaded", with: [
            "entryPoint": entryPoint,
            "contentQuality": contentQuality
        ])
    }

    /// Records a dictionary lookup that did not resolve to a public species row.
    static func trackSpeciesDictionaryNotFound(entryPoint: String) {
        send("SpeciesDictionaryNotFound", with: ["entryPoint": entryPoint])
    }

    /// Records an explicit retry from the dictionary error or not-found state.
    static func trackSpeciesDictionaryRetry(entryPoint: String) {
        send("SpeciesDictionaryRetry", with: ["entryPoint": entryPoint])
    }

    /// Records a public reference image load failure that falls back to placeholder UI.
    static func trackSpeciesDictionaryImageFallback(entryPoint: String, source: String) {
        send("SpeciesDictionaryReferenceImageFallback", with: [
            "entryPoint": entryPoint,
            "source": source
        ])
    }

    // MARK: - Hardware Events

    /// Records a thermal throttling event.
    static func trackThermalThrottling(fpsLimit: Int) {
        send("CaptureThermalThrottled", with: ["targetFPS": String(fpsLimit)])
    }

    /// Records privacy-safe focus-detection performance without image content or coordinates.
    static func trackImageFocusDetection(
        durationMilliseconds: Int,
        outcome: String,
        areaBucket: String?
    ) {
        var properties = [
            "durationMs": String(max(0, durationMilliseconds)),
            "outcome": outcome
        ]
        if let areaBucket {
            properties["areaBucket"] = areaBucket
        }
        send("ImageFocusDetectionCompleted", with: properties)
    }

    // MARK: - Error Events

    /// Records a named error domain for custom error tracking.
    static func trackError(_ errorDomain: String) {
        send("ClientErrorCaptured", with: ["domain": errorDomain])
    }

    /// Records launch-time local store recovery without including paths, user IDs, or exception text.
    static func trackStartupStoreRecovery(
        outcome: String,
        reason: String,
        properties: [String: String] = [:]
    ) {
        var params = properties
        params.merge([
            "outcome": outcome,
            "reason": reason
        ]) { _, latest in latest }
        send("StartupStoreRecovery", with: params)
    }

    // MARK: - Private

    private static func send(_ signal: String, with params: [String: String]? = nil) {
        guard isInitialized else {
            MerianLog.general.warning("AppTelemetry.send() called before initialize() — signal '\(signal)' dropped.")
            return
        }

        var properties = params?.reduce(into: [String: Any]()) { result, element in
            result[element.key] = element.value
        } ?? [:]
        properties["event_source"] = "ios_client"

        if let testCaptureHandler {
            testCaptureHandler(signal, properties)
            return
        }

        PostHogManager.shared.capture(signal, properties: properties)
    }

    private static var testCaptureHandler: CaptureHandler? {
        lock.withLock { captureHandlerForTesting }
    }
}

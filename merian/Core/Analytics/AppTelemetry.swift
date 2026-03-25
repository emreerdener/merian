import Foundation
import TelemetryClient
import os

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
        let configuration = TelemetryManagerConfiguration(appID: MerianEnvironment.telemetryAppID)
        TelemetryManager.initialize(with: configuration)
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
            TelemetryManager.send(signal, with: params)
        } else {
            TelemetryManager.send(signal)
        }
    }
}

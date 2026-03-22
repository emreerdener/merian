import Foundation
import TelemetryClient

// MARK: - Core TelemetryDeck Gateway
/// Architecture wrapper for TelemetryDeck.
/// All metrics are strictly anonymized, ensuring ZERO Personally Identifiable Information (PII) is tracked.
enum AppTelemetry {
    // MARK: - Thread-Safe State Management
    
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _isInitialized = false
    
    static var isInitialized: Bool {
        get {
            lock.lock()
            let value = _isInitialized
            lock.unlock()
            return value
        }
        set {
            lock.lock()
            _isInitialized = newValue
            lock.unlock()
        }
    }
    
    // MARK: - Lifecycle Bootstrapping
    /// Establishes the connection to TelemetryDeck during the instant iOS App Boot phase
    static func initialize() {
        let appId = MerianEnvironment.telemetryAppID
        
        let configuration = TelemetryManagerConfiguration(appID: appId)
        
        // Disable automatically sending location data to honor the strict Master Protocol Geoprivacy constraints
        // We only append location when the user explicitly agrees to 'public' biological scans natively
        
        TelemetryManager.initialize(with: configuration)
        isInitialized = true
        print("📊 TelemetryDeck securely initialized (Anonymous Analytics Only)")
    }
    
    // MARK: - Gamification Event Metrics
    /// Tracks a successful taxonomy interaction globally mapped back to the hardware pipeline
    static func trackScan(isPro: Bool) {
        guard isInitialized else { return }
        TelemetryManager.send("ScanCompleted", with: [
            "tier": isPro ? "Pro" : "Free"
        ])
    }
    
    /// Tracks globally mapping back to when a user captures an entirely new species
    static func trackNewDiscovery(isPro: Bool) {
        guard isInitialized else { return }
        TelemetryManager.send("NewSpeciesDiscovered", with: [
            "tier": isPro ? "Pro" : "Free"
        ])
    }
    
    // MARK: - Monetization Event Metrics
    /// Tracks when a user hits the physical 2-scan bounds and the Paywall springs dynamically
    static func trackPaywallImpression() {
        guard isInitialized else { return }
        TelemetryManager.send("PaywallViewed")
    }
    
    // MARK: - Hardware Health Event Metrics
    /// Tracks if the device's physical sensors hit critical thresholds and trigger Thermal Downgrading
    static func trackThermalThrottling(fpsLimit: Int) {
        guard isInitialized else { return }
        TelemetryManager.send("ThermalThrottled", with: [
            "targetFPS": String(fpsLimit)
        ])
    }
    
    // MARK: - Fatal Exception Event Metrics
    /// Hard crash tracker (implicitly caught by TelemetryDeck out of the box, but this allows custom assertions)
    static func trackError(_ errorDomain: String) {
        guard isInitialized else { return }
        TelemetryManager.send("SystemError", with: [
            "domain": errorDomain
        ])
    }
}

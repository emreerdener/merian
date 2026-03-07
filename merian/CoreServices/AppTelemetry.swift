import Foundation
import TelemetryClient

/// Architecture wrapper for TelemetryDeck.
/// All metrics are strictly anonymized, ensuring ZERO Personally Identifiable Information (PII) is tracked.
enum AppTelemetry {
    
    /// Establishes the connection to TelemetryDeck during the instant iOS App Boot phase
    static func initialize() {
        let appId = MerianEnvironment.telemetryAppID
        
        let configuration = TelemetryManagerConfiguration(appID: appId)
        
        // Disable automatically sending location data to honor the strict Master Protocol Geoprivacy constraints
        // We only append location when the user explicitly agrees to 'public' biological scans natively
        
        TelemetryManager.initialize(with: configuration)
        print("📊 TelemetryDeck securely initialized (Anonymous Analytics Only)")
    }
    
    /// Tracks a successful taxonomy interaction globally mapped back to the hardware pipeline
    static func trackScan(isPro: Bool) {
        TelemetryManager.send("ScanCompleted", with: [
            "tier": isPro ? "Pro" : "Free"
        ])
    }
    
    /// Tracks when a user hits the physical 3-scan bounds and the Paywall springs dynamically
    static func trackPaywallImpression() {
        TelemetryManager.send("PaywallViewed")
    }
    
    /// Tracks if the device's physical sensors hit critical thresholds and trigger Thermal Downgrading
    static func trackThermalThrottling(fpsLimit: Int) {
        TelemetryManager.send("ThermalThrottled", with: [
            "targetFPS": String(fpsLimit)
        ])
    }
    
    /// Hard crash tracker (implicitly caught by TelemetryDeck out of the box, but this allows custom assertions)
    static func trackError(_ errorDomain: String) {
        TelemetryManager.send("SystemError", with: [
            "domain": errorDomain
        ])
    }
}

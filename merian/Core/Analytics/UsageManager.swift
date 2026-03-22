import Foundation
import Combine
import Observation

// MARK: - Core Quota Enforcement
/// Enforces the Explorer Tier (Free) strict limitations. Tracks scan counts against the physical device constraints (DeviceCheck prep).
@MainActor
@Observable final class UsageManager {
    // MARK: - Singleton Architecture
    static let shared = UsageManager()
    
    // MARK: - Quota Thresholds
    private let maxFreeScansPerDay = 2
    
    // MARK: - State Management
    var freeScansRemaining: Int = 0
    var showPaywall: Bool = false
    
    // MARK: - Persistent Storage Keys
    private let defaults = UserDefaults.standard
    private var lastScanDateKey: String { "Merian_LastScanDate_\(DeviceIdentityManager.shared.deviceId)" }
    private var scansUsedKey: String { "Merian_ScansUsedToday_\(DeviceIdentityManager.shared.deviceId)" }
    
    // MARK: - Lifecycle Bootstrapping
    private init() {
        self.freeScansRemaining = maxFreeScansPerDay
        evaluateDailyRefresh()
    }
    
    // MARK: - Quota Validation Engine
    /// Called passively on App Boot or during an active session to resolve the 24-hour UTC rollover boundary
    func evaluateDailyRefresh() {
        let calendar = Calendar.current
        let lastDate = defaults.object(forKey: lastScanDateKey) as? Date ?? Date.distantPast
        
        if !calendar.isDateInToday(lastDate) {
            // A new day has passed, refresh the quotas physically back to baseline
            defaults.set(Date(), forKey: lastScanDateKey)
            defaults.set(0, forKey: scansUsedKey)
            self.freeScansRemaining = maxFreeScansPerDay
        } else {
            let used = defaults.integer(forKey: scansUsedKey)
            self.freeScansRemaining = max(0, maxFreeScansPerDay - used)
        }
    }
    
    // MARK: - Execution & Refund Mutators
    /// Explicitly called the exact moment the user triggers an iOS Camera Shutter capture sequence natively.
    /// Returns true if the architecture legally allows the AI payload to jump up to Supabase.
    func canPerformScan(isProActive: Bool) -> Bool {
        #warning("TEMPORARY OVERRIDE: Daily scan limit bypassed for testing. Remove before launch!")
        return true
        // return isProActive || freeScansRemaining > 0
    }
    
    /// Deducts a scan perfectly from the physical vault constraints. 
    /// This is now called exactly when the user commits to analyzing an image to prevent airplane-mode hoarding.
    func consumeScan() {
        let used = defaults.integer(forKey: scansUsedKey) + 1
        defaults.set(used, forKey: scansUsedKey)
        defaults.set(Date(), forKey: lastScanDateKey)
        
        self.freeScansRemaining -= 1
    }
    
    /// Restores a scan if the inference engine natively fails to process the payload (e.g. unreadable image or aborted request), ensuring the user isn't unfairly penalized.
    func refundScan() {
        let currentUsed = defaults.integer(forKey: scansUsedKey)
        if currentUsed > 0 {
            defaults.set(currentUsed - 1, forKey: scansUsedKey)
            self.freeScansRemaining += 1
        }
    }
}

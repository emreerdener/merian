import Foundation
import Combine

/// Enforces the Explorer Tier (Free) strict limitations. Tracks scan counts against the physical device constraints (DeviceCheck prep).
@MainActor
final class UsageManager: ObservableObject {
    static let shared = UsageManager()
    
    private let maxFreeScansPerDay = 3
    
    @Published var freeScansRemaining: Int
    @Published var showPaywall: Bool = false
    
    private let defaults = UserDefaults.standard
    private let lastScanDateKey = "Merian_LastScanDate"
    private let scansUsedKey = "Merian_ScansUsedToday"
    
    private init() {
        self.freeScansRemaining = maxFreeScansPerDay
        evaluateDailyRefresh()
    }
    
    /// Called passively on App Boot or during an active session to resolve the 24-hour UTC rollover boundary
    func evaluateDailyRefresh() {
        let calendar = Calendar.current
        let lastDate = defaults.object(forKey: lastScanDateKey) as? Date ?? Date.distantPast
        
        if !calendar.isDateInToday(lastDate) {
            // A new day has passed, refresh the quotas physically back to baseline
            defaults.set(Date(), forKey: lastScanDateKey)
            defaults.set(0, forKey: scansUsedKey)
            self.freeScansRemaining = maxFreeScansPerDay
            print("🌅 Explorer Tier: Daily scan limits refreshed globally!")
        } else {
            let used = defaults.integer(forKey: scansUsedKey)
            self.freeScansRemaining = max(0, maxFreeScansPerDay - used)
        }
    }
    
    /// Explicitly called the exact moment the user triggers an iOS Camera Shutter capture sequence natively.
    /// Returns true if the architecture legally allows the AI payload to jump up to Supabase.
    func canPerformScan(isProActive: Bool) -> Bool {
        return true // TEMPORARILY DISABLED FOR TESTING
    }
    
    /// Deducts a scan perfectly from the physical vault constraints. 
    /// This should ONLY be called once the Supabase API positively returns a species validation.
    func recordSuccessfulScan() {
        let used = defaults.integer(forKey: scansUsedKey) + 1
        defaults.set(used, forKey: scansUsedKey)
        defaults.set(Date(), forKey: lastScanDateKey)
        
        self.freeScansRemaining = max(0, maxFreeScansPerDay - used)
        print("📸 Scan Deducted | Remaining today: \(freeScansRemaining)")
    }
}

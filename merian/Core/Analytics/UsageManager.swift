import Foundation
import Observation

/// Tracks daily scan usage for free-tier users and enforces the per-day quota.
@MainActor
@Observable final class UsageManager {
    static let shared = UsageManager()

    // MARK: - Configuration

    let maxFreeScansPerDay = 2

    // MARK: - State

    var freeScansRemaining: Int = 0
    var showPaywall: Bool = false

    // MARK: - Storage Keys

    private let defaults = UserDefaults.standard
    private var lastScanDateKey: String { "Merian_LastScanDate_\(DeviceIdentityManager.shared.deviceId)" }
    private var scansUsedKey: String { "Merian_ScansUsedToday_\(DeviceIdentityManager.shared.deviceId)" }

    private init() {
        freeScansRemaining = maxFreeScansPerDay
        evaluateDailyRefresh()
    }

    // MARK: - Quota

    /// Resets the scan count if the calendar day has changed.
    func evaluateDailyRefresh() {
        let lastDate = defaults.object(forKey: lastScanDateKey) as? Date ?? Date.distantPast

        if !Calendar.current.isDateInToday(lastDate) {
            // New day — reset the scan count.
            defaults.set(Date(), forKey: lastScanDateKey)
            defaults.set(0, forKey: scansUsedKey)
            freeScansRemaining = maxFreeScansPerDay
        } else {
            let used = defaults.integer(forKey: scansUsedKey)
            freeScansRemaining = max(0, maxFreeScansPerDay - used)
        }
    }

    // MARK: - Scan Consumption

    /// Returns true if the user is allowed to perform another scan.
    func canPerformScan(isProActive: Bool) -> Bool {
        return isProActive || freeScansRemaining > 0
    }

    /// Records a scan as consumed, updating the daily count.
    func consumeScan() {
        let used = defaults.integer(forKey: scansUsedKey) + 1
        defaults.set(used, forKey: scansUsedKey)
        defaults.set(Date(), forKey: lastScanDateKey)
        freeScansRemaining -= 1
    }

    /// Refunds a scan when processing fails and the user should not be charged.
    func refundScan() {
        let currentUsed = defaults.integer(forKey: scansUsedKey)
        if currentUsed > 0 {
            defaults.set(currentUsed - 1, forKey: scansUsedKey)
            freeScansRemaining += 1
        }
    }
}

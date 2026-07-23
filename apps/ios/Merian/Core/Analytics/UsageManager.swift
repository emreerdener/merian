import Foundation
import Observation

/// Maintains a responsive, advisory local scan meter for free-tier UX.
///
/// The Supabase AI quota reservation is the authorization boundary. Values in
/// UserDefaults can be stale or modified and must never be treated as proof
/// that a paid provider call is allowed.
@MainActor
@Observable final class UsageManager {
    static let shared = UsageManager()

    // MARK: - Configuration

    let maxFreeScansPerDay = 1

    // MARK: - State

    var freeScansRemaining: Int = 0
    var showPaywall: Bool = false

    // MARK: - Storage Keys

    private let defaults = UserDefaults.standard
    private var lastScanDateKey: String { "Merian_LastScanDate_\(DeviceIdentityManager.shared.deviceId)" }
    private var scansUsedKey: String { "Merian_ScansUsedToday_\(DeviceIdentityManager.shared.deviceId)" }
    private var hasLoggedFreeScanLimitOverride = false

#if DEBUG
    static var debugFreeScanLimitOverride: Bool?
    private static let freeScanLimitOverrideEnvironmentKey = "MERIAN_DISABLE_FREE_SCAN_LIMIT"
#endif

    private init() {
        freeScansRemaining = maxFreeScansPerDay
        evaluateDailyRefresh()
    }

    private var isFreeScanLimitOverrideEnabled: Bool {
#if DEBUG
        if let debugFreeScanLimitOverride = Self.debugFreeScanLimitOverride {
            return debugFreeScanLimitOverride
        }
#endif

        if FeatureFlags.isEnabled(.unlimitedFreeScans) {
            return true
        }

#if DEBUG
        return ProcessInfo.processInfo.environment[Self.freeScanLimitOverrideEnvironmentKey] == "1"
#else
        return false
#endif
    }

    private func logFreeScanLimitOverrideIfNeeded() {
        guard isFreeScanLimitOverrideEnabled, !hasLoggedFreeScanLimitOverride else { return }
        hasLoggedFreeScanLimitOverride = true

        if FeatureFlags.isEnabled(.unlimitedFreeScans) {
            MerianLog.general.warning("DEBUG OVERRIDE ACTIVE: the advisory local free-scan meter is disabled.")
            return
        }

#if DEBUG
        MerianLog.general.warning("DEBUG OVERRIDE ACTIVE: the advisory local free-scan meter is disabled via MERIAN_DISABLE_FREE_SCAN_LIMIT.")
#endif
    }

    // MARK: - Quota

    /// Resets the scan count if the calendar day has changed.
    func evaluateDailyRefresh() {
        if isFreeScanLimitOverrideEnabled {
            logFreeScanLimitOverrideIfNeeded()
            freeScansRemaining = maxFreeScansPerDay
            showPaywall = false
            return
        }

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

    /// Returns whether local UX should start another scan.
    ///
    /// This is advisory only. The server independently authorizes and reserves
    /// quota before any paid provider call.
    func canPerformScan(isProActive: Bool) -> Bool {
        if isFreeScanLimitOverrideEnabled {
            logFreeScanLimitOverrideIfNeeded()
            return true
        }

        return isProActive || freeScansRemaining > 0
    }

    /// Records a scan in the advisory local meter.
    func consumeScan() {
        if isFreeScanLimitOverrideEnabled {
            logFreeScanLimitOverrideIfNeeded()
            return
        }

        let used = defaults.integer(forKey: scansUsedKey) + 1
        defaults.set(used, forKey: scansUsedKey)
        defaults.set(Date(), forKey: lastScanDateKey)
        freeScansRemaining -= 1
    }

    /// Refunds the advisory local meter after a pre-provider failure.
    ///
    /// Server quota refunds are handled independently by the Edge Function.
    func refundScan() {
        if isFreeScanLimitOverrideEnabled {
            logFreeScanLimitOverrideIfNeeded()
            return
        }

        let currentUsed = defaults.integer(forKey: scansUsedKey)
        if currentUsed > 0 {
            defaults.set(currentUsed - 1, forKey: scansUsedKey)
            freeScansRemaining += 1
        }
    }
}

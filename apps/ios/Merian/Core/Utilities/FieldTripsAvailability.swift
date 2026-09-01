import Foundation

/// Every build-time product release gate, with the value shipped to production.
///
/// DEBUG builds may override these values from Settings → Feature Flags. Release
/// builds never read those local overrides.
enum FeatureFlag: String, CaseIterable, Identifiable, Sendable {
    case fieldTrips
    case dwcaExports
    case unlimitedFreeScans

    var id: String { rawValue }

    var defaultValue: Bool {
        switch self {
        case .fieldTrips:
            true
        case .dwcaExports:
            // swiftlint:disable:next todo
            // TODO(dwca-export-release): Enable only after the deferred DwC-A
            // production load, delivery, and operations gates pass.
            false
        case .unlimitedFreeScans:
            false
        }
    }

    var title: String {
        switch self {
        case .fieldTrips:
            "Field trips"
        case .dwcaExports:
            "Darwin Core exports"
        case .unlimitedFreeScans:
            "Bypass local scan meter"
        }
    }

    var summary: String {
        switch self {
        case .fieldTrips:
            "Shows Field trips and its supporting progress surfaces."
        case .dwcaExports:
            "Shows the staged scan-export controls. The server gate remains authoritative."
        case .unlimitedFreeScans:
            "Debug-only bypass for the advisory local scan meter."
        }
    }
}

/// Central resolver for build-time release gates.
enum FeatureFlags {
    private static let debugOverrideKeyPrefix = "Merian.DebugFeatureFlag."

    static func isEnabled(
        _ flag: FeatureFlag,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        debugOverride(for: flag, userDefaults: userDefaults) ?? flag.defaultValue
    }

    /// Returns a persisted override in DEBUG builds and always returns `nil` in
    /// production, ensuring App Store behavior comes only from code defaults.
    static func debugOverride(
        for flag: FeatureFlag,
        userDefaults: UserDefaults = .standard
    ) -> Bool? {
        #if DEBUG
        userDefaults.object(forKey: debugOverrideKey(for: flag)) as? Bool
        #else
        nil
        #endif
    }

    #if DEBUG
    static func setDebugOverride(
        _ value: Bool?,
        for flag: FeatureFlag,
        userDefaults: UserDefaults = .standard
    ) {
        let key = debugOverrideKey(for: flag)
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    static func resetDebugOverrides(userDefaults: UserDefaults = .standard) {
        for flag in FeatureFlag.allCases {
            setDebugOverride(nil, for: flag, userDefaults: userDefaults)
        }
    }
    #endif

    private static func debugOverrideKey(for flag: FeatureFlag) -> String {
        debugOverrideKeyPrefix + flag.rawValue
    }
}

enum FieldTripSharingAvailability {
    // swiftlint:disable:next todo
    // TODO(field-trip-sharing-experience): Enable only after the complete standard
    // outing sharing experience is ready, then restore publication-state labels.
    static let isEnabled = false
}

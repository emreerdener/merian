import Foundation

/// Every build-time product release gate, with the value shipped to production.
///
/// DEBUG builds may override these values from Settings → Feature Flags. Release
/// builds never read those local overrides.
enum FeatureFlag: String, CaseIterable, Identifiable, Sendable {
    case speciesDictionaryTree
    case fieldTrips
    case fieldTripEvents
    case dwcaExports
    case unlimitedFreeScans

    var id: String { rawValue }

    var defaultValue: Bool {
        switch self {
        case .speciesDictionaryTree:
            // swiftlint:disable:next todo
            // TODO(species-dictionary-tree-release): Enable after the Tree is ready to ship.
            false
        case .fieldTripEvents:
            false
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
        case .speciesDictionaryTree:
            "Species Dictionary Tree"
        case .fieldTrips:
            "Field trips"
        case .fieldTripEvents:
            "Field trip Events"
        case .dwcaExports:
            "Darwin Core exports"
        case .unlimitedFreeScans:
            "Bypass local scan meter"
        }
    }

    var summary: String {
        switch self {
        case .speciesDictionaryTree:
            "Shows the unfinished Tree inside Explore’s Index."
        case .fieldTrips:
            "Shows Field trips and its supporting progress surfaces."
        case .fieldTripEvents:
            "Releases Events beyond the simulator and tester preview."
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

@MainActor
enum FieldTripEventsAvailability {
    // swiftlint:disable:next todo
    // TODO(field-trip-events-release): When Events UI/UX is ready, follow the release
    // checklist in docs/features-and-hardware/25-field-trips.md, change the central
    // default, promote the preview changelog copy, and remove preview bypasses.
    static var isReleased: Bool {
        FeatureFlag.fieldTripEvents.defaultValue
    }

    static let allowedEmail = "erdener.emre@gmail.com"

    static var isEnabled: Bool {
        isEnabled(
            isReleased: isReleased,
            email: SupabaseManager.shared.currentUser?.email,
            isSimulator: isSimulatorBuild,
            debugOverride: FeatureFlags.debugOverride(for: .fieldTripEvents)
        )
    }

    static func isEnabled(
        isReleased: Bool,
        email: String?,
        isSimulator: Bool,
        debugOverride: Bool? = nil
    ) -> Bool {
        if let debugOverride {
            return debugOverride
        }

        if isReleased || isSimulator { return true }
        return email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == allowedEmail
    }

    static func logRolloutState() {
        #if DEBUG
        if isReleased {
            MerianLog.general.notice(
                "Field Trips rollout: Outings and Events are public."
            )
        } else {
            MerianLog.general.notice(
                "TODO(field-trip-events-release): Outings are public; Events remain staged to the tester allowlist and simulator builds."
            )
        }
        #endif
    }

    private static var isSimulatorBuild: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}

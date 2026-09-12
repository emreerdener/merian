import Foundation
@testable import Merian
import Testing

@Suite("Feature Flag Tests")
@MainActor
struct FeatureFlagsTests {
    @Test func fieldTripsAreReleasedForEveryUserAndDevice() throws {
        let suiteName = "FieldTripsReleaseGateTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        #expect(FeatureFlags.isEnabled(
            .fieldTrips,
            userDefaults: userDefaults
        ))
    }

    @Test func registryContainsEveryReleaseGateAndItsProductionDefault() {
        #expect(FeatureFlag.allCases == [
            .fieldTrips,
            .dwcaExports,
            .unlimitedFreeScans
        ])
        #expect(FeatureFlag.fieldTrips.defaultValue)
        #expect(!FeatureFlag.dwcaExports.defaultValue)
        #expect(!FeatureFlag.unlimitedFreeScans.defaultValue)
    }

    @Test func dwcaExportsRemainStagedUntilTheExplicitReleaseChange() throws {
        let suiteName = "DwcaExportsReleaseGateTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        #expect(!FeatureFlags.isEnabled(
            .dwcaExports,
            userDefaults: userDefaults
        ))
    }

    #if DEBUG
    @Test func debugOverridesUseInstalledKeysAndResetToCodeDefaults() throws {
        let suiteName = "FeatureFlagsTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let installedKeys: [(flag: FeatureFlag, key: String)] = [
            (.fieldTrips, "Merian.DebugFeatureFlag.fieldTrips"),
            (.dwcaExports, "Merian.DebugFeatureFlag.dwcaExports"),
            (.unlimitedFreeScans, "Merian.DebugFeatureFlag.unlimitedFreeScans")
        ]

        for installedKey in installedKeys {
            let override = !installedKey.flag.defaultValue
            FeatureFlags.setDebugOverride(
                override,
                for: installedKey.flag,
                userDefaults: userDefaults
            )
            #expect(
                userDefaults.object(forKey: installedKey.key) as? Bool == override
            )
            #expect(FeatureFlags.isEnabled(
                installedKey.flag,
                userDefaults: userDefaults
            ) == override)
        }

        FeatureFlags.resetDebugOverrides(userDefaults: userDefaults)

        for installedKey in installedKeys {
            #expect(userDefaults.object(forKey: installedKey.key) == nil)
            #expect(FeatureFlags.isEnabled(
                installedKey.flag,
                userDefaults: userDefaults
            ) == installedKey.flag.defaultValue)
        }
    }
    #endif

    @Test func eventsAreNotAFeatureFlag() {
        #expect(!FeatureFlag.allCases.contains { $0.rawValue == "fieldTripEvents" })
    }
}

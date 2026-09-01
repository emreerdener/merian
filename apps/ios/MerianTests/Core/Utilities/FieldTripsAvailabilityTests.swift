import Foundation
@testable import Merian
import Testing

@Suite("Field trips Availability Tests")
@MainActor
struct FieldTripsAvailabilityTests {
    @Test func fieldTripsAreReleasedForEveryUserAndDevice() {
        #expect(FeatureFlags.isEnabled(.fieldTrips))
    }

    @Test func standardOutingSharingRemainsDeferredUntilTheExperienceIsReady() {
        #expect(!FieldTripSharingAvailability.isEnabled)
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
    @Test func debugOverridesArePersistedAndCanReturnToTheCodeDefault() throws {
        let suiteName = "FeatureFlagsTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        #expect(!FeatureFlags.isEnabled(
            .dwcaExports,
            userDefaults: userDefaults
        ))

        FeatureFlags.setDebugOverride(
            true,
            for: .dwcaExports,
            userDefaults: userDefaults
        )
        #expect(FeatureFlags.isEnabled(
            .dwcaExports,
            userDefaults: userDefaults
        ))

        FeatureFlags.setDebugOverride(
            nil,
            for: .dwcaExports,
            userDefaults: userDefaults
        )
        #expect(!FeatureFlags.isEnabled(
            .dwcaExports,
            userDefaults: userDefaults
        ))
    }
    #endif

    @Test func eventsAreNotAFeatureFlag() {
        #expect(!FeatureFlag.allCases.contains { $0.rawValue == "fieldTripEvents" })
    }
}

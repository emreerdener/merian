import Foundation
@testable import Merian
import Testing

@Suite("Field trips Availability Tests")
@MainActor
struct FieldTripsAvailabilityTests {
    @Test func fieldTripsAreReleasedForEveryUserAndDevice() {
        #expect(FeatureFlags.isEnabled(.fieldTrips))
    }

    @Test func eventsRemainStagedUntilTheExplicitReleaseChange() {
        #expect(!FieldTripEventsAvailability.isReleased)
    }

    @Test func registryContainsEveryReleaseGateAndItsProductionDefault() {
        #expect(FeatureFlag.allCases == [
            .speciesDictionaryTree,
            .fieldTrips,
            .fieldTripEvents,
            .dwcaExports,
            .unlimitedFreeScans
        ])
        #expect(!FeatureFlag.speciesDictionaryTree.defaultValue)
        #expect(FeatureFlag.fieldTrips.defaultValue)
        #expect(!FeatureFlag.fieldTripEvents.defaultValue)
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
            .speciesDictionaryTree,
            userDefaults: userDefaults
        ))

        FeatureFlags.setDebugOverride(
            true,
            for: .speciesDictionaryTree,
            userDefaults: userDefaults
        )
        #expect(FeatureFlags.isEnabled(
            .speciesDictionaryTree,
            userDefaults: userDefaults
        ))

        FeatureFlags.setDebugOverride(
            nil,
            for: .speciesDictionaryTree,
            userDefaults: userDefaults
        )
        #expect(!FeatureFlags.isEnabled(
            .speciesDictionaryTree,
            userDefaults: userDefaults
        ))
    }
    #endif

    @Test func simulatorAlwaysEnablesFieldTripEventsPreview() {
        #expect(FieldTripEventsAvailability.isEnabled(
            isReleased: false,
            email: nil,
            isSimulator: true
        ))
        #expect(FieldTripEventsAvailability.isEnabled(
            isReleased: false,
            email: "someone@example.com",
            isSimulator: true
        ))
    }

    @Test func eventsPreviewEmailIsCaseAndWhitespaceInsensitive() {
        #expect(FieldTripEventsAvailability.isEnabled(
            isReleased: false,
            email: "  ERDENER.EMRE@GMAIL.COM ",
            isSimulator: false
        ))
    }

    @Test func otherUsersAndGuestsCannotSeeEventsPreviewOnDevice() {
        #expect(!FieldTripEventsAvailability.isEnabled(
            isReleased: false,
            email: nil,
            isSimulator: false
        ))
        #expect(!FieldTripEventsAvailability.isEnabled(
            isReleased: false,
            email: "someone@example.com",
            isSimulator: false
        ))
    }

    @Test func eventsReleaseFlagEnablesEveryUserAndDevice() {
        #expect(FieldTripEventsAvailability.isEnabled(
            isReleased: true,
            email: nil,
            isSimulator: false
        ))
        #expect(FieldTripEventsAvailability.isEnabled(
            isReleased: true,
            email: "someone@example.com",
            isSimulator: false
        ))
    }

    @Test func eventDebugOverrideWinsOverReleaseAndPreviewEligibility() {
        #expect(!FieldTripEventsAvailability.isEnabled(
            isReleased: true,
            email: FieldTripEventsAvailability.allowedEmail,
            isSimulator: true,
            debugOverride: false
        ))
        #expect(FieldTripEventsAvailability.isEnabled(
            isReleased: false,
            email: nil,
            isSimulator: false,
            debugOverride: true
        ))
    }
}

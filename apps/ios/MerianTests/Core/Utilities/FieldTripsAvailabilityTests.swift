@testable import Merian
import Testing

@Suite("Field trips Availability Tests")
@MainActor
struct FieldTripsAvailabilityTests {
    @Test func fieldTripsAreReleasedForEveryUserAndDevice() {
        #expect(FieldTripsAvailability.isEnabled)
    }

    @Test func eventsRemainStagedUntilTheExplicitReleaseChange() {
        #expect(!FieldTripEventsAvailability.isReleased)
    }

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
}

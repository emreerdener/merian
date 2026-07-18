@testable import Merian
import Testing

@Suite("Field trips Availability Tests")
@MainActor
struct FieldTripsAvailabilityTests {
    @Test func simulatorAlwaysEnablesFieldTrips() {
        #expect(FieldTripsAvailability.isEnabled(email: nil, isSimulator: true))
        #expect(FieldTripsAvailability.isEnabled(email: "someone@example.com", isSimulator: true))
    }

    @Test func allowlistedEmailIsCaseAndWhitespaceInsensitive() {
        #expect(FieldTripsAvailability.isEnabled(
            email: "  ERDENER.EMRE@GMAIL.COM ",
            isSimulator: false
        ))
    }

    @Test func otherUsersAndGuestsCannotSeeFieldTripsOnDevice() {
        #expect(!FieldTripsAvailability.isEnabled(email: nil, isSimulator: false))
        #expect(!FieldTripsAvailability.isEnabled(
            email: "someone@example.com",
            isSimulator: false
        ))
    }
}

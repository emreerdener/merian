@testable import Merian
import Testing

@Suite("Field Trip Sharing Availability Tests")
struct FieldTripSharingAvailabilityTests {
    @Test func standardOutingSharingRemainsDeferredUntilTheExperienceIsReady() {
        #expect(!FieldTripSharingAvailability.isEnabled)
    }
}

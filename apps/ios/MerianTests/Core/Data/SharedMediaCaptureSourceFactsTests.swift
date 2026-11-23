import Foundation
@testable import Merian
import Testing

@Suite("Captured source context survives draft restoration")
struct SharedMediaCaptureSourceFactsTests {
    @Test func importedUnknownFactsStayUnknownAfterRoundTrip() throws {
        let added = Date(timeIntervalSince1970: 100)
        let facts = SharedMediaCaptureSourceFacts(addedAt: added, context: nil)
        let restored = try JSONDecoder().decode(SharedMediaCaptureSourceFacts.self, from: JSONEncoder().encode(facts))
        try restored.validate()
        #expect(restored == facts && restored.addedAt == added)
        #expect(restored.environmentContext.location == nil && restored.environmentContext.captureDate == nil)
        #expect(restored.telemetry.timestamp == nil && restored.telemetry.gpsElevation == nil)
    }

    @Test func capturedTimeIsNotReplacedByRestorationTime() throws {
        let captured = Date(timeIntervalSince1970: 100), added = Date(timeIntervalSince1970: 200)
        let context = EnvironmentContext(location: nil, locationName: nil, weatherCondition: nil,
            weatherTemperature: nil, captureDate: captured)
        let facts = SharedMediaCaptureSourceFacts(addedAt: added, context: context, distance: 2, zoom: 1.5)
        try facts.validate()
        #expect(facts.environmentContext.captureDate == captured)
        #expect(facts.telemetry.timestamp == DateUtilities.iso8601Formatter.string(from: captured))
        #expect(facts.telemetry.subjectDistanceInMeters == 2 && facts.telemetry.zoomFactor == 1.5)
    }

    @Test func invalidNumericContextCannotEnterJournal() {
        #expect(throws: (any Error).self) {
            try SharedMediaCaptureSourceFacts(addedAt: .init(timeIntervalSince1970: .infinity), context: nil).validate()
        }
        #expect(throws: (any Error).self) {
            try SharedMediaCaptureSourceFacts(addedAt: .distantPast, context: nil, distance: -1).validate()
        }
        #expect(throws: (any Error).self) {
            try SharedMediaCaptureSourceFacts(addedAt: .distantPast, context: nil, zoom: 0).validate()
        }
    }
}

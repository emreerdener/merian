import CoreLocation
import XCTest

@testable import Merian

final class CaptureSubmissionEnvironmentContextGraceTests: XCTestCase {
    func testCompletedContextWinsGraceRaceAndPreservesTelemetryFields() async {
        let timestamp = Date(timeIntervalSince1970: 1_750_000_000)
        let context = EnvironmentContext(
            location: CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 30.2672,
                    longitude: -97.7431
                ),
                altitude: 142,
                horizontalAccuracy: 4,
                verticalAccuracy: 6,
                timestamp: timestamp
            ),
            locationName: "Zilker Park",
            weatherCondition: "Clear",
            weatherTemperature: 75,
            captureDate: timestamp
        )
        let task = Task {
            CaptureSubmissionContextSnapshot(context)
        }

        let result = await CaptureSubmissionEnvironmentContextGrace.resolve(
            from: task,
            graceMilliseconds: 100
        )
        let resolved = result.snapshot?.makeEnvironmentContext()

        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(resolved?.location?.coordinate.latitude, 30.2672)
        XCTAssertEqual(resolved?.location?.coordinate.longitude, -97.7431)
        XCTAssertEqual(resolved?.location?.altitude, 142)
        XCTAssertEqual(resolved?.location?.verticalAccuracy, 6)
        XCTAssertEqual(resolved?.location?.timestamp, timestamp)
        XCTAssertEqual(resolved?.locationName, "Zilker Park")
        XCTAssertEqual(resolved?.weatherCondition, "Clear")
        XCTAssertEqual(resolved?.weatherTemperature, 75)
        XCTAssertEqual(resolved?.captureDate, timestamp)
    }

    func testTimeoutReturnsOnceWhileContextContinuesForLateMerge() async {
        let context = EnvironmentContext(location: nil, locationName: "Creek")
        let task = Task {
            try? await Task.sleep(for: .milliseconds(50))
            return CaptureSubmissionContextSnapshot(context)
        }

        let result = await CaptureSubmissionEnvironmentContextGrace.resolve(
            from: task,
            graceMilliseconds: 1
        )

        XCTAssertTrue(result.timedOut)
        XCTAssertNil(result.snapshot)
        let lateSnapshot = await task.value
        XCTAssertEqual(
            lateSnapshot.makeEnvironmentContext().locationName,
            "Creek"
        )
    }

    func testMissingTaskDoesNotReportTimeout() async {
        let result = await CaptureSubmissionEnvironmentContextGrace.resolve(
            from: nil,
            graceMilliseconds: 1
        )

        XCTAssertFalse(result.timedOut)
        XCTAssertNil(result.snapshot)
    }
}

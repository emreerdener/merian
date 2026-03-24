import XCTest
import CoreLocation
@testable import merian

final class CaptureTelemetryTests: XCTestCase {
    
    func testCaptureTelemetryInitialization_withValidEnvironmentContext() {
        // Arrange: Setup a mock CLLocation with strong vertical accuracy (<25m)
        let mockCoordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let mockLocation = CLLocation(
            coordinate: mockCoordinate,
            altitude: 15.0,
            horizontalAccuracy: 10.0,
            verticalAccuracy: 20.0,
            timestamp: Date()
        )
        
        let context = EnvironmentContext(
            location: mockLocation,
            locationName: "San Francisco",
            weatherCondition: "Clear",
            weatherTemperature: 72.5
        )
        
        // Act
        let telemetry = CaptureTelemetry(from: context, distance: 3.5)
        
        // Assert
        XCTAssertEqual(telemetry.subjectDistanceInMeters, 3.5)
        XCTAssertEqual(telemetry.gpsLatitude, 37.7749)
        XCTAssertEqual(telemetry.gpsLongitude, -122.4194)
        XCTAssertEqual(telemetry.gpsElevation, 15.0, "Elevation should be mapped natively when verticalAccuracy is between 0 and 25")
        XCTAssertEqual(telemetry.locationName, "San Francisco")
        XCTAssertEqual(telemetry.weatherCondition, "Clear")
        XCTAssertEqual(telemetry.weatherTemperatureF, 72.5)
        XCTAssertNil(telemetry.timeOfDay)
        XCTAssertNotNil(telemetry.timestamp)
    }
    
    func testCaptureTelemetryInitialization_withInaccurateElevation() {
        // Arrange: Vertical accuracy > 25 indicates unreliable elevation telemetry
        let mockCoordinate = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let mockLocation = CLLocation(
            coordinate: mockCoordinate,
            altitude: 15.0,
            horizontalAccuracy: 10.0,
            verticalAccuracy: 30.0, 
            timestamp: Date()
        )
        
        let context = EnvironmentContext(
            location: mockLocation,
            locationName: "San Francisco",
            weatherCondition: "Fog",
            weatherTemperature: 55.0
        )
        
        // Act
        let telemetry = CaptureTelemetry(from: context, distance: nil)
        
        // Assert: Explicitly confirm that unreliable hardware data is wiped and not synced to Gemini
        XCTAssertNil(telemetry.gpsElevation, "Elevation must natively drop to nil if verticalAccuracy is > 25 to prevent corrupting inference context")
        XCTAssertEqual(telemetry.gpsLatitude, 37.7749)
        XCTAssertEqual(telemetry.weatherCondition, "Fog")
    }
}

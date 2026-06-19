import Testing
import CoreLocation
import Foundation

@testable import Merian

@MainActor
struct EnvironmentContextManagerTests {
    
    @Test func testDeferredContextBindsStaticCoordinatesSuccessfully() async throws {
        // Arrange: Mock explicit coordinates
        let mockLocation = CLLocation(latitude: 40.7812, longitude: -73.9665)
        
        let manager = EnvironmentContextManager.shared
        manager.isAuthorized = true
        
        // Act: Execute deferred pipeline explicitly mapping preLocked hardware limits
        let context = await manager.fetchDeferredContext(preLockedLocation: mockLocation)
        
        // Assert: Ensure payload boundaries extract accurately into localized properties
        #expect(context.location?.coordinate.latitude == 40.7812, "Deferred context MUST lock latitude securely")
        #expect(context.location?.coordinate.longitude == -73.9665, "Deferred context MUST lock longitude securely")
        
        // NOTE: WeatherKit will natively drop `weatherTemperature` within simulators unless entitled correctly, so testing dynamic injection boundaries isn't isolated. 
        // We guarantee the context wrapper itself builds the metadata format correctly.
    }
    
    @Test func testUnauthorizedLocationRejectsContextBoundaries() async throws {
        // Arrange
        let manager = EnvironmentContextManager.shared
        manager.isAuthorized = false // Explicitly reject bounds
        
        // Act
        let context = await manager.fetchDeferredContext()
        
        // Assert: Enforce zero-PII fallback natively without crashes
        #expect(context.location == nil, "Environment mappings MUST completely strip PII location footprint if permissions are aggressively revoked")
        #expect(context.weatherTemperature == nil, "Environment mappings cannot attempt Weather API resolution without physical coordinate limits")
        #expect(context.locationName == nil, "Reverse Geocode must aggressively halt if permissions are denied")
    }

    @Test func testPassiveRegionResolutionRequiresExistingAuthorization() {
        #expect(EnvironmentContextManager.allowsPassiveRegionResolution(for: .authorizedWhenInUse))
        #expect(EnvironmentContextManager.allowsPassiveRegionResolution(for: .authorizedAlways))
        #expect(!EnvironmentContextManager.allowsPassiveRegionResolution(for: .notDetermined))
        #expect(!EnvironmentContextManager.allowsPassiveRegionResolution(for: .denied))
        #expect(!EnvironmentContextManager.allowsPassiveRegionResolution(for: .restricted))
    }

    @Test func testRegionIdentifierNormalizationTrimsAndUppercasesISOCode() {
        #expect(EnvironmentContextManager.normalizedRegionIdentifier(" us ") == "US")
        #expect(EnvironmentContextManager.normalizedRegionIdentifier("ca") == "CA")
        #expect(EnvironmentContextManager.normalizedRegionIdentifier("   ") == nil)
        #expect(EnvironmentContextManager.normalizedRegionIdentifier(nil) == nil)
    }
}

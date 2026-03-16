import XCTest
@testable import Merian

final class AppTelemetryTests: XCTestCase {

    func testAppTelemetryInvocation() {
        // AppTelemetry strictly writes non-PII events to a shared memory space without explicit return states.
        // The most critical bounds here are to ensure calling every wrapper logic doesn't throw a fatalError/crash the main threads
        
        AppTelemetry.trackScan(isPro: true)
        AppTelemetry.trackScan(isPro: false)
        
        AppTelemetry.trackNewDiscovery(isPro: true)
        AppTelemetry.trackNewDiscovery(isPro: false)
        
        AppTelemetry.trackPaywallImpression()
        AppTelemetry.trackThermalThrottling(fpsLimit: 15)
        AppTelemetry.trackError("UnitTestTrigger")
    }
}

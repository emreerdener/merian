import XCTest
@testable import Merian

@MainActor
final class CircuitBreakerManagerTests: XCTestCase {

    var circuitBreaker: CircuitBreakerManager!

    override func setUp() async throws {
        circuitBreaker = CircuitBreakerManager.shared
        // Reset state explicitly
        circuitBreaker.recordSuccess()
    }

    override func tearDown() async throws {
        circuitBreaker.recordSuccess()
        circuitBreaker = nil
    }

    func testCircuitTripsAfterThreshold() {
        XCTAssertFalse(circuitBreaker.isCircuitTripped)
        
        // Single failure should not trip
        circuitBreaker.recordFailure()
        XCTAssertFalse(circuitBreaker.isCircuitTripped)
        
        // Threshold is 3 failures based on the implementation
        circuitBreaker.recordFailure()
        XCTAssertFalse(circuitBreaker.isCircuitTripped)
        
        circuitBreaker.recordFailure()
        XCTAssertTrue(circuitBreaker.isCircuitTripped)
    }

    func testCircuitResetsOnSuccess() {
        // Force a trip
        circuitBreaker.recordFailure()
        circuitBreaker.recordFailure()
        circuitBreaker.recordFailure()
        XCTAssertTrue(circuitBreaker.isCircuitTripped)
        
        // A single success forces the cooldown lock off
        circuitBreaker.recordSuccess()
        XCTAssertFalse(circuitBreaker.isCircuitTripped)
    }
}

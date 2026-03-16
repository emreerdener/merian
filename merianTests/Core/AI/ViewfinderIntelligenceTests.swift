import XCTest
@testable import Merian

@MainActor
final class ViewfinderIntelligenceTests: XCTestCase {

    var vui: ViewfinderIntelligence!

    override func setUp() async throws {
        vui = ViewfinderIntelligence.shared
        // Reset pause state to test baseline
        vui.pauseAnalysis(for: 0)
        try await Task.sleep(nanoseconds: 10_000_000)
    }

    override func tearDown() async throws {
        vui.pauseAnalysis(for: 0)
        vui = nil
    }

    func testDistanceHeuristic() async throws {
        // High distance should trigger move closer
        vui.analyze(brightness: 0.5, distance: 3.0)
        // Let the detached task execute
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(vui.currentHint, .moveCloser)
        XCTAssertFalse(vui.isOptimal)
    }

    func testBrightnessHeuristic() async throws {
        // Very low brightness should trigger too dark
        vui.analyze(brightness: 0.1, distance: 1.0)
        // Let the detached task execute
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(vui.currentHint, .tooDark)
        XCTAssertFalse(vui.isOptimal)
    }

    func testOptimalHeuristic() async throws {
        // Good brightness and distance
        vui.analyze(brightness: 0.8, distance: 1.5)
        // Let the detached task execute
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(vui.currentHint, .optimal)
        XCTAssertTrue(vui.isOptimal)
    }

    func testPauseAnalysis() async throws {
        // Pause for long enough that analysis stops
        vui.pauseAnalysis(for: 2.0)
        
        // Try triggering a bad frame
        vui.analyze(brightness: 0.1, distance: 4.0)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // State should remain optimal due to the pause block
        XCTAssertEqual(vui.currentHint, .optimal)
        XCTAssertTrue(vui.isOptimal)
    }
}

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
        vui.analyze(brightness: 0.5, distance: 3.5, lumaStdDev: 50.0)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(vui.currentHint, .moveCloser)
        XCTAssertFalse(vui.isOptimal)
    }

    func testTooCloseHeuristic() async throws {
        vui.analyze(brightness: 0.5, distance: 0.05, lumaStdDev: 50.0)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(vui.currentHint, .tooClose)
        XCTAssertFalse(vui.isOptimal)
    }

    func testBrightnessHeuristic() async throws {
        vui.analyze(brightness: 0.1, distance: 1.0, lumaStdDev: 50.0)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(vui.currentHint, .tooDark)
        XCTAssertFalse(vui.isOptimal)
    }

    func testLowAverageBrightnessWithUsableMidtonesIsOptimal() async throws {
        vui.analyze(brightness: 0.18, distance: 1.0, lumaStdDev: 50.0, wellLitPixelRatio: 0.55)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(vui.currentHint, .optimal)
        XCTAssertTrue(vui.isOptimal)
    }

    func testLowAverageBrightnessMostlyUnderlitIsTooDark() async throws {
        vui.analyze(brightness: 0.18, distance: 1.0, lumaStdDev: 50.0, wellLitPixelRatio: 0.25)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(vui.currentHint, .tooDark)
        XCTAssertFalse(vui.isOptimal)
    }

    func testTooBrightHeuristic() async throws {
        vui.analyze(brightness: 0.95, distance: 1.0, lumaStdDev: 50.0)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(vui.currentHint, .tooBright)
        XCTAssertFalse(vui.isOptimal)
    }

    func testHoldStillHeuristic() async throws {
        vui.analyze(brightness: 0.5, distance: 1.0, lumaStdDev: 10.0)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(vui.currentHint, .holdStill)
        XCTAssertFalse(vui.isOptimal)
    }

    func testOptimalHeuristic() async throws {
        vui.analyze(brightness: 0.5, distance: 1.5, lumaStdDev: 50.0)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(vui.currentHint, .optimal)
        XCTAssertTrue(vui.isOptimal)
    }

    func testPauseAnalysis() async throws {
        vui.pauseAnalysis(for: 2.0)
        vui.analyze(brightness: 0.1, distance: 4.0, lumaStdDev: 5.0)
        try await Task.sleep(nanoseconds: 100_000_000)
        // State should remain optimal due to the pause block
        XCTAssertEqual(vui.currentHint, .optimal)
        XCTAssertTrue(vui.isOptimal)
    }
}

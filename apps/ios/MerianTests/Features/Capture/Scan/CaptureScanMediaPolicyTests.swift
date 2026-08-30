import XCTest

@testable import Merian

final class CaptureScanMediaPolicyTests: XCTestCase {
    func testFiveFrameSamplingUsesTenThroughNinetyPercent() {
        assertEqualArrays(
            CaptureScanVideoFrameSamplingPolicy.sampleOffsets(
                duration: 5,
                sampleCount: 5
            ),
            [0.5, 1.5, 2.5, 3.5, 4.5],
            accuracy: 0.000_001
        )
    }

    func testSamplingClampsVeryShortVideosToValidOffsets() {
        assertEqualArrays(
            CaptureScanVideoFrameSamplingPolicy.sampleOffsets(
                duration: 0,
                sampleCount: 5
            ),
            [0.05, 0.05, 0.05, 0.05, 0.05],
            accuracy: 0.000_001
        )
    }

    func testSamplingHandlesOneOrZeroRequestedFrames() {
        XCTAssertEqual(
            CaptureScanVideoFrameSamplingPolicy.sampleOffsets(
                duration: 4,
                sampleCount: 1
            ),
            [2]
        )
        XCTAssertTrue(
            CaptureScanVideoFrameSamplingPolicy.sampleOffsets(
                duration: 4,
                sampleCount: 0
            ).isEmpty
        )
    }

    func testPlaybackPresentationDescribesSourceAndCompressionRatio() {
        let compressed = PreparedCaptureScanVideoPlayback(
            fileURL: URL(fileURLWithPath: "/tmp/clip.mp4"),
            isCompressed: true,
            originalBytes: 400,
            playbackBytes: 100,
            preparationDuration: 0.2
        )
        let emptyOriginal = PreparedCaptureScanVideoPlayback(
            fileURL: URL(fileURLWithPath: "/tmp/original.mp4"),
            isCompressed: false,
            originalBytes: 0,
            playbackBytes: 0,
            preparationDuration: 0
        )

        XCTAssertEqual(compressed.sourceDescription, "compressed")
        XCTAssertEqual(compressed.compressionRatio, 0.25)
        XCTAssertEqual(emptyOriginal.sourceDescription, "original")
        XCTAssertEqual(emptyOriginal.compressionRatio, 1)
    }
}

private extension XCTestCase {
    func assertEqualArrays(
        _ expression1: [Double],
        _ expression2: [Double],
        accuracy: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            expression1.count,
            expression2.count,
            file: file,
            line: line
        )
        for (actual, expected) in zip(expression1, expression2) {
            XCTAssertEqual(
                actual,
                expected,
                accuracy: accuracy,
                file: file,
                line: line
            )
        }
    }
}

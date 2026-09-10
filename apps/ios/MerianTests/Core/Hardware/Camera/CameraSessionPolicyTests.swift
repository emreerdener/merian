import AVFoundation
@testable import Merian
import XCTest

final class CameraSessionPolicyTests: XCTestCase {
    func testZoomConfigurationCapsRangeAndFiltersOpticalStops() {
        let configuration = CameraSessionPolicy.zoomConfiguration(
            maximumAvailableFactor: 189,
            switchOverFactors: [2, 6, 20],
            currentFactor: 2
        )

        XCTAssertEqual(configuration.maximumFactor, 15)
        XCTAssertEqual(configuration.opticalStops, [1, 2, 6])
        XCTAssertEqual(configuration.currentFactor, 2)
    }

    func testZoomClampingKeepsUIAndHardwareBoundsIndependent() {
        let presentation = CameraSessionPolicy.presentationZoomFactor(
            requestedFactor: 20,
            maximumFactor: 15
        )
        let hardware = CameraSessionPolicy.hardwareZoomFactor(
            presentationFactor: presentation,
            minimumFactor: 2,
            maximumFactor: 10
        )

        XCTAssertEqual(presentation, 15)
        XCTAssertEqual(hardware, 10)
        XCTAssertEqual(
            CameraSessionPolicy.presentationZoomFactor(
                requestedFactor: -5,
                maximumFactor: 15
            ),
            1
        )
    }

    func testFrameDurationClampsToSupportedRange() {
        let minimum = CMTime(value: 1, timescale: 60)
        let maximum = CMTime(value: 1, timescale: 15)

        XCTAssertEqual(
            CameraSessionPolicy.clampedFrameDuration(
                requestedDuration: CMTime(value: 1, timescale: 120),
                minimumDuration: minimum,
                maximumDuration: maximum
            ),
            minimum
        )
        XCTAssertEqual(
            CameraSessionPolicy.clampedFrameDuration(
                requestedDuration: CMTime(value: 1, timescale: 5),
                minimumDuration: minimum,
                maximumDuration: maximum
            ),
            maximum
        )
        let supported = CMTime(value: 1, timescale: 30)
        XCTAssertEqual(
            CameraSessionPolicy.clampedFrameDuration(
                requestedDuration: supported,
                minimumDuration: minimum,
                maximumDuration: maximum
            ),
            supported
        )
    }

    func testFrameDurationUpdateOrderProtectsDeviceConstraints() {
        XCTAssertTrue(
            CameraSessionPolicy.shouldSetMaximumDurationFirst(
                targetDuration: CMTime(value: 1, timescale: 30),
                currentMinimumDuration: CMTime(value: 1, timescale: 60)
            )
        )
        XCTAssertFalse(
            CameraSessionPolicy.shouldSetMaximumDurationFirst(
                targetDuration: CMTime(value: 1, timescale: 60),
                currentMinimumDuration: CMTime(value: 1, timescale: 30)
            )
        )
    }
}

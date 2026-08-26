import Foundation
import XCTest

@testable import Merian

final class ExploreMapPresentationTests: XCTestCase {
    func testDiscoveriesLabelUsesSingularAndPluralCopy() {
        XCTAssertEqual(
            ExploreMapPresentation.discoveriesInViewLabel(count: 1),
            "1 discovery in view"
        )
        XCTAssertEqual(
            ExploreMapPresentation.discoveriesInViewLabel(count: 2),
            "2 discoveries in view"
        )
    }

    func testCameraPolicyPreservesThumbnailThresholdAndClampsZoomRange() {
        let thresholdDelta = 360 / pow(2, ExploreMapCameraPolicy.thumbnailZoomLevel)

        XCTAssertEqual(
            ExploreMapCameraPolicy.zoomLevel(longitudeDelta: thresholdDelta),
            ExploreMapCameraPolicy.thumbnailZoomLevel,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            ExploreMapCameraPolicy.zoomLevel(longitudeDelta: 720),
            0
        )
        XCTAssertEqual(
            ExploreMapCameraPolicy.zoomLevel(longitudeDelta: 0),
            ExploreMapCameraPolicy.maximumZoomLevel
        )
    }
}

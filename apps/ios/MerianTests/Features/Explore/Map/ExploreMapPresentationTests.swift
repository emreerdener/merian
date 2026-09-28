import Foundation
import MapKit
import XCTest

@testable import Merian

final class ExploreMapPresentationTests: XCTestCase {
    func testLocateDefaultsToOneKilometerFromWideOrMissingViewport() {
        let location = locateFixture(accuracy: 10)
        let city = MKCoordinateRegion(
            center: location.coordinate, latitudinalMeters: 50_000, longitudinalMeters: 50_000
        )
        for current in [nil, city] {
            let region = ExploreMapCameraPolicy.locateRegion(for: location, currentRegion: current)
            XCTAssertEqual(region.center.latitude, location.coordinate.latitude)
            XCTAssertEqual(region.center.longitude, location.coordinate.longitude)
            XCTAssertEqual(widthInMeters(region), 1_000, accuracy: 20)
        }
    }

    func testLocatePreservesCloserZoomAcrossLatitudes() {
        let current = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 60, longitude: 1),
            latitudinalMeters: 250, longitudinalMeters: 250
        )
        let region = ExploreMapCameraPolicy.locateRegion(
            for: locateFixture(accuracy: 10), currentRegion: current
        )
        XCTAssertEqual(widthInMeters(region), 250, accuracy: 5)
    }

    func testLocateWidensForAccuracyEvenFromCloseZoom() {
        let current = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            latitudinalMeters: 250, longitudinalMeters: 250
        )
        let region = ExploreMapCameraPolicy.locateRegion(
            for: locateFixture(accuracy: 2_000), currentRegion: current
        )
        XCTAssertEqual(widthInMeters(region), 4_000, accuracy: 80)
    }

    func testLocateIgnoresUnavailableAccuracyAndInvalidViewportWidth() {
        let invalid = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            span: MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0)
        )
        for accuracy in [-1.0, .nan, .infinity] {
            let region = ExploreMapCameraPolicy.locateRegion(
                for: locateFixture(accuracy: accuracy), currentRegion: invalid
            )
            XCTAssertEqual(widthInMeters(region), 1_000, accuracy: 20)
        }
    }

    private func locateFixture(accuracy: CLLocationAccuracy) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: -1,
            timestamp: Date(timeIntervalSince1970: 0)
        )
    }

    private func widthInMeters(_ region: MKCoordinateRegion) -> CLLocationDistance {
        let halfWidth = region.span.longitudeDelta / 2
        return CLLocation(
            latitude: region.center.latitude, longitude: region.center.longitude - halfWidth
        ).distance(from: CLLocation(
            latitude: region.center.latitude, longitude: region.center.longitude + halfWidth
        ))
    }

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

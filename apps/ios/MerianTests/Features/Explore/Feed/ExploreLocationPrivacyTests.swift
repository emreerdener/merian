import XCTest

@testable import Merian

@MainActor
final class ExploreLocationPrivacyTests: XCTestCase {
    func testDisplayLabelKeepsCityAndStateFromExactAddress() {
        XCTAssertEqual(
            ExploreLocationPrivacy.displayLabel(from: "123 Main St, Austin, TX, United States"),
            "Austin, TX"
        )
        XCTAssertEqual(
            ExploreLocationPrivacy.displayLabel(from: "Austin, Travis County, TX, United States"),
            "Austin, TX"
        )
        XCTAssertEqual(
            ExploreLocationPrivacy.displayLabel(from: "123 Main St, Austin, TX 78701, United States"),
            "Austin, TX"
        )
        XCTAssertEqual(
            ExploreLocationPrivacy.displayLabel(from: "123 Main St, Austin, Texas 78701, United States"),
            "Austin, TX"
        )
        XCTAssertEqual(
            ExploreLocationPrivacy.displayLabel(from: "123 Main St, Austin, TX 78701 United States"),
            "Austin, TX"
        )
    }

    func testDisplayLabelFallsBackToStateForLandmarkAndSingleState() {
        XCTAssertEqual(ExploreLocationPrivacy.displayLabel(from: "Central Park, NY"), "New York")
        XCTAssertEqual(ExploreLocationPrivacy.displayLabel(from: "Little Sarasota Bay, FL"), "Florida")
        XCTAssertEqual(ExploreLocationPrivacy.displayLabel(from: "FL"), "Florida")
        XCTAssertEqual(ExploreLocationPrivacy.displayLabel(from: "California"), "California")
    }

    func testDisplayLabelKeepsSafeCityOnlyHistoricalLabels() {
        XCTAssertEqual(ExploreLocationPrivacy.displayLabel(from: "Austin"), "Austin")
    }

    func testDisplayLabelSuppressesCoordinatesAndSmallSiteLabels() {
        XCTAssertNil(ExploreLocationPrivacy.displayLabel(from: "30.2672, -97.7431"))
        XCTAssertNil(ExploreLocationPrivacy.displayLabel(from: "Zilker Park"))
        XCTAssertNil(ExploreLocationPrivacy.displayLabel(from: "Little Sarasota Bay"))
    }
}

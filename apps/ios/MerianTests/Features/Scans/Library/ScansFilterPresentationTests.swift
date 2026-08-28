import XCTest

@testable import Merian

final class ScansFilterPresentationTests: XCTestCase {
    func testFormattedTitleNormalizesWireAndStoredLabels() {
        XCTAssertEqual(
            ScansFilterPresentation.formattedTitle("critically_endangered"),
            "Critically endangered"
        )
        XCTAssertEqual(
            ScansFilterPresentation.formattedTitle("needs-review"),
            "Needs review"
        )
        XCTAssertEqual(
            ScansFilterPresentation.formattedTitle("  already   spaced  "),
            "Already spaced"
        )
        XCTAssertEqual(ScansFilterPresentation.formattedTitle(""), "")
    }

    func testSelectedSummaryHandlesEmptySingleAndMultipleValues() {
        XCTAssertEqual(
            ScansFilterPresentation.selectedSummary(
                Set<String>(),
                title: { $0 }
            ),
            "None"
        )
        XCTAssertEqual(
            ScansFilterPresentation.selectedSummary(
                ["needs_review"],
                title: { $0 }
            ),
            "Needs review"
        )
        XCTAssertEqual(
            ScansFilterPresentation.selectedSummary(
                ["first", "second"],
                title: { $0 }
            ),
            "2 selected"
        )
    }

    func testGroupedSummariesPreserveFilterPresentationPolicy() {
        var filters = ScanLibraryFilters()
        XCTAssertEqual(ScansFilterPresentation.dateSummary(filters), "None")
        XCTAssertEqual(
            ScansFilterPresentation.naturalistSummary(filters),
            "None"
        )
        XCTAssertEqual(
            ScansFilterPresentation.taxonomySummary(filters),
            "None"
        )

        filters.dateFilters = [.custom]
        filters.isInvasive = true
        filters.taxonomyClasses = ["aves_class"]
        XCTAssertEqual(
            ScansFilterPresentation.dateSummary(filters),
            "Custom range"
        )
        XCTAssertEqual(
            ScansFilterPresentation.naturalistSummary(filters),
            "Invasive"
        )
        XCTAssertEqual(
            ScansFilterPresentation.taxonomySummary(filters),
            "Aves class"
        )

        filters.hazardTypes = ["toxic"]
        filters.taxonomyOrders = ["passeriformes"]
        XCTAssertEqual(
            ScansFilterPresentation.naturalistSummary(filters),
            "2 selected"
        )
        XCTAssertEqual(
            ScansFilterPresentation.taxonomySummary(filters),
            "2 selected"
        )
    }

    func testTaxonomyOptionVisibilityRequiresAtLeastOneDimension() {
        XCTAssertFalse(
            ScansFilterPresentation.hasTaxonomyOptions(
                ScanLibraryFilterOptions()
            )
        )
        XCTAssertTrue(
            ScansFilterPresentation.hasTaxonomyOptions(
                ScanLibraryFilterOptions(taxonomyGenera: ["Danaus"])
            )
        )
    }
}

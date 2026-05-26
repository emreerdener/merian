import XCTest
@testable import Merian

final class ExploreHashtagSuggestionTests: XCTestCase {
    func testSuggestsSpeciesTaxonomyLocationAndFieldNoteTags() {
        let context = ExploreHashtagSuggestionContext(
            speciesName: "Red Shiner",
            scientificName: "Cyprinella lutrensis",
            publicLocationLabel: "Austin, TX",
            fieldNotes: "Schooling in a shallow creek after rain",
            ecologyType: "freshwater",
            taxonomyKingdom: "Animalia",
            taxonomyClass: "Actinopterygii",
            habitatDescription: "Freshwater streams and pools",
            colors: ["red"],
            groupTags: ["fish"],
            semanticTags: ["stream"],
            imageQualityScore: 91
        )

        let suggestions = ExploreHashtagSuggestionEngine.suggestions(for: context)

        XCTAssertTrue(suggestions.contains("redshiner"))
        XCTAssertTrue(suggestions.contains("freshwaterfish"))
        XCTAssertTrue(suggestions.contains("austintx"))
        XCTAssertTrue(suggestions.contains("creeklife"))
        XCTAssertFalse(suggestions.contains("featured"))
    }

    func testSelectedTagsAreNotSuggestedAgainAndSlotsAreRespected() {
        let context = ExploreHashtagSuggestionContext(
            speciesName: "Monarch Butterfly",
            scientificName: "Danaus plexippus",
            publicLocationLabel: "Chicago, IL",
            fieldNotes: "Pollinator on milkweed flowers",
            taxonomyClass: "Insecta",
            groupTags: ["pollinator", "insect"]
        )

        let suggestions = ExploreHashtagSuggestionEngine.suggestions(
            for: context,
            selectedHashtags: ["monarchbutterfly", "insects", "milkweed", "chicagoil"]
        )

        XCTAssertFalse(suggestions.contains("monarchbutterfly"))
        XCTAssertLessThanOrEqual(suggestions.count, 4)
        XCTAssertTrue(suggestions.contains("pollinators"))
    }

    func testInputNormalizationMatchesPublishingLimit() {
        let tags = ExploreHashtagSuggestionEngine.normalizedInputTags(
            from: "#CityBioBlitz, #Red-Shiner #Red_Shiner #featured #fish #freshwater #extra"
        )

        XCTAssertEqual(tags, ["citybioblitz", "redshiner", "red_shiner", "fish", "freshwater"])
    }
}

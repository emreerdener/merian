@testable import Merian
import Testing

@Suite("Species Common Name Presentation")
struct SpeciesCommonNamePresentationTests {
    @Test func normalizationRetainsExistingFuzzyComparisonRules() {
        #expect(
            SpeciesCommonNamePresentation.normalizationKey(
                for: "Lamb's-ear"
            ) == "lambsear"
        )
        #expect(
            SpeciesCommonNamePresentation.normalizationKey(
                for: "Lamb’s ears"
            ) == "lambsear"
        )
    }

    @Test func fuzzyDeduplicationPreservesFirstSpellingAndOrder() {
        let values = [
            "Hare's Foot Inkcap",
            "Monarch",
            "Hare’s-foot Inkcaps",
            "MONARCHS",
            "Viceroy"
        ]

        #expect(
            SpeciesCommonNamePresentation.removingFuzzyDuplicates(from: values)
                == ["Hare's Foot Inkcap", "Monarch", "Viceroy"]
        )
    }
}

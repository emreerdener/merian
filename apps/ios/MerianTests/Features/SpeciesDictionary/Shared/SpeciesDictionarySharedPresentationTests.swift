import XCTest

@testable import Merian

final class SpeciesDictionarySharedPresentationTests: XCTestCase {
    func testRouteNormalizesCanonicalAndSyntheticIdentities() {
        let speciesID = "1cf79982-e5ee-4e3d-8d65-274527e6ae01"
        let route = SpeciesDictionaryRoute(
            scientificName: "  Testus   floridus ",
            speciesId: " \(speciesID.uppercased()) ",
            entryPoint: .exploreDetailSimilarSpecies
        )
        let defaultRoute = SpeciesDictionaryRoute(
            scientificName: "Testus floridus"
        )
        let legacyRoute = SpeciesDictionaryRoute(
            scientificName: "Testus floridus",
            speciesId: "external:testus%20floridus"
        )

        XCTAssertEqual(route.speciesId, speciesID)
        XCTAssertEqual(route.scientificName, "Testus floridus")
        XCTAssertEqual(route.entryPoint, .exploreDetailSimilarSpecies)
        XCTAssertEqual(defaultRoute.entryPoint, .unknown)
        XCTAssertNil(legacyRoute.speciesId)
        XCTAssertEqual(legacyRoute.id, "Testus floridus")
    }

    func testTaxonomyAdapterRejectsEmptyContent() {
        let populated = SpeciesDictionaryTaxonomy(
            kingdom: "Animalia",
            phylum: nil,
            className: nil,
            order: "Lepidoptera",
            family: nil,
            genus: "Danaus"
        )
        let empty = SpeciesDictionaryTaxonomy(
            kingdom: " ",
            phylum: nil,
            className: nil,
            order: nil,
            family: nil,
            genus: nil
        )

        XCTAssertEqual(
            SpeciesDictionaryTaxonomyPresentation.data(from: populated)?.genus,
            "Danaus"
        )
        XCTAssertNil(SpeciesDictionaryTaxonomyPresentation.data(from: empty))
    }

    func testReferenceImagePresentationIsCrossSurfaceAndSourceAware() {
        let naturebook = SpeciesDictionaryReferenceImage(
            url: "https://media.merian.app/public_uploads/pro/test.webp",
            source: .merian,
            license: "Used with permission via Naturebook",
            attribution: "Ayla E.",
            authorUsername: " @ayla ",
            width: nil,
            height: nil
        )
        let naturebookWithoutUsername = SpeciesDictionaryReferenceImage(
            url: "https://media.merian.app/public_uploads/pro/anonymous.webp",
            source: .merian,
            license: "Used with permission via Naturebook",
            attribution: "Ayla E.",
            width: nil,
            height: nil
        )
        let wikipedia = SpeciesDictionaryReferenceImage(
            url: "https://upload.wikimedia.org/test.jpg",
            source: .wikipedia,
            license: "CC BY-SA 4.0",
            attribution: "Example Photographer",
            width: 1200,
            height: 800
        )

        XCTAssertEqual(naturebook.source.label, "Naturebook")
        XCTAssertEqual(naturebook.source.rawValue, "merian")
        XCTAssertEqual(naturebook.naturebookAuthorUsername, "ayla")
        XCTAssertEqual(
            naturebook.fullscreenAttributionLabel,
            "@ayla · Naturebook"
        )
        XCTAssertEqual(
            naturebookWithoutUsername.fullscreenAttributionLabel,
            "Naturebook"
        )
        XCTAssertEqual(
            wikipedia.fullscreenAttributionLabel,
            "Example Photographer · CC BY-SA 4.0 · Wikipedia"
        )
    }
}

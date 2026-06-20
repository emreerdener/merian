import Foundation
import Testing
@testable import Merian

@Suite("Community Identification Models")
struct CommunityIdentificationModelsTests {
    @Test func taxonPathRelationshipClassifiesExactDescendantAncestorAndConflict() {
        let family = CommunityTaxonSearchResult(
            taxonId: "taxon-family",
            commonName: "Hawks",
            scientificName: "Accipitridae",
            rank: "family",
            path: "animalia.chordata.aves.accipitridae",
            speciesId: nil
        )
        let species = CommunityTaxonSearchResult(
            taxonId: "taxon-species",
            commonName: "Red-tailed Hawk",
            scientificName: "Buteo jamaicensis",
            rank: "species",
            path: "animalia.chordata.aves.accipitridae.buteo.buteo_jamaicensis",
            speciesId: "species-red-tailed-hawk"
        )
        let sibling = CommunityTaxonSearchResult(
            taxonId: "taxon-vulture",
            commonName: "Turkey Vulture",
            scientificName: "Cathartes aura",
            rank: "species",
            path: "animalia.chordata.aves.cathartidae.cathartes.cathartes_aura",
            speciesId: "species-turkey-vulture"
        )

        #expect(species.relationship(to: species.path) == .exact)
        #expect(species.relationship(to: family.path) == .descendant)
        #expect(family.relationship(to: species.path) == .ancestor)
        #expect(sibling.relationship(to: species.path) == .conflict)
        #expect(species.relationship(to: nil) == .conflict)
    }

    @Test func taxonDisplayFallsBackToScientificName() {
        #expect(CommunityTaxonDisplay.name(commonName: "  ", scientificName: "Buteo jamaicensis") == "Buteo jamaicensis")
        #expect(CommunityTaxonDisplay.rankTitle("genus") == "Genus")
        #expect(CommunityTaxonDisplay.rankTitle(nil) == "Taxon")
    }
}

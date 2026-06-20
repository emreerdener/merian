import Foundation
import Testing
@testable import Merian

@Suite("Community Identification Models")
struct CommunityIdentificationModelsTests {
    @Test func taxonPathRelationshipClassifiesExactDescendantAncestorAndConflict() {
        let family = CommunityTaxonSearchResult(
            taxonId: "taxon-family",
            taxonomyVersionId: "taxonomy-v1",
            commonName: "Hawks",
            scientificName: "Accipitridae",
            rank: "family",
            path: "animalia.chordata.aves.accipitridae",
            speciesId: nil
        )
        let species = CommunityTaxonSearchResult(
            taxonId: "taxon-species",
            taxonomyVersionId: "taxonomy-v1",
            commonName: "Red-tailed Hawk",
            scientificName: "Buteo jamaicensis",
            rank: "species",
            path: "animalia.chordata.aves.accipitridae.buteo.buteo_jamaicensis",
            speciesId: "species-red-tailed-hawk"
        )
        let sibling = CommunityTaxonSearchResult(
            taxonId: "taxon-vulture",
            taxonomyVersionId: "taxonomy-v1",
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

    @Test func communityIdentificationDecodesVersionAndRoleMetadata() throws {
        let json = """
        {
          "id": "identification-1",
          "user_id": "user-1",
          "author_name": "Avery",
          "author_avatar_url": null,
          "taxon_id": "taxon-1",
          "taxonomy_version_id": "taxonomy-v1",
          "common_name": "Red-tailed Hawk",
          "scientific_name": "Buteo jamaicensis",
          "rank": "species",
          "disagreement_mode": "implicit_support",
          "role_label": "leading",
          "is_genus_best_possible": false,
          "reasoning": null,
          "created_at": "2026-06-20T12:00:00Z",
          "withdrawn_at": null,
          "is_viewer": true
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let identification = try decoder.decode(CommunityIdentification.self, from: json)

        #expect(identification.taxonomyVersionId == "taxonomy-v1")
        #expect(identification.displayRole == "Leading")
    }
}

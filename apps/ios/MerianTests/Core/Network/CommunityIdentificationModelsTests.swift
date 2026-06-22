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
        #expect(identification.roleLabel == "leading")
    }

    @Test func communityTaxonSearchResultDecodesOptionalSuggestionMetadata() throws {
        let searchJson = """
        {
          "taxon_id": "taxon-plain",
          "taxonomy_version_id": "taxonomy-v1",
          "common_name": "Red-tailed Hawk",
          "scientific_name": "Buteo jamaicensis",
          "rank": "species",
          "path": "animalia.chordata.aves.accipitridae.buteo.buteo_jamaicensis",
          "species_id": "species-red-tailed-hawk"
        }
        """.data(using: .utf8)!
        let suggestionJson = """
        {
          "taxon_id": "taxon-suggestion",
          "taxonomy_version_id": "taxonomy-v1",
          "common_name": "Turkey Vulture",
          "scientific_name": "Cathartes aura",
          "rank": "species",
          "path": "animalia.chordata.aves.cathartidae.cathartes.cathartes_aura",
          "species_id": "species-turkey-vulture",
          "suggestion_source": "ai_candidate",
          "confidence_score": 0.82,
          "distinguishing_feature": "longer wings"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let searchResult = try decoder.decode(CommunityTaxonSearchResult.self, from: searchJson)
        let suggestion = try decoder.decode(CommunityTaxonSearchResult.self, from: suggestionJson)

        #expect(searchResult.suggestionSource == nil)
        #expect(searchResult.confidenceScore == nil)
        #expect(suggestion.suggestionSource == .aiCandidate)
        #expect(suggestion.suggestionSource?.displayLabel == "Alternative from scan analysis")
        #expect(suggestion.confidenceScore == 0.82)
        #expect(suggestion.distinguishingFeature == "longer wings")
    }

    @Test func communityDetailDecodesSuggestedTaxa() throws {
        let json = """
        {
          "request_id": "request-1",
          "post_id": "post-1",
          "scan_id": "scan-1",
          "hero_image_url": "https://media.merian.app/test.webp",
          "requested_at": "2026-06-20T12:00:00Z",
          "status": "needs_id",
          "note": null,
          "author_user_id": "user-1",
          "author_name": "Avery",
          "author_username": "avery",
          "author_avatar_url": null,
          "author_is_pro": false,
          "taxonomy_version_id": "taxonomy-v1",
          "projection_state": "community_needs_id",
          "consensus_processing_state": "idle",
          "current_taxon_id": "taxon-1",
          "current_common_name": "Red-tailed Hawk",
          "current_scientific_name": "Buteo jamaicensis",
          "current_rank": "species",
          "current_path": "animalia.chordata.aves.accipitridae.buteo.buteo_jamaicensis",
          "initial_taxon_id": "taxon-1",
          "initial_common_name": "Red-tailed Hawk",
          "initial_scientific_name": "Buteo jamaicensis",
          "initial_rank": "species",
          "initial_path": "animalia.chordata.aves.accipitridae.buteo.buteo_jamaicensis",
          "resolved_taxon_id": null,
          "consensus_score": null,
          "identification_count": 0,
          "viewer_identification_id": null,
          "public_location_label": "Austin, TX",
          "location_sharing": "open",
          "inference_tier": "pro",
          "suggested_taxa": [
            {
              "taxon_id": "taxon-1",
              "taxonomy_version_id": "taxonomy-v1",
              "common_name": "Red-tailed Hawk",
              "scientific_name": "Buteo jamaicensis",
              "rank": "species",
              "path": "animalia.chordata.aves.accipitridae.buteo.buteo_jamaicensis",
              "species_id": "species-red-tailed-hawk",
              "suggestion_source": "ai_initial",
              "confidence_score": 0.97,
              "distinguishing_feature": "Visible belly band and broad wings match the initial ID."
            }
          ],
          "identifications": []
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let detail = try decoder.decode(CommunityIdentificationDetail.self, from: json)

        #expect(detail.suggestedTaxa?.count == 1)
        #expect(detail.inferenceTier == "pro")
        #expect(detail.suggestedTaxa?.first?.suggestionSource == .aiInitial)
        #expect(detail.suggestedTaxa?.first?.displayName == "Red-tailed Hawk")
        #expect(detail.suggestedTaxa?.first?.confidenceScore == 0.97)
        #expect(detail.suggestedTaxa?.first?.distinguishingFeature == "Visible belly band and broad wings match the initial ID.")
    }
}

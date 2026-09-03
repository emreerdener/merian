import Foundation
import Testing

@testable import Merian

@Suite("Species Dictionary API Models")
struct SpeciesDictionaryAPIModelsTests {
    @Test func testSpeciesDictionaryResponseDecodesReferenceImagesAndLookalikes() throws {
        let data = Data("""
        {
            "schema_version": 1,
            "data": {
                "id": "species-123",
                "scientific_name": "Testus floridus",
                "common_name": "Field Test",
                "content_quality": "complete",
                "alternative_common_names": ["Meadow Test"],
                "taxonomy": {
                    "kingdom": "Plantae",
                    "phylum": "Tracheophyta",
                    "class": "Magnoliopsida",
                    "order": "Testales",
                    "family": "Testaceae",
                    "genus": "Testus"
                },
                "hazard_type": "irritant",
                "iucn_red_list_status": "least concern",
                "wikipedia_url": "https://en.wikipedia.org/wiki/Testus_floridus",
                "wikipedia_overview": "A dictionary test species with enough text to be useful in the overview card.",
                "habitat_description": "Found in open test meadows.",
                "gbif_taxon_key": 42,
                "group_tags": ["plant", "flower"],
                "reference_images": [
                    {
                        "url": "https://media.merian.app/public_uploads/pro/test.webp",
                        "source": "merian",
                        "license": "Used with permission via Naturebook",
                        "attribution": "Explorer ABC123",
                        "author_user_id": "66a06afc-a56f-4d19-bfc3-07cf32c1f458",
                        "author_username": "ayla"
                    },
                    {
                        "url": "https://upload.wikimedia.org/test.jpg",
                        "source": "wikipedia",
                        "license": "CC BY-SA 4.0",
                        "attribution": "Example Photographer",
                        "width": 1200,
                        "height": 800
                    },
                    { "url": "https://static.inaturalist.org/photo.jpg", "source": "gbif" }
                ],
                "similar_species": [
                    {
                        "species_id": "species-minor",
                        "scientific_name": "Testus minor",
                        "common_name": "Small Test",
                        "reference_image_url": "https://example.com/minor.jpg",
                        "iucn_red_list_status": "least concern",
                        "reason": "Similar five-petaled flowers.",
                        "visual_traits": ["five petals", "serrated leaves"],
                        "confidence": 0.78,
                        "source": "model_enrichment",
                        "review_status": "unreviewed",
                        "is_bidirectional": false,
                        "sort_order": 0
                    }
                ]
            }
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeciesDictionaryResponse.self, from: data)

        #expect(response.effectiveSchemaVersion == 1)
        #expect(response.data.scientificName == "Testus floridus")
        #expect(response.data.contentQuality == .complete)
        #expect(response.data.referenceImages.map(\.source) == [.merian, .wikipedia, .gbif])
        #expect(response.data.referenceImages[0].authorUserId == "66a06afc-a56f-4d19-bfc3-07cf32c1f458")
        #expect(response.data.referenceImages[0].authorUsername == "ayla")
        #expect(response.data.referenceImages[1].license == "CC BY-SA 4.0")
        #expect(response.data.referenceImages[1].attribution == "Example Photographer")
        #expect(response.data.referenceImages[1].width == 1200)
        #expect(response.data.referenceImages[1].height == 800)
        #expect(response.data.taxonomy?.genus == "Testus")
        #expect(response.data.similarSpecies.first?.speciesId == "species-minor")
        #expect(response.data.similarSpecies.first?.scientificName == "Testus minor")
        #expect(response.data.similarSpecies.first?.reason == "Similar five-petaled flowers.")
        #expect(response.data.similarSpecies.first?.visualTraits == ["five petals", "serrated leaves"])
        #expect(response.data.similarSpecies.first?.confidence == 0.78)
    }

    @Test func testSpeciesDictionaryResponseDecodesLegacyPayloadWithoutSchemaVersion() throws {
        let data = Data("""
        {
            "data": {
                "id": "species-legacy",
                "scientific_name": "Legacy testus",
                "common_name": "Legacy Test",
                "alternative_common_names": [],
                "taxonomy": null,
                "hazard_type": null,
                "iucn_red_list_status": null,
                "wikipedia_url": null,
                "wikipedia_overview": null,
                "habitat_description": null,
                "gbif_taxon_key": null,
                "group_tags": [],
                "reference_images": [],
                "similar_species": []
            }
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeciesDictionaryResponse.self, from: data)

        #expect(response.schemaVersion == nil)
        #expect(response.effectiveSchemaVersion == 0)
        #expect(response.data.scientificName == "Legacy testus")
        #expect(response.data.contentQuality == nil)
    }

    @Test func testSpeciesDictionaryReferenceImageSourceFallbackIsResilient() throws {
        let data = Data("""
        {
            "data": {
                "id": "species-source",
                "scientific_name": "Source testus",
                "common_name": "Source Test",
                "alternative_common_names": [],
                "taxonomy": null,
                "hazard_type": null,
                "iucn_red_list_status": null,
                "wikipedia_url": null,
                "wikipedia_overview": null,
                "habitat_description": null,
                "gbif_taxon_key": null,
                "group_tags": [],
                "reference_images": [
                    { "url": "https://example.com/future.jpg", "source": "future_source" }
                ],
                "similar_species": []
            }
        }
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeciesDictionaryResponse.self, from: data)

        #expect(response.data.referenceImages.first?.source == .unknown("future_source"))
    }
}

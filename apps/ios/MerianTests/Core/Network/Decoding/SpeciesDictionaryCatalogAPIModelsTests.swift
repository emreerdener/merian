import Foundation
import Testing

@testable import Merian

@Suite("Species Dictionary Catalog API Models")
struct SpeciesDictionaryCatalogAPIModelsTests {
    @Test func catalogResponseDecodesItemsAndCursor() throws {
        let data = Data(
            """
            {
                "schema_version": 1,
                "data": [
                    {
                        "id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                        "scientific_name": "Danaus plexippus",
                        "common_name": "Monarch Butterfly",
                        "content_quality": "complete",
                        "taxonomy": {
                            "kingdom": "Animalia",
                            "phylum": "Arthropoda",
                            "class": "Insecta",
                            "order": "Lepidoptera",
                            "family": "Nymphalidae",
                            "genus": "Danaus"
                        },
                        "iucn_red_list_status": "least concern",
                        "hazard_type": "none",
                        "group_tags": ["animal", "insect"],
                        "reference_image_url": "https://example.com/monarch.jpg"
                    }
                ],
                "next_cursor": {
                    "scientific_name": "Danaus plexippus",
                    "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                    "created_at": "2026-06-01T12:00:00Z"
                }
            }
            """.utf8
        )

        let response = try Self.decoder.decode(
            SpeciesDictionaryCatalogResponse.self,
            from: data
        )

        #expect(response.effectiveSchemaVersion == 1)
        #expect(response.data.first?.commonName == "Monarch Butterfly")
        #expect(response.data.first?.taxonomy?.className == "Insecta")
        #expect(
            response.data.first?.referenceImageUrl
                == "https://example.com/monarch.jpg"
        )
        #expect(response.nextCursor?.scientificName == "Danaus plexippus")
        #expect(response.nextCursor?.createdAt == "2026-06-01T12:00:00Z")
    }

    @Test func overviewResponseDecodesCategoriesAndRegions() throws {
        let data = Data(
            """
            {
                "schema_version": 1,
                "data": {
                    "featured_species": {
                        "id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                        "scientific_name": "Danaus plexippus",
                        "common_name": "Monarch Butterfly",
                        "overview": "The monarch butterfly is a milkweed butterfly known for long-distance migration.",
                        "reference_image_url": "https://example.com/featured.jpg"
                    },
                    "categories": [
                        {
                            "id": "all",
                            "title": "All",
                            "subtitle": "Browse every species in the dictionary",
                            "count": 42,
                            "reference_image_url": "https://example.com/all.jpg",
                            "region": null
                        },
                        {
                            "id": "your_region",
                            "title": "Your Region",
                            "subtitle": "Species associated with United States",
                            "count": 8,
                            "reference_image_url": "https://example.com/local.jpg",
                            "region": "United States",
                            "region_code": "US"
                        },
                        {
                            "id": "recently_added",
                            "title": "Recently added",
                            "subtitle": "Newest entries added to the database",
                            "count": 42,
                            "reference_image_url": "https://example.com/recent.jpg",
                            "region": null
                        }
                    ],
                    "groups": [
                        {
                            "id": "birds",
                            "title": "Birds",
                            "count": 12,
                            "reference_image_url": "https://example.com/bird.jpg"
                        }
                    ],
                    "regions": [
                        {
                            "id": "region:united%20states",
                            "title": "United States",
                            "count": 8,
                            "reference_image_url": "https://example.com/local.jpg",
                            "code": "US"
                        }
                    ]
                }
            }
            """.utf8
        )

        let response = try Self.decoder.decode(
            SpeciesDictionaryOverviewResponse.self,
            from: data
        )

        #expect(response.effectiveSchemaVersion == 1)
        #expect(
            response.data.featuredSpecies?.commonName == "Monarch Butterfly"
        )
        #expect(response.data.categories.first?.id == .all)
        #expect(response.data.categories[1].id == .yourRegion)
        #expect(response.data.categories[1].region == "United States")
        #expect(response.data.categories[1].regionCode == "US")
        #expect(response.data.categories.last?.id == .recentlyAdded)
        #expect(response.data.groups.first?.title == "Birds")
        #expect(response.data.regions.first?.title == "United States")
        #expect(response.data.regions.first?.code == "US")
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

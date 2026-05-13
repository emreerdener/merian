import Foundation
import Testing
@testable import Merian

@MainActor
struct SpeciesDictionaryTests {
    init() {
        MockURLProtocol.mockEndpoints = [:]

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        MerianNetworkClient.shared.overridingSession = URLSession(configuration: config)
        MerianNetworkClient.shared.resetSpeciesDictionaryCacheForTesting()
    }

    @Test func testSpeciesDictionaryResponseDecodesReferenceImagesAndLookalikes() throws {
        let data = """
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
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeciesDictionaryResponse.self, from: data)

        #expect(response.effectiveSchemaVersion == 1)
        #expect(response.data.scientificName == "Testus floridus")
        #expect(response.data.contentQuality == .complete)
        #expect(response.data.effectiveContentQuality == .complete)
        #expect(response.data.referenceImages.map(\.source) == [.wikipedia, .gbif])
        #expect(response.data.referenceImages.first?.license == "CC BY-SA 4.0")
        #expect(response.data.referenceImages.first?.attribution == "Example Photographer")
        #expect(response.data.referenceImages.first?.attributionCaption == "Example Photographer - CC BY-SA 4.0")
        #expect(response.data.referenceImages.first?.width == 1200)
        #expect(response.data.referenceImages.first?.height == 800)
        #expect(response.data.taxonomyData?.genus == "Testus")
        #expect(response.data.similarSpeciesData?.entries.first?.speciesId == "species-minor")
        #expect(response.data.similarSpeciesData?.entries.first?.scientificName == "Testus minor")
        #expect(response.data.similarSpeciesData?.entries.first?.similarityReason == "Similar five-petaled flowers.")
        #expect(response.data.similarSpeciesData?.entries.first?.visualTraits == ["five petals", "serrated leaves"])
        #expect(response.data.similarSpeciesData?.entries.first?.similarityConfidence == 0.78)
    }

    @Test func testSpeciesDictionaryResponseDecodesLegacyPayloadWithoutSchemaVersion() throws {
        let data = """
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
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeciesDictionaryResponse.self, from: data)

        #expect(response.schemaVersion == nil)
        #expect(response.effectiveSchemaVersion == 0)
        #expect(response.data.scientificName == "Legacy testus")
        #expect(response.data.contentQuality == nil)
        #expect(response.data.effectiveContentQuality == .needsEnrichment)
    }

    @Test func testGetSpeciesDictionaryConstructsPayloadAndParsesResponse() async throws {
        let testData = """
        {
            "data": {
                "id": "species-123",
                "scientific_name": "Testus floridus",
                "common_name": "Field Test",
                "alternative_common_names": [],
                "taxonomy": null,
                "hazard_type": "none",
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
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        MockURLProtocol.mockEndpoints["/species-dictionary"] = { request in
            #expect(request.url?.path.hasSuffix("/species-dictionary") == true)
            #expect(request.httpMethod == "POST")

            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["scientific_name"] as? String == "Testus floridus")
            return (mockResponse, testData)
        }

        let species = try await MerianNetworkClient.shared.getSpeciesDictionary(scientificName: "Testus floridus")

        #expect(species.id == "species-123")
        #expect(species.commonName == "Field Test")
    }

    @Test func testSpeciesDictionaryRouteCarriesAnalyticsEntryPoint() {
        let route = SpeciesDictionaryRoute(
            scientificName: "Testus floridus",
            speciesId: " species-123 ",
            entryPoint: .exploreDetailSimilarSpecies
        )
        let defaultRoute = SpeciesDictionaryRoute(scientificName: "Testus floridus")

        #expect(route.speciesId == "species-123")
        #expect(route.entryPoint == .exploreDetailSimilarSpecies)
        #expect(defaultRoute.entryPoint == .unknown)
    }

    @Test func testGetSpeciesDictionaryCanPreferSpeciesIdPayload() async throws {
        let testData = """
        {
            "data": {
                "id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                "scientific_name": "Testus floridus",
                "common_name": "Field Test",
                "alternative_common_names": [],
                "taxonomy": null,
                "hazard_type": "none",
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
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        MockURLProtocol.mockEndpoints["/species-dictionary"] = { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["species_id"] as? String == "1cf79982-e5ee-4e3d-8d65-274527e6ae01")
            #expect(payload["scientific_name"] as? String == "Testus floridus")
            return (mockResponse, testData)
        }

        let species = try await MerianNetworkClient.shared.getSpeciesDictionary(
            speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
            scientificName: "Testus floridus"
        )

        #expect(species.id == "1cf79982-e5ee-4e3d-8d65-274527e6ae01")
    }

    @Test func testGetSpeciesDictionaryMemoizesRecentResponseByScientificName() async throws {
        let testData = """
        {
            "schema_version": 1,
            "data": {
                "id": "species-cache",
                "scientific_name": "Cache testus",
                "common_name": "Cache Test",
                "alternative_common_names": [],
                "taxonomy": null,
                "hazard_type": "none",
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
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        var requestCount = 0

        MockURLProtocol.mockEndpoints["/species-dictionary"] = { request in
            requestCount += 1
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["scientific_name"] as? String == "Cache testus")
            return (mockResponse, testData)
        }

        let first = try await MerianNetworkClient.shared.getSpeciesDictionary(scientificName: "Cache testus")
        let second = try await MerianNetworkClient.shared.getSpeciesDictionary(scientificName: "  Cache   testus  ")

        #expect(first.id == "species-cache")
        #expect(second.id == "species-cache")
        #expect(requestCount == 1)
    }

    @Test func testSpeciesDictionaryViewModelLoadsSpecies() async throws {
        MockURLProtocol.mockEndpoints["/species-dictionary"] = { _ in
            let data = """
            {
                "data": {
                    "id": "species-123",
                    "scientific_name": "Testus floridus",
                    "common_name": "Field Test",
                    "alternative_common_names": [],
                    "taxonomy": null,
                    "hazard_type": "none",
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
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let viewModel = SpeciesDictionaryPageViewModel(scientificName: "Testus floridus")
        await viewModel.load()

        guard case .loaded(let species) = viewModel.state else {
            Issue.record("Expected loaded species state")
            return
        }
        #expect(species.scientificName == "Testus floridus")
    }

    @Test func testSpeciesDictionaryViewModelMaps404ToNotFound() async {
        MockURLProtocol.mockEndpoints["/species-dictionary"] = { _ in
            let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"error":"Species not found"}"#.utf8))
        }

        let viewModel = SpeciesDictionaryPageViewModel(scientificName: "Missing species")
        await viewModel.load()

        #expect(viewModel.state == .notFound)
    }
}

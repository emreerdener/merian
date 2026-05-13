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
    }

    @Test func testSpeciesDictionaryResponseDecodesReferenceImagesAndLookalikes() throws {
        let data = """
        {
            "data": {
                "id": "species-123",
                "scientific_name": "Testus floridus",
                "common_name": "Field Test",
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
                    { "url": "https://upload.wikimedia.org/test.jpg", "source": "wikipedia" },
                    { "url": "https://static.inaturalist.org/photo.jpg", "source": "gbif" }
                ],
                "similar_species": [
                    {
                        "scientific_name": "Testus minor",
                        "common_name": "Small Test",
                        "reference_image_url": "https://example.com/minor.jpg",
                        "iucn_red_list_status": "least concern"
                    }
                ]
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeciesDictionaryResponse.self, from: data)

        #expect(response.data.scientificName == "Testus floridus")
        #expect(response.data.referenceImages.map(\.source) == [.wikipedia, .gbif])
        #expect(response.data.taxonomyData?.genus == "Testus")
        #expect(response.data.similarSpeciesData?.entries.first?.scientificName == "Testus minor")
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

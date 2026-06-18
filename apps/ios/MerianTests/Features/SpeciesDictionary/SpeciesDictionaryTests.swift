import CoreGraphics
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
                        "url": "https://media.merian.app/public_uploads/pro/test.webp",
                        "source": "merian",
                        "license": "Used with permission via Merian",
                        "attribution": "Explorer ABC123"
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
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeciesDictionaryResponse.self, from: data)

        #expect(response.effectiveSchemaVersion == 1)
        #expect(response.data.scientificName == "Testus floridus")
        #expect(response.data.contentQuality == .complete)
        #expect(response.data.effectiveContentQuality == .complete)
        #expect(response.data.referenceImages.map(\.source) == [.merian, .wikipedia, .gbif])
        #expect(response.data.referenceImages[0].source.label == "Merian")
        #expect(response.data.referenceImages[0].attributionCaption == "Explorer ABC123 - Used with permission via Merian")
        #expect(response.data.referenceImages[1].license == "CC BY-SA 4.0")
        #expect(response.data.referenceImages[1].attribution == "Example Photographer")
        #expect(response.data.referenceImages[1].attributionCaption == "Example Photographer - CC BY-SA 4.0")
        #expect(response.data.referenceImages[1].width == 1200)
        #expect(response.data.referenceImages[1].height == 800)
        #expect(response.data.taxonomyData?.genus == "Testus")
        #expect(response.data.similarSpeciesData?.entries.first?.speciesId == "species-minor")
        #expect(response.data.similarSpeciesData?.entries.first?.scientificName == "Testus minor")
        #expect(response.data.similarSpeciesData?.entries.first?.similarityReason == "Similar five-petaled flowers.")
        #expect(response.data.similarSpeciesData?.entries.first?.visualTraits == ["five petals", "serrated leaves"])
        #expect(response.data.similarSpeciesData?.entries.first?.similarityConfidence == 0.78)
    }

    @Test func testAlternativeCommonNamesLineSanitizesNames() {
        let displayNames = AlternativeCommonNamesLine.displayNames(
            from: [
                "Field Test",
                " Meadow Test, Prairie Test ",
                "meadow test",
                "",
                "Garden Test"
            ],
            excluding: "Field Test"
        )

        #expect(displayNames == ["Meadow Test", "Prairie Test", "Garden Test"])
    }

    @Test func testAlternativeCommonNamesLineTreatsDashVariantsAsDuplicates() {
        let displayNames = AlternativeCommonNamesLine.displayNames(
            from: [
                "Desert-rose",
                "Desert–Rose",
                "Sabi Star",
                "Sabi-star"
            ],
            excluding: "Desert Rose"
        )

        #expect(displayNames == ["Sabi Star"])
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

    @Test func testSpeciesDictionaryReferenceImageSourceFallbackIsResilient() throws {
        let data = """
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
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeciesDictionaryResponse.self, from: data)

        #expect(response.data.referenceImages.first?.source == .unknown("future_source"))
        #expect(response.data.referenceImages.first?.source.label == "Reference")
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

    @Test func testSpeciesObservationStatsResponseDecodesPublicCharts() throws {
        let data = """
        {
            "schema_version": 1,
            "data": {
                "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                "scientific_name": "Danaus plexippus",
                "source": {
                    "provider": "inaturalist",
                    "scope": "global",
                    "inaturalist_taxon_id": 48662,
                    "fetched_at": "2026-05-17T12:00:00.000Z"
                },
                "status": "partial",
                "total_observations": 450448,
                "last_observation_date": "2026-05-17",
                "fetched_at": "2026-05-17T12:00:00.000Z",
                "provider_errors": ["life stage bucket unavailable"],
                "seasonality": [
                    { "month": 1, "count": 10 },
                    { "month": 2, "count": 20 }
                ],
                "history": [
                    { "year": 2026, "month": 5, "count": 40 }
                ],
                "life_stage": [
                    {
                        "key": "adult",
                        "label": "Adult",
                        "values": [{ "month": 8, "count": 100 }]
                    }
                ],
                "sex": [
                    {
                        "key": "female",
                        "label": "Female",
                        "values": [{ "month": 8, "count": 12 }]
                    }
                ]
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeciesObservationStatsResponse.self, from: data)

        #expect(response.effectiveSchemaVersion == 1)
        #expect(response.data.scientificName == "Danaus plexippus")
        #expect(response.data.status == .partial)
        #expect(response.data.totalObservations == 450448)
        #expect(response.data.source.inaturalistTaxonId == 48662)
        #expect(response.data.lifeStage.first?.label == "Adult")
    }

    @Test func testGetSpeciesObservationStatsConstructsPayloadAndMemoizes() async throws {
        let testData = """
        {
            "schema_version": 1,
            "data": {
                "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                "scientific_name": "Danaus plexippus",
                "source": {
                    "provider": "inaturalist",
                    "scope": "global",
                    "inaturalist_taxon_id": 48662,
                    "fetched_at": "2026-05-17T12:00:00.000Z"
                },
                "status": "fresh",
                "total_observations": 450448,
                "last_observation_date": "2026-05-17",
                "fetched_at": "2026-05-17T12:00:00.000Z",
                "provider_errors": [],
                "seasonality": [{ "month": 5, "count": 1200 }],
                "history": [{ "year": 2026, "month": 5, "count": 1200 }],
                "life_stage": [],
                "sex": []
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

        MockURLProtocol.mockEndpoints["/species-observation-stats"] = { request in
            requestCount += 1
            #expect(request.url?.path.hasSuffix("/species-observation-stats") == true)
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)

            let url = try #require(request.url)
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            })
            #expect(queryItems["species_id"] == "1cf79982-e5ee-4e3d-8d65-274527e6ae01")
            #expect(queryItems["scientific_name"] == "Danaus plexippus")
            #expect(MockURLProtocol.bodyData(for: request) == nil)
            return (mockResponse, testData)
        }

        let first = try await MerianNetworkClient.shared.getSpeciesObservationStats(
            speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
            scientificName: "Danaus plexippus"
        )
        let second = try await MerianNetworkClient.shared.getSpeciesObservationStats(
            speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
            scientificName: "  Danaus   plexippus  "
        )

        #expect(first.totalObservations == 450448)
        #expect(second.totalObservations == 450448)
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

    @Test func testSpeciesDictionaryCatalogResponseDecodesItemsAndCursor() throws {
        let data = """
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
                "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01"
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeciesDictionaryCatalogResponse.self, from: data)

        #expect(response.effectiveSchemaVersion == 1)
        #expect(response.data.first?.commonName == "Monarch Butterfly")
        #expect(response.data.first?.taxonomy?.className == "Insecta")
        #expect(response.data.first?.referenceImageUrl == "https://example.com/monarch.jpg")
        #expect(response.nextCursor?.scientificName == "Danaus plexippus")
        #expect(response.data.first?.dictionaryRoute.entryPoint == .exploreDictionaryCatalog)
    }

    @Test func testGetSpeciesDictionaryCatalogConstructsPayloadAndParsesResponse() async throws {
        let testData = """
        {
            "schema_version": 1,
            "data": [],
            "next_cursor": {
                "scientific_name": "Danaus plexippus",
                "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01"
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
            #expect(request.httpMethod == "POST")
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let cursor = try #require(payload["cursor"] as? [String: Any])

            #expect(payload["mode"] as? String == "catalog")
            #expect(payload["query"] as? String == "Danaus")
            #expect(payload["limit"] as? Int == 25)
            #expect(cursor["scientific_name"] as? String == "Danaus plexippus")
            #expect(cursor["species_id"] as? String == "1cf79982-e5ee-4e3d-8d65-274527e6ae01")
            return (mockResponse, testData)
        }

        let response = try await MerianNetworkClient.shared.getSpeciesDictionaryCatalog(
            query: " Danaus ",
            limit: 25,
            cursor: SpeciesDictionaryCatalogCursor(
                scientificName: "Danaus plexippus",
                speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01"
            )
        )

        #expect(response.nextCursor?.speciesId == "1cf79982-e5ee-4e3d-8d65-274527e6ae01")
    }

    @Test func testSpeciesDictionaryTreeResponseDecodesGraphPayload() throws {
        let data = """
        {
            "schema_version": 1,
            "data": {
                "nodes": [
                    {
                        "id": "taxonomy:genus:animalia/arthropoda/insecta/lepidoptera/nymphalidae/danaus",
                        "rank": "genus",
                        "title": "Danaus",
                        "subtitle": "Genus",
                        "parent_id": "taxonomy:family:animalia/arthropoda/insecta/lepidoptera/nymphalidae",
                        "species_count": 2,
                        "child_count": 2,
                        "lineage": {
                            "kingdom": "Animalia",
                            "phylum": "Arthropoda",
                            "class": "Insecta",
                            "order": "Lepidoptera",
                            "family": "Nymphalidae",
                            "genus": "Danaus"
                        },
                        "representative_species": {
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
                        },
                        "species": null
                    }
                ],
                "edges": [
                    {
                        "from": "taxonomy:family:animalia/arthropoda/insecta/lepidoptera/nymphalidae",
                        "to": "taxonomy:genus:animalia/arthropoda/insecta/lepidoptera/nymphalidae/danaus"
                    }
                ]
            }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeciesDictionaryTreeResponse.self, from: data)

        #expect(response.effectiveSchemaVersion == 1)
        #expect(response.data.nodes.first?.rank == .genus)
        #expect(response.data.nodes.first?.lineage?.className == "Insecta")
        #expect(response.data.nodes.first?.representativeSpecies?.dictionaryRoute.scientificName == "Danaus plexippus")
        #expect(response.data.edges.first?.id.contains("->") == true)
    }

    @Test func testGetSpeciesDictionaryTreeConstructsPayloadAndParsesResponse() async throws {
        let testData = """
        {
            "schema_version": 1,
            "data": {
                "nodes": [],
                "edges": []
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
            #expect(request.httpMethod == "POST")
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

            #expect(payload["mode"] as? String == "tree")
            #expect(payload["limit"] == nil)
            #expect(payload["query"] == nil)
            return (mockResponse, testData)
        }

        let response = try await MerianNetworkClient.shared.getSpeciesDictionaryTree()

        #expect(response.data.nodes.isEmpty)
        #expect(response.data.edges.isEmpty)
    }

    @Test func testTaxonomyTreeGraphSearchVisibilityLayoutAndRouting() throws {
        let graph = TaxonomyTreeGraphBuilder.build(from: Self.taxonomyTreePayload())
        let danausID = "taxonomy:genus:animalia/arthropoda/insecta/lepidoptera/nymphalidae/danaus"
        let monarchID = "species:1cf79982-e5ee-4e3d-8d65-274527e6ae01"
        let danausNode = try #require(graph.node(id: danausID))
        let monarchNode = try #require(graph.node(id: monarchID))

        #expect(danausNode.speciesCount == 2)
        #expect(monarchNode.dictionaryRoute?.scientificName == "Danaus plexippus")
        #expect(graph.searchResults(for: "monarch").first?.id == monarchID)
        #expect(graph.visibleNodeIDs(focusedNodeID: nil, selectedNodeID: nil, scale: 0.6).contains(monarchID))
        #expect(graph.visibleNodeIDs(focusedNodeID: danausID, selectedNodeID: nil, scale: 0.6).count == graph.nodes.count)

        let layout = TaxonomyTreeLayout.make(
            graph: graph,
            visibleNodeIDs: graph.visibleNodeIDs(focusedNodeID: nil, selectedNodeID: monarchID, scale: 1.2),
            minimumSize: CGSize(width: 320, height: 480)
        )
        let genusPosition = try #require(layout.positions[danausID])
        let speciesPosition = try #require(layout.positions[monarchID])

        #expect(genusPosition.x < speciesPosition.x)
        #expect(layout.size.width >= 320)
        #expect(layout.size.height >= 480)
    }

    @Test func testTaxonomyTreeZoomPreservesAnchorContentPoint() {
        let viewModel = TaxonomyTreeCanvasViewModel()
        viewModel.scale = 1
        viewModel.baseScale = 1
        viewModel.offset = CGSize(width: -120, height: 80)

        let anchor = CGPoint(x: 180, y: 260)
        let before = CGPoint(
            x: (anchor.x - viewModel.offset.width) / viewModel.scale,
            y: (anchor.y - viewModel.offset.height) / viewModel.scale
        )

        viewModel.zoom(by: 1.5, anchoredAt: anchor)

        let after = CGPoint(
            x: (anchor.x - viewModel.offset.width) / viewModel.scale,
            y: (anchor.y - viewModel.offset.height) / viewModel.scale
        )
        #expect(abs(before.x - after.x) < 0.001)
        #expect(abs(before.y - after.y) < 0.001)
        #expect(viewModel.scale == 1.5)
    }

    private static func taxonomyTreePayload() -> SpeciesDictionaryTreePayload {
        let taxonomy = SpeciesDictionaryTaxonomy(
            kingdom: "Animalia",
            phylum: "Arthropoda",
            className: "Insecta",
            order: "Lepidoptera",
            family: "Nymphalidae",
            genus: "Danaus"
        )
        let monarch = SpeciesDictionaryTreeSpecies(
            id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly",
            contentQuality: .complete,
            taxonomy: taxonomy,
            iucnRedListStatus: "least concern",
            hazardType: "none",
            groupTags: ["animal", "insect"],
            referenceImageUrl: "https://example.com/monarch.jpg"
        )
        let queen = SpeciesDictionaryTreeSpecies(
            id: "2cf79982-e5ee-4e3d-8d65-274527e6ae02",
            scientificName: "Danaus gilippus",
            commonName: "Queen Butterfly",
            contentQuality: .complete,
            taxonomy: taxonomy,
            iucnRedListStatus: nil,
            hazardType: nil,
            groupTags: ["animal", "insect"],
            referenceImageUrl: nil
        )
        let lineageIDs = [
            "taxonomy:kingdom:animalia",
            "taxonomy:phylum:animalia/arthropoda",
            "taxonomy:class:animalia/arthropoda/insecta",
            "taxonomy:order:animalia/arthropoda/insecta/lepidoptera",
            "taxonomy:family:animalia/arthropoda/insecta/lepidoptera/nymphalidae",
            "taxonomy:genus:animalia/arthropoda/insecta/lepidoptera/nymphalidae/danaus"
        ]
        let ranks: [SpeciesDictionaryTreeRank] = [.kingdom, .phylum, .className, .order, .family, .genus]
        let titles = ["Animalia", "Arthropoda", "Insecta", "Lepidoptera", "Nymphalidae", "Danaus"]
        let nodes = zip(lineageIDs.indices, lineageIDs).map { pair in
            let index = pair.0
            let id = pair.1
            return SpeciesDictionaryTreeNodePayload(
                id: id,
                rank: ranks[index],
                title: titles[index],
                subtitle: ranks[index].title,
                parentId: index == 0 ? nil : lineageIDs[index - 1],
                speciesCount: 2,
                childCount: index == lineageIDs.count - 1 ? 2 : 1,
                lineage: taxonomy,
                representativeSpecies: monarch,
                species: nil
            )
        } + [
            SpeciesDictionaryTreeNodePayload(
                id: "species:1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                rank: .species,
                title: "Monarch Butterfly",
                subtitle: "Danaus plexippus",
                parentId: lineageIDs.last,
                speciesCount: 1,
                childCount: 0,
                lineage: taxonomy,
                representativeSpecies: monarch,
                species: monarch
            ),
            SpeciesDictionaryTreeNodePayload(
                id: "species:2cf79982-e5ee-4e3d-8d65-274527e6ae02",
                rank: .species,
                title: "Queen Butterfly",
                subtitle: "Danaus gilippus",
                parentId: lineageIDs.last,
                speciesCount: 1,
                childCount: 0,
                lineage: taxonomy,
                representativeSpecies: queen,
                species: queen
            )
        ]
        let lineageEdges = zip(lineageIDs.dropLast(), lineageIDs.dropFirst()).map {
            SpeciesDictionaryTreeEdgePayload(from: $0, to: $1)
        }
        let speciesEdges = [
            SpeciesDictionaryTreeEdgePayload(from: lineageIDs.last!, to: "species:1cf79982-e5ee-4e3d-8d65-274527e6ae01"),
            SpeciesDictionaryTreeEdgePayload(from: lineageIDs.last!, to: "species:2cf79982-e5ee-4e3d-8d65-274527e6ae02")
        ]

        return SpeciesDictionaryTreePayload(nodes: nodes, edges: lineageEdges + speciesEdges)
    }
}

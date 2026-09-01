import Foundation
@testable import Merian
import Testing

@Suite("Species Dictionary Tests")
@MainActor
struct SpeciesDictionaryTests {
    private let networkClient: MerianNetworkClient
    private let mockTransport: ScopedMockTransport

    init() {
        let mockTransport = ScopedMockTransport()
        let networkClient = MerianNetworkClient()
        networkClient.overridingSession = mockTransport.makeSession()
        networkClient.overridingAuthUserID = UUID(
            uuidString: "22222222-2222-4222-8222-222222222222"
        )
        networkClient.resetSpeciesDictionaryCacheForTesting()
        self.mockTransport = mockTransport
        self.networkClient = networkClient
    }

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

    @Test func testGetSpeciesDictionaryConstructsPayloadAndParsesResponse() async throws {
        let testData = Data("""
        {
            "schema_version": 1,
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
        """.utf8)
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        mockTransport.register(path: "/species-dictionary") { request in
            #expect(request.url?.path.hasSuffix("/species-dictionary") == true)
            #expect(request.httpMethod == "POST")

            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["scientific_name"] as? String == "Testus floridus")
            return (mockResponse, testData)
        }

        let species = try await networkClient.getSpeciesDictionary(scientificName: "Testus floridus")

        #expect(species.id == "1cf79982-e5ee-4e3d-8d65-274527e6ae01")
        #expect(species.commonName == "Field Test")
    }

    @Test func testGetSpeciesDictionaryCanPreferSpeciesIdPayload() async throws {
        let testData = Data("""
        {
            "schema_version": 1,
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
        """.utf8)
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        mockTransport.register(path: "/species-dictionary") { request in
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["species_id"] as? String == "1cf79982-e5ee-4e3d-8d65-274527e6ae01")
            #expect(payload["scientific_name"] as? String == "Testus floridus")
            return (mockResponse, testData)
        }

        let species = try await networkClient.getSpeciesDictionary(
            speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
            scientificName: "Testus floridus"
        )

        #expect(species.id == "1cf79982-e5ee-4e3d-8d65-274527e6ae01")
    }

    @Test func testGetSpeciesDictionaryMemoizesRecentResponseByScientificName() async throws {
        let testData = Data("""
        {
            "schema_version": 1,
            "data": {
                "id": "3cf79982-e5ee-4e3d-8d65-274527e6ae03",
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
        """.utf8)
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        var requestCount = 0

        mockTransport.register(path: "/species-dictionary") { request in
            requestCount += 1
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["scientific_name"] as? String == "Cache testus")
            return (mockResponse, testData)
        }

        let first = try await networkClient.getSpeciesDictionary(scientificName: "Cache testus")
        let second = try await networkClient.getSpeciesDictionary(scientificName: "  Cache   testus  ")

        #expect(first.id == "3cf79982-e5ee-4e3d-8d65-274527e6ae03")
        #expect(second.id == "3cf79982-e5ee-4e3d-8d65-274527e6ae03")
        #expect(requestCount == 1)
    }

    @Test func testGetSpeciesDictionaryRejectsUnsupportedSchemaWithoutCaching() async throws {
        let speciesID = "1cf79982-e5ee-4e3d-8d65-274527e6ae01"
        let mockResponse = Self.okResponse
        var responses = [
            Self.detailResponseData(
                schemaVersion: nil,
                id: speciesID,
                scientificName: "Schema testus"
            ),
            Self.detailResponseData(
                schemaVersion: 2,
                id: speciesID,
                scientificName: "Schema testus"
            ),
            Self.detailResponseData(
                schemaVersion: 1,
                id: speciesID,
                scientificName: "Schema testus"
            )
        ]
        var requestCount = 0
        mockTransport.register(path: "/species-dictionary") { _ in
            requestCount += 1
            return (mockResponse, responses.removeFirst())
        }

        for _ in 0..<2 {
            await #expect(throws: MerianError.invalidResponse) {
                try await networkClient.getSpeciesDictionary(
                    scientificName: "Schema testus"
                )
            }
        }
        let species = try await networkClient.getSpeciesDictionary(
            scientificName: "Schema testus"
        )

        #expect(species.id == speciesID)
        #expect(requestCount == 3)
    }

    @Test func testGetSpeciesDictionaryRejectsMismatchedIdentityWithoutCaching() async throws {
        let requestedID = "1cf79982-e5ee-4e3d-8d65-274527e6ae01"
        let mismatchedID = "2cf79982-e5ee-4e3d-8d65-274527e6ae02"
        var responses = [
            Self.detailResponseData(
                schemaVersion: 1,
                id: mismatchedID,
                scientificName: "Wrong testus"
            ),
            Self.detailResponseData(
                schemaVersion: 1,
                id: requestedID,
                scientificName: "Identity testus"
            )
        ]
        var requestCount = 0
        mockTransport.register(path: "/species-dictionary") { _ in
            requestCount += 1
            return (Self.okResponse, responses.removeFirst())
        }

        await #expect(throws: MerianError.invalidResponse) {
            try await networkClient.getSpeciesDictionary(
                speciesId: requestedID,
                scientificName: "Identity testus"
            )
        }
        let species = try await networkClient.getSpeciesDictionary(
            speciesId: requestedID,
            scientificName: "Identity testus"
        )

        #expect(species.id == requestedID)
        #expect(requestCount == 2)
    }

    @Test func testGetSpeciesDictionaryAcceptsLocalStaleIDRecoveryWithoutAliasingOldID() async throws {
        let staleID = "1cf79982-e5ee-4e3d-8d65-274527e6ae01"
        let canonicalID = "2cf79982-e5ee-4e3d-8d65-274527e6ae02"
        let responseData = Self.detailResponseData(
            schemaVersion: 1,
            id: canonicalID,
            scientificName: "Recovery testus"
        )
        var requestCount = 0
        mockTransport.register(path: "/species-dictionary") { _ in
            requestCount += 1
            return (Self.okResponse, responseData)
        }

        let recovered = try await networkClient.getSpeciesDictionary(
            speciesId: staleID,
            scientificName: "Recovery testus"
        )
        let canonicalCacheHit = try await networkClient.getSpeciesDictionary(
            speciesId: canonicalID,
            scientificName: "Recovery testus"
        )
        _ = try await networkClient.getSpeciesDictionary(
            speciesId: staleID,
            scientificName: "Recovery testus"
        )

        #expect(recovered.id == canonicalID)
        #expect(canonicalCacheHit.id == canonicalID)
        #expect(requestCount == 2)
    }

    @Test func testGetSpeciesDictionaryNormalizesInvalidIDToNameOnlyExternalLookup() async throws {
        let responseData = Self.detailResponseData(
            schemaVersion: 1,
            id: "external:externalis%20exemplaris",
            scientificName: "Externalis exemplaris"
        )
        var requestCount = 0
        mockTransport.register(path: "/species-dictionary") { request in
            requestCount += 1
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            #expect(payload["species_id"] == nil)
            #expect(
                payload["scientific_name"] as? String
                    == "Externalis exemplaris"
            )
            return (Self.okResponse, responseData)
        }

        let first = try await networkClient.getSpeciesDictionary(
            speciesId: "external:externalis%20exemplaris",
            scientificName: "  Externalis   exemplaris "
        )
        let second = try await networkClient.getSpeciesDictionary(
            scientificName: "Externalis exemplaris"
        )

        #expect(first.id == "external:externalis%20exemplaris")
        #expect(second.id == first.id)
        #expect(requestCount == 1)
        await #expect(throws: MerianError.invalidResponse) {
            try await networkClient.getSpeciesDictionary(
                speciesId: "external:externalis%20exemplaris"
            )
        }
        #expect(requestCount == 1)
    }

    @Test func testSpeciesObservationStatsResponseDecodesPublicCharts() throws {
        let data = Data("""
        {
            "schema_version": 2,
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
        """.utf8)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(SpeciesObservationStatsResponse.self, from: data)

        #expect(response.effectiveSchemaVersion == 2)
        #expect(response.data.scientificName == "Danaus plexippus")
        #expect(response.data.status == .partial)
        #expect(response.data.totalObservations == 450448)
        #expect(response.data.source.inaturalistTaxonId == 48662)
        #expect(response.data.lifeStage.first?.label == "Adult")
    }

    @Test func testGetSpeciesObservationStatsConstructsPayloadAndMemoizes() async throws {
        let testData = Data("""
        {
            "schema_version": 2,
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
        """.utf8)
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        var requestCount = 0

        mockTransport.register(path: "/species-observation-stats") { request in
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

        let first = try await networkClient.getSpeciesObservationStats(
            speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
            scientificName: "Danaus plexippus"
        )
        let second = try await networkClient.getSpeciesObservationStats(
            speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
            scientificName: "  Danaus   plexippus  "
        )

        #expect(first.totalObservations == 450448)
        #expect(second.totalObservations == 450448)
        #expect(requestCount == 1)

        await #expect(throws: MerianError.invalidResponse) {
            try await networkClient.getSpeciesObservationStats(
                speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                scientificName: "   "
            )
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await networkClient.getSpeciesObservationStats(
                speciesId: "not-a-uuid",
                scientificName: "Danaus plexippus"
            )
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await networkClient.getSpeciesObservationStats(
                speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                scientificName: String(repeating: "x", count: 161)
            )
        }
        #expect(requestCount == 1)
    }

    @Test func testGetSpeciesObservationStatsRejectsLegacyOrMismatchedResponses() async throws {
        func responseData(
            schemaVersion: Int,
            speciesId: String,
            scientificName: String
        ) -> Data {
            Data("""
            {
                "schema_version": \(schemaVersion),
                "data": {
                    "species_id": "\(speciesId)",
                    "scientific_name": "\(scientificName)",
                    "source": {
                        "provider": "inaturalist",
                        "scope": "global",
                        "inaturalist_taxon_id": 48662,
                        "fetched_at": "2026-05-17T12:00:00.000Z"
                    },
                    "status": "fresh",
                    "total_observations": 1,
                    "last_observation_date": "2026-05-17",
                    "fetched_at": "2026-05-17T12:00:00.000Z",
                    "provider_errors": [],
                    "seasonality": [],
                    "history": [],
                    "life_stage": [],
                    "sex": []
                }
            }
            """.utf8)
        }

        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        var responses = [
            responseData(
                schemaVersion: 1,
                speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                scientificName: "Danaus plexippus"
            ),
            responseData(
                schemaVersion: 2,
                speciesId: "00000000-0000-4000-8000-000000000999",
                scientificName: "Danaus plexippus"
            )
        ]
        var requestCount = 0
        mockTransport.register(path: "/species-observation-stats") { _ in
            requestCount += 1
            return (mockResponse, responses.removeFirst())
        }

        await #expect(throws: MerianError.invalidResponse) {
            try await networkClient.getSpeciesObservationStats(
                speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                scientificName: "Danaus plexippus"
            )
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await networkClient.getSpeciesObservationStats(
                speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                scientificName: "Danaus plexippus"
            )
        }
        #expect(requestCount == 2)
    }

    private static var okResponse: HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    private static func detailResponseData(
        schemaVersion: Int?,
        id: String,
        scientificName: String
    ) -> Data {
        let schema = schemaVersion.map { "\"schema_version\": \($0)," }
            ?? ""
        return Data("""
        {
            \(schema)
            "data": {
                "id": "\(id)",
                "scientific_name": "\(scientificName)",
                "common_name": "Field Test",
                "content_quality": "complete",
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
    }
}

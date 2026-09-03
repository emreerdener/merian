import Foundation
import Testing

@testable import Merian

@Suite("Species Dictionary Detail Endpoint")
@MainActor
struct SpeciesDictionaryDetailEndpointTests {
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

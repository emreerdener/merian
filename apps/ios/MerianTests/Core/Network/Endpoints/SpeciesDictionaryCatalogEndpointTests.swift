import Foundation
import Testing

@testable import Merian

@Suite("Species Dictionary Catalog Endpoint")
@MainActor
struct SpeciesDictionaryCatalogEndpointTests {
    private let networkClient: MerianNetworkClient
    private let mockTransport: ScopedMockTransport

    init() {
        let mockTransport = ScopedMockTransport()
        let networkClient = MerianNetworkClient()
        networkClient.overridingSession = mockTransport.makeSession()
        networkClient.overridingAuthUserID = UUID(
            uuidString: "22222222-2222-4222-8222-222222222222"
        )
        self.mockTransport = mockTransport
        self.networkClient = networkClient
    }

    @Test func catalogEndpointConstructsPayloadAndParsesResponse() async throws {
        let testData = Data(
            """
            {
                "schema_version": 1,
                "data": [],
                "next_cursor": {
                    "scientific_name": "Danaus plexippus",
                    "species_id": "1cf79982-e5ee-4e3d-8d65-274527e6ae01"
                }
            }
            """.utf8
        )
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        mockTransport.register(path: "/species-dictionary") { request in
            #expect(request.httpMethod == "POST")
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            let cursor = try #require(payload["cursor"] as? [String: Any])

            #expect(payload["mode"] as? String == "catalog")
            #expect(payload["category"] as? String == "group")
            #expect(payload["group"] as? String == "birds")
            #expect(payload["query"] as? String == "Danaus")
            #expect(payload["limit"] as? Int == 25)
            #expect(
                cursor["scientific_name"] as? String == "Danaus plexippus"
            )
            #expect(
                cursor["species_id"] as? String
                    == "1cf79982-e5ee-4e3d-8d65-274527e6ae01"
            )
            #expect(
                cursor["created_at"] as? String
                    == "2026-06-01T12:00:00Z"
            )
            return (mockResponse, testData)
        }

        let response = try await networkClient.getSpeciesDictionaryCatalog(
            category: .group,
            group: " birds ",
            query: " Danaus ",
            limit: 25,
            cursor: SpeciesDictionaryCatalogCursor(
                scientificName: "Danaus plexippus",
                speciesId: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
                createdAt: "2026-06-01T12:00:00Z"
            )
        )

        #expect(
            response.nextCursor?.speciesId
                == "1cf79982-e5ee-4e3d-8d65-274527e6ae01"
        )
    }

    @Test func overviewEndpointConstructsPayloadAndParsesResponse() async throws {
        let testData = Data(
            """
            {
                "schema_version": 1,
                "data": {
                    "categories": [],
                    "regions": []
                }
            }
            """.utf8
        )
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        mockTransport.register(path: "/species-dictionary") { request in
            #expect(request.httpMethod == "POST")
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )

            #expect(payload["mode"] as? String == "overview")
            #expect(payload["user_region"] as? String == "US")
            #expect((payload["cache_buster"] as? String)?.isEmpty == false)
            return (mockResponse, testData)
        }

        let response = try await networkClient.getSpeciesDictionaryOverview(
            userRegion: " US "
        )

        #expect(response.effectiveSchemaVersion == 1)
        #expect(response.data.categories.isEmpty)
    }

    @Test func endpointsRejectMissingOrUnsupportedSchemaVersions() async throws {
        var requestCount = 0
        mockTransport.register(path: "/species-dictionary") { request in
            requestCount += 1
            let body = try #require(MockURLProtocol.bodyData(for: request))
            let payload = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            let responseData: Data
            if payload["mode"] as? String == "catalog" {
                responseData = Data(
                    #"{"data":[],"next_cursor":null}"#.utf8
                )
            } else {
                responseData = Data(
                    #"{"schema_version":2,"data":{"categories":[],"regions":[]}}"#.utf8
                )
            }
            return (Self.okResponse, responseData)
        }

        await #expect(throws: MerianError.invalidResponse) {
            try await networkClient.getSpeciesDictionaryCatalog()
        }
        await #expect(throws: MerianError.invalidResponse) {
            try await networkClient.getSpeciesDictionaryOverview()
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
}
